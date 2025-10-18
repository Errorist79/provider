local http = require "resty.http"
local cjson = require "cjson.safe"

local UnkeyAuthHandler = {
  VERSION  = "1.0.0",
  PRIORITY = 1000, -- Execute after rate-limiting (900) but before most plugins
}

local function extract_api_key_from_path(path)
  -- Pattern: /<API_KEY>/<CHAIN_SLUG>
  local m = ngx.re.match(path, [[^/([^/]+)/[^/]+$]], "jo")
  if m and m[1] then
    return m[1]
  end
  return nil
end

local function verify_with_auth_bridge(conf, api_key)
  local httpc = http.new()
  httpc:set_timeout(conf.timeout)

  local res, err = httpc:request_uri(conf.auth_bridge_url, {
    method = "POST",
    headers = {
      ["Content-Type"] = "application/json"
    },
    body = cjson.encode({ api_key = api_key }),
    keepalive_timeout = conf.keepalive,
    keepalive_pool = 10,
  })

  if not res then
    kong.log.err("auth-bridge request failed: ", err)
    return nil, "auth_service_unavailable"
  end

  if res.status == 401 or res.status == 403 then
    return nil, "invalid_credentials"
  end

  if res.status ~= 200 then
    kong.log.err("auth-bridge unexpected status: ", res.status, " body: ", res.body)
    return nil, "auth_service_error"
  end

  local body, decode_err = cjson.decode(res.body)
  if not body then
    kong.log.err("failed to decode auth-bridge response: ", decode_err)
    return nil, "auth_service_error"
  end

  if not body.valid then
    return nil, "invalid_credentials"
  end

  return body, nil
end

local function set_consumer(verification)
  -- Create or retrieve Kong consumer based on organization_id
  local consumer_id = verification.organization_id or verification.owner_id
  if not consumer_id then
    kong.log.warn("no consumer identifier found in verification response")
    return
  end

  -- Set authenticated consumer
  kong.client.authenticate(nil, {
    id = consumer_id,
    custom_id = consumer_id,
  })

  kong.log.debug("authenticated consumer: ", consumer_id)
end

local function set_metadata_headers(verification)
  -- Set organization metadata
  if verification.organization_id then
    kong.service.request.set_header("X-Organization-Id", verification.organization_id)
  end

  -- Set plan information for rate limiting
  if verification.plan then
    kong.service.request.set_header("X-Plan", verification.plan)
  end

  -- Set key metadata
  if verification.key_id then
    kong.service.request.set_header("X-Key-Id", verification.key_id)
  end

  if verification.key_name then
    kong.service.request.set_header("X-Key-Name", verification.key_name)
  end

  -- Set allowed chains if present
  if verification.meta and verification.meta.allowedChains then
    kong.service.request.set_header("X-Allowed-Chains", cjson.encode(verification.meta.allowedChains))
  end

  -- Pass through all metadata as JSON for downstream services
  if verification.meta then
    kong.service.request.set_header("X-Key-Metadata", cjson.encode(verification.meta))
  end
end

function UnkeyAuthHandler:access(conf)
  -- Extract API key from path
  local original_path = kong.request.get_path()
  local api_key = extract_api_key_from_path(original_path)

  if not api_key then
    if conf.anonymous then
      -- Set anonymous consumer
      kong.client.authenticate(nil, { id = conf.anonymous })
      return
    end
    return kong.response.exit(400, {
      message = "Invalid path format. Expected: /<API_KEY>/<CHAIN_SLUG>"
    })
  end

  -- Set apikey header for downstream (will be hidden if configured)
  kong.service.request.set_header("apikey", api_key)

  -- Rewrite path: remove API key segment
  kong.service.request.set_path("/")

  -- Hide credentials from logs if configured
  if conf.hide_credentials then
    kong.log.set_serialize_value("request.headers.apikey", "[REDACTED]")
  end

  -- Verify with Auth Bridge
  local verification, err = verify_with_auth_bridge(conf, api_key)

  if err then
    if err == "invalid_credentials" then
      if conf.anonymous then
        kong.client.authenticate(nil, { id = conf.anonymous })
        return
      end
      return kong.response.exit(401, {
        message = "Invalid or unauthorized API key"
      })
    elseif err == "auth_service_unavailable" then
      return kong.response.exit(502, {
        message = "Authentication service unavailable"
      })
    else
      return kong.response.exit(500, {
        message = "Authentication error"
      })
    end
  end

  -- Set Kong consumer
  set_consumer(verification)

  -- Set metadata headers for downstream services and plugins
  set_metadata_headers(verification)

  kong.log.info("authenticated request for organization: ",
                verification.organization_id or "unknown",
                " plan: ",
                verification.plan or "unknown")
end

return UnkeyAuthHandler
