### 0) ortam değişkenleri

```bash
ADMIN=http://localhost:8001
PROXY=http://localhost:8000
UPSTREAM_NAME=evm-rpc
SERVICE_NAME=evm-rpc-svc
ROUTE_NAME=evm-rpc-route
CONSUMER_NAME=test
APIKEY_VALUE=sk_test_1234567890
```

### 1) delete all

```bash
for id in $(curl -s $ADMIN/plugins | jq -r '.data[].id'); do curl -s -X DELETE $ADMIN/plugins/$id; done
for id in $(curl -s $ADMIN/routes | jq -r '.data[].id'); do curl -s -X DELETE $ADMIN/routes/$id; done
for id in $(curl -s $ADMIN/services | jq -r '.data[].id'); do curl -s -X DELETE $ADMIN/services/$id; done
for id in $(curl -s $ADMIN/consumers | jq -r '.data[].id'); do
  for kid in $(curl -s $ADMIN/consumers/$id/key-auth | jq -r '.data[].id'); do curl -s -X DELETE $ADMIN/consumers/$id/key-auth/$kid; done
  curl -s -X DELETE $ADMIN/consumers/$id
done
for id in $(curl -s $ADMIN/upstreams | jq -r '.data[].id'); do curl -s -X DELETE $ADMIN/upstreams/$id; done
```

### 2) upstream and targets

```bash
curl -s -X POST $ADMIN/upstreams -H 'Content-Type: application/json' -d "{\"name\":\"$UPSTREAM_NAME\"}"
curl -s -X POST $ADMIN/upstreams/$UPSTREAM_NAME/targets -H 'Content-Type: application/json' -d '{"target":"149.50.96.191:8545","weight":100}'
curl -s -X POST $ADMIN/upstreams/$UPSTREAM_NAME/targets -H 'Content-Type: application/json' -d '{"target":"57.129.18.215:8545","weight":100}'
```

### 3) service

```bash
curl -s -X POST $ADMIN/services -H 'Content-Type: application/json' -d "{\"name\":\"$SERVICE_NAME\",\"host\":\"$UPSTREAM_NAME\",\"protocol\":\"http\",\"port\":80}"
```

### 4) route

```bash
SERVICE_ID=$(curl -s $ADMIN/services | jq -r ".data[] | select(.name==\"$SERVICE_NAME\") | .id")
curl -s -X POST $ADMIN/routes \
  -H 'Content-Type: application/json' \
  -d "{\"name\":\"$ROUTE_NAME\",\"service\":{\"id\":\"$SERVICE_ID\"},\"paths\":[\"~/[^/]+/eth$\"],\"strip_path\":true,\"methods\":[\"POST\"]}"
```

### 5) consumer and API key

```bash
curl -s -X POST $ADMIN/consumers -H 'Content-Type: application/json' -d "{\"username\":\"$CONSUMER_NAME\"}"
CONSUMER_ID=$(curl -s $ADMIN/consumers | jq -r ".data[] | select(.username==\"$CONSUMER_NAME\") | .id")
curl -s -X POST $ADMIN/consumers/$CONSUMER_ID/key-auth -H 'Content-Type: application/json' -d "{\"key\":\"$APIKEY_VALUE\"}"
```

### 6) key-auth plugin (route level)

```bash
ROUTE_ID=$(curl -s $ADMIN/routes | jq -r ".data[] | select(.name==\"$ROUTE_NAME\") | .id")
curl -s -X POST $ADMIN/routes/$ROUTE_ID/plugins -H 'Content-Type: application/json' -d '{"name":"key-auth","config":{"key_names":["apikey"],"run_on_preflight":false}}'
```

### 7) rate-limiting plugin (route level)

```bash
curl -s -X POST $ADMIN/routes/$ROUTE_ID/plugins -H 'Content-Type: application/json' -d '{"name":"rate-limiting","config":{"second":2,"minute":10,"limit_by":"ip","policy":"local","fault_tolerant":true,"hide_client_headers":false}}'
```

### 8) pre-function (access point, header set + root path)

```bash
read -r -d '' LUA_ACCESS <<'EOF'
local uri = kong.request.get_path()
local m = ngx.re.match(uri, [[^/([^/]+)/eth$]], "jo")
if m and m[1] then
  local apikey = m[1]
  ngx.req.set_header("apikey", apikey)
  kong.service.request.set_path("/")
end
EOF
curl -s -X POST $ADMIN/plugins -H 'Content-Type: application/json' -d "$(jq -n --arg rid "$ROUTE_ID" --arg code "$LUA_ACCESS" '{route:{id:$rid}, name:"pre-function", config:{rewrite:[], access:[$code], header_filter:[], body_filter:[], log:[]}}')"
```

### 9) test

```bash
curl -i $PROXY/$APIKEY_VALUE/eth -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

### 10) add prometheus

```bash
ADMIN=http://localhost:8001

curl -sS -X POST $ADMIN/plugins \
  -H 'Content-Type: application/json' \
  -d '{
    "name":"prometheus",
    "config":{
      "per_consumer": true,
      "status_code_metrics": true,
      "latency_metrics": true,
      "bandwidth_metrics": true,
      "upstream_health_metrics": true
    }
  }'
```

### 11) generate traffic: 

```bash
PROXY=http://localhost:8000
APIKEY_VALUE=sk_test_1234567890

for i in $(seq 1 5); do
  curl -s $PROXY/$APIKEY_VALUE/eth \
    -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' >/dev/null
done
```

### 12) Test:

```bash
curl -sS $ADMIN/metrics | grep -E 'kong_http_requests_total|kong_bandwidth_bytes' | head
```

### 13) Grafana dashboard

```bash
curl -X POST http://admin:admin@localhost:3000/api/dashboards/db \
  -H "Content-Type: application/json" \
  -d @"dashboard.json"
```