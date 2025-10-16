#!/usr/bin/env bash
set -euo pipefail

ADMIN=http://localhost:8001

# =============== Helpers
jqn() { jq -r "${1}"; }

delete_if_exists() {
  local url="$1"
  local id="$2"
  if [[ -n "$id" && "$id" != "null" ]]; then
    curl -sS -X DELETE "$url/$id" >/dev/null || true
  fi
}

# =============== 0) Global Prometheus plugin (varsa) sil
PROM_ID=$(curl -s "$ADMIN/plugins?name=prometheus" | jq -r '.data[0].id // empty')
delete_if_exists "$ADMIN/plugins" "$PROM_ID"

# =============== 1) Route/Service sil
# Eski/yanlış kalmış tüm route'ları sil (özellikle "rpc", "evm-rpc-route" gibi)
for RID in $(curl -s "$ADMIN/routes" | jq -r '.data[].id'); do
  curl -sS -X DELETE "$ADMIN/routes/$RID" >/dev/null || true
done

# Tüm servisleri sil (önce pluginlerini)
for SID in $(curl -s "$ADMIN/services" | jq -r '.data[].id'); do
  # service scoped plugins
  for PID in $(curl -s "$ADMIN/services/$SID/plugins" | jq -r '.data[].id'); do
    curl -sS -X DELETE "$ADMIN/services/$SID/plugins/$PID" >/dev/null || true
  done
  curl -sS -X DELETE "$ADMIN/services/$SID" >/dev/null || true
done

# =============== 2) Upstream & targets sil
# "evm-rpc" upstream varsa, önce targets'i sil, sonra upstream'i
UPSTREAM="evm-rpc"
if curl -sf "$ADMIN/upstreams/$UPSTREAM" >/dev/null 2>&1; then
  # targets listesi
  for TID in $(curl -s "$ADMIN/upstreams/$UPSTREAM/targets/all" | jq -r '.data[].id'); do
    curl -sS -X DELETE "$ADMIN/upstreams/$UPSTREAM/targets/$TID" >/dev/null || true
  done
  curl -sS -X DELETE "$ADMIN/upstreams/$UPSTREAM" >/dev/null || true
fi

# =============== 3) Consumers & credentials sil (isteğe bağlı genel temizlik)
for CID in $(curl -s "$ADMIN/consumers" | jq -r '.data[].id'); do
  # key-auth creds
  for KID in $(curl -s "$ADMIN/consumers/$CID/key-auth" | jq -r '.data[].id'); do
    curl -sS -X DELETE "$ADMIN/consumers/$CID/key-auth/$KID" >/dev/null || true
  done
  curl -sS -X DELETE "$ADMIN/consumers/$CID" >/dev/null || true
done

# =============== 4) ——— Recreate ———

# 4.1 Upstream
curl -sS -X POST "$ADMIN/upstreams" \
  -H 'Content-Type: application/json' \
  -d '{
    "name":"evm-rpc",
    "algorithm":"round-robin",
    "healthchecks":{
      "active":{
        "type":"http","http_path":"/","timeout":2,"concurrency":2,
        "healthy":{"interval":10,"http_statuses":[200,204,301,302,307],"successes":2},
        "unhealthy":{"interval":5,"http_statuses":[429,500,503,504,505],"http_failures":2,"tcp_failures":2,"timeouts":2}
      },
      "passive":{
        "healthy":{"http_statuses":[200,201,202,204,301,302,307],"successes":1},
        "unhealthy":{"http_statuses":[429,500,503,504],"http_failures":1,"tcp_failures":1,"timeouts":1}
      }
    }
  }' >/dev/null

# 4.2 Targets
curl -sS -X POST "$ADMIN/upstreams/evm-rpc/targets" \
  -H 'Content-Type: application/json' -d '{"target":"149.50.96.191:8545","weight":100}' >/dev/null
