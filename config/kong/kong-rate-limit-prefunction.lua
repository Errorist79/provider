-- Dynamic Rate Limiting Based on Plan
-- Reads plan from X-Plan header (set by Unkey verification)
-- Applies appropriate rate limits per plan

local cjson = require "cjson.safe"

-- Get plan from header (set by Unkey verification)
local plan = kong.request.get_header("X-Plan") or "free"
local organization_id = kong.request.get_header("X-Organization-Id")

-- Plan-based rate limits (requests per minute)
local PLAN_LIMITS = {
    free = 100,
    basic = 1000,
    pro = 10000,
    enterprise = 100000
}

-- Get rate limit for plan
local rate_limit = PLAN_LIMITS[plan] or PLAN_LIMITS["free"]

-- Extract RPC method for compute unit calculation
local body = kong.request.get_raw_body()
local rpc_method = nil
local compute_units = 1  -- Default CU

if body then
    local decoded = cjson.decode(body)
    if decoded and decoded.method then
        rpc_method = decoded.method

        -- Compute units by method (from database/postgresql/init/02_chains.sql)
        local METHOD_CU = {
            -- Standard methods (1-3 CU)
            eth_blockNumber = 1,
            eth_chainId = 1,
            eth_gasPrice = 1,
            eth_getBalance = 1,
            eth_getCode = 1,
            eth_getTransactionCount = 1,
            eth_call = 2,
            eth_estimateGas = 2,
            eth_sendRawTransaction = 2,
            eth_getBlockByNumber = 3,
            eth_getBlockByHash = 3,
            eth_getTransactionByHash = 2,
            eth_getTransactionReceipt = 2,

            -- Expensive methods (5-10 CU)
            eth_getLogs = 10,
            eth_newFilter = 5,
            eth_getFilterLogs = 10,
            eth_getStorageAt = 5,

            -- Trace methods (50-100 CU)
            debug_traceTransaction = 50,
            debug_traceBlockByNumber = 100,
            debug_traceBlockByHash = 100,
            trace_transaction = 50,
            trace_block = 100,
            trace_filter = 100
        }

        compute_units = METHOD_CU[rpc_method] or 1
    end
end

-- Set headers for downstream processing and logging
kong.service.request.set_header("X-Rate-Limit", tostring(rate_limit))
kong.service.request.set_header("X-RPC-Method", rpc_method or "unknown")
kong.service.request.set_header("X-Compute-Units", tostring(compute_units))

-- Check if method requires special access (archive/trace)
if compute_units >= 50 then
    -- Trace methods require enterprise or pro plan
    if plan ~= "pro" and plan ~= "enterprise" then
        return kong.response.exit(403, {
            message = "Trace methods require Pro or Enterprise plan",
            error = "insufficient_plan",
            method = rpc_method,
            current_plan = plan,
            required_plan = "pro"
        })
    end
end

if compute_units >= 5 and compute_units < 50 then
    -- Archive methods require basic or higher
    if plan == "free" then
        return kong.response.exit(403, {
            message = "Archive methods require Basic plan or higher",
            error = "insufficient_plan",
            method = rpc_method,
            current_plan = plan,
            required_plan = "basic"
        })
    end
end

-- For expensive methods, check compute unit quota
if compute_units >= 10 then
    kong.log.info("Expensive method detected: ", rpc_method, " (", compute_units, " CU) for plan: ", plan)
end
