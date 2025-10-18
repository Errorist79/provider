local typedefs = require "kong.db.schema.typedefs"

return {
  name = "unkey-auth",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { auth_bridge_url = {
              type = "string",
              default = "http://auth-bridge:8081/api/v1/verify",
              required = true,
          }},
          { timeout = {
              type = "number",
              default = 5000,
              required = true,
          }},
          { keepalive = {
              type = "number",
              default = 60000,
              required = true,
          }},
          { anonymous = {
              type = "string",
              default = nil,
          }},
          { hide_credentials = {
              type = "boolean",
              default = true,
          }},
        },
    }},
  },
}