curl -sS -X POST "$ADMIN/upstreams/evm-rpc/targets" \
  -H 'Content-Type: application/json' -d '{"target":"149.50.96.192:8545","weight":100}' >/dev/null

# 4.3 Service
curl -sS -X POST "$ADMIN/services" \
  -H 'Content-Type: application/json' \
  -d '{"name":"evm-rpc-svc","host":"evm-rpc","port":80,"protocol":"http","path":"/"}' >/dev/null

SVC_ID=$(curl -s "$ADMIN/services/evm-rpc-svc" | jq -r '.id')

# 4.4 Route (regex path: /:apikey/eth)
curl -sS -X POST "$ADMIN/services/$SVC_ID/routes" \
  -H 'Content-Type: application/json' \
  -d '{
    "name":"evm-rpc-route",
    "paths":["~^/([^/]+)/eth$"],
    "methods":["POST","GET"],
    "strip_path":false,
    "preserve_host":false
  }' >/dev/null

ROUTE_ID=$(curl -s "$ADMIN/routes/evm-rpc-route" | jq -r '.id')

# 4.5 pre-function (rewrite: path apikey -> header + uri=/eth)
LUA_REWRITE='return function()
  local uri = ngx.var.uri or ""
  local m = ngx.re.match(uri, [[^/([^/]+)/eth$]], "jo")
  if m and m[1] then
    local apikey = m[1]
    ngx.req.set_header("apikey", apikey)
    ngx.req.set_uri("/eth", false)
  end
end'

curl -sS -X POST "$ADMIN/routes/$ROUTE_ID/plugins" \
  -H 'Content-Type: application/json' \
  -d "$(jq -n --arg c "$LUA_REWRITE" '{name:"pre-function", config:{rewrite:$c}}')" >/dev/null

# 4.6 key-auth
curl -sS -X POST "$ADMIN/routes/$ROUTE_ID/plugins" \
  -H 'Content-Type: application/json' \
  -d '{"name":"key-auth","config":{"key_names":["apikey"],"hide_credentials":false}}' >/dev/null

# 4.7 Rate limits (credential + ip) -> 2/s & 10/min
curl -sS -X POST "$ADMIN/routes/$ROUTE_ID/plugins" \
  -H 'Content-Type: application/json' \
  -d '{"name":"rate-limiting","config":{"second":2,"minute":10,"limit_by":"credential","policy":"local","fault_tolerant":true,"hide_client_headers":false}}' >/dev/null

curl -sS -X POST "$ADMIN/routes/$ROUTE_ID/plugins" \
  -H 'Content-Type: application/json' \
  -d '{"name":"rate-limiting","config":{"second":2,"minute":10,"limit_by":"ip","policy":"local","fault_tolerant":true,"hide_client_headers":false}}' >/dev/null

# 4.8 Prometheus (global)
curl -sS -X POST "$ADMIN/plugins" \
  -H 'Content-Type: application/json' \
  -d '{"name":"prometheus"}' >/dev/null

# 4.9 (Opsiyonel) file-log
curl -sS -X POST "$ADMIN/services/$SVC_ID/plugins" \
  -H 'Content-Type: application/json' \
  -d '{"name":"file-log","config":{"path":"/usr/local/kong/logs/requests.json","reopen":true}}' >/dev/null

# 4.10 Consumer + credential
curl -sS -X POST "$ADMIN/consumers" \
  -H 'Content-Type: application/json' \
  -d '{"username":"user-1"}' >/dev/null || true

curl -sS -X POST "$ADMIN/consumers/user-1/key-auth" \
  -H 'Content-Type: application/json' \
  -d '{"key":"sk_test_1234567890"}' >/dev/null || true

echo "OK ✅  Temizlik ve kurulum tamam. Teste hazırsın:"
echo 'curl -sS http://localhost:8000/sk_test_1234567890/eth -H "Content-Type: application/json" -d '\''{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'\'' -i'
