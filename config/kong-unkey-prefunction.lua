-- Kong pre-function that validates API keys via the Auth Bridge service
-- Adds organization/plan metadata headers for downstream consumers
local http = require "resty.http"
local cjson = require "cjson.safe"

-- Configuration
local AUTH_BRIDGE_URL = os.getenv("AUTH_BRIDGE_URL") or "http://auth-bridge:8081/api/v1/verify"

-- Extract API key from path
local uri = kong.request.get_path()
local m = ngx.re.match(uri, [[^/([^/]+)/[^/]+$]], "jo")

if not m or not m[1] then
    return kong.response.exit(400, {message = "Invalid path format. Use: /<API_KEY>/<CHAIN_SLUG>"})
end

local api_key = m[1]

-- Set header for downstream (masked in logs)
ngx.req.set_header("apikey", api_key)
kong.service.request.set_path("/")
kong.log.set_serialize_value("request.headers.apikey", "[REDACTED]")

-- Verify with auth-bridge
local httpc = http.new()
httpc:set_timeout(5000)

local res, err = httpc:request_uri(AUTH_BRIDGE_URL, {
    method = "POST",
    headers = {["Content-Type"] = "application/json"},
    body = cjson.encode({api_key = api_key})
})

if not res then
    kong.log.err("auth-bridge request failed: ", err)
    return kong.response.exit(502, {message = "Unable to verify API key"})
end

if res.status == 401 then
    return kong.response.exit(401, {message = "Invalid API key", error = "unauthorized"})
end

if res.status ~= 200 then
    kong.log.err("auth-bridge responded with status ", res.status, ": ", res.body)
    return kong.response.exit(502, {message = "Unable to verify API key"})
end

local body = cjson.decode(res.body)
if not body or body.valid ~= true then
    return kong.response.exit(401, {message = "Invalid API key"})
end

-- Set consumer for Kong
if body.owner_id then
    kong.client.authenticate({
        id = body.owner_id,
        custom_id = body.owner_id
    })
end

-- Set metadata headers for rate limiting and routing
if body.meta then
    if body.meta.organizationId then
        kong.service.request.set_header("X-Organization-Id", body.meta.organizationId)
    end
    if body.meta.plan then
        kong.service.request.set_header("X-Plan", body.meta.plan)
    end
    if body.meta.allowedChains then
        kong.service.request.set_header("X-Allowed-Chains", cjson.encode(body.meta.allowedChains))
    end
end

-- Provide normalized fields if present
if body.organization_id then
    kong.service.request.set_header("X-Organization-Id", body.organization_id)
end

kong.log.info("API key verified for owner: ", body.owner_id)
