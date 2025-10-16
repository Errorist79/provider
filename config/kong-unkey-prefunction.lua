-- Kong pre-function for Unkey verification with Redis cache
-- This runs in the access phase and verifies API keys with Unkey

local http = require "resty.http"
local cjson = require "cjson.safe"
local redis = require "resty.redis"

-- Configuration
local UNKEY_VERIFY_URL = os.getenv("UNKEY_VERIFY_URL") or "http://unkey:3000/api/v1/keys.verifyKey"
local CACHE_TTL = tonumber(os.getenv("UNKEY_CACHE_TTL")) or 60
local REDIS_HOST = os.getenv("REDIS_HOST") or "redis"
local REDIS_PORT = tonumber(os.getenv("REDIS_PORT")) or 6379
local REDIS_PASSWORD = os.getenv("REDIS_PASSWORD")

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

-- Cache key
local cache_key = "unkey:verify:" .. ngx.md5(api_key)

-- Try Redis cache first
local red = redis:new()
red:set_timeout(1000)

local ok, err = red:connect(REDIS_HOST, REDIS_PORT)
if ok and REDIS_PASSWORD then
    red:auth(REDIS_PASSWORD)
end

local cached_data = nil
if ok then
    local cached, err = red:get(cache_key)
    if cached and cached ~= ngx.null then
        cached_data = cjson.decode(cached)
        kong.log.debug("Cache hit for API key")
    end
end

-- If not in cache, verify with Unkey
if not cached_data then
    kong.log.debug("Cache miss - verifying with Unkey")

    local httpc = http.new()
    httpc:set_timeout(5000)

    local res, err = httpc:request_uri(UNKEY_VERIFY_URL, {
        method = "POST",
        headers = {["Content-Type"] = "application/json"},
        body = cjson.encode({key = api_key})
    })

    if not res or res.status ~= 200 then
        return kong.response.exit(401, {message = "Invalid API key", error = "unauthorized"})
    end

    local body = cjson.decode(res.body)
    if not body or not body.valid then
        return kong.response.exit(401, {message = body.message or "Invalid API key"})
    end

    cached_data = body

    -- Cache the result
    if ok then
        red:setex(cache_key, CACHE_TTL, cjson.encode(body))
    end
end

-- Set consumer for Kong
if cached_data.ownerId then
    kong.client.authenticate({
        id = cached_data.ownerId,
        custom_id = cached_data.ownerId
    })
end

-- Set metadata headers for rate limiting and routing
if cached_data.meta then
    if cached_data.meta.organizationId then
        kong.service.request.set_header("X-Organization-Id", cached_data.meta.organizationId)
    end
    if cached_data.meta.plan then
        kong.service.request.set_header("X-Plan", cached_data.meta.plan)
    end
    if cached_data.meta.allowedChains then
        kong.service.request.set_header("X-Allowed-Chains", cjson.encode(cached_data.meta.allowedChains))
    end
end

-- Close Redis connection
if ok then
    red:set_keepalive(10000, 100)
end

kong.log.info("API key verified for owner: ", cached_data.ownerId)
