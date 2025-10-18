# Auth Bridge Service

Stateless adapter between Kong Gateway and Unkey. The service verifies incoming API keys, enriches the response with organization metadata, and caches results in Redis to minimize latency.

## Features

- Verifies keys against Unkey's `keys.verifyKey` endpoint using a workspace/root key.
- Normalizes metadata (`organizationId`, `plan`, `allowedChains`) for Kong plugins.
- Redis-backed cache for low-latency lookups with configurable TTL.
- Health endpoint (`GET /healthz`) for readiness probes.

## Configuration

Environment variables use the `AUTH_BRIDGE_` prefix. Key settings include:

| Variable | Description | Default |
|----------|-------------|---------|
| `AUTH_BRIDGE_SERVER_PORT` | HTTP listen port | `8081` |
| `AUTH_BRIDGE_UNKEY_BASEURL` | Base URL of the Unkey API | `http://unkey:8080` |
| `AUTH_BRIDGE_UNKEY_API_KEY` | Root/workspace key for verification | required |
| `AUTH_BRIDGE_CACHE_ENABLED` | Toggle Redis cache | `true` |
| `AUTH_BRIDGE_CACHE_TTL` | Cache TTL (Go duration) | `60s` |
| `AUTH_BRIDGE_CACHE_REDIS_ADDR` | Redis address | `redis:6379` |

## Running locally

```bash
# Build & run
cd services/auth-bridge
AUTH_BRIDGE_UNKEY_API_KEY=your-unkey-root-key go run ./cmd/server
```

Provide a JSON payload to verify a key:

```bash
curl -X POST http://localhost:8081/api/v1/verify \
  -H "Content-Type: application/json" \
  -d '{"api_key":"sk_live_123"}'
```

On success, the service returns normalized metadata and rate-limit information to Kong.
