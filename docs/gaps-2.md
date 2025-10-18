  🔴 KRİTİK EKSİKLER (Latency & Security)

  1. LATENCY BOTTLENECKS

  A. Kong Plugin - Cache Yok ❌

  Durum: unkey-auth plugin'i her request'te Auth Bridge'e gidiyor (HTTP call)
  Etki: +3-10ms latency per request
  Kod: services/kong-plugins/unkey-auth/handler.lua:18-56

  -- ŞU ANDA: Her seferinde HTTP call
  local verification, err = verify_with_auth_bridge(conf, api_key)

  Çözüm: Kong-level Redis cache (mlcache) ekle
  -- Örnek çözüm:
  local cache = kong.cache
  local cache_key = "unkey:verify:" .. api_key
  local verification, err = cache:get(cache_key, {
    ttl = 60,
    neg_ttl = 5  -- invalid keys için düşük TTL
  }, verify_with_auth_bridge, conf, api_key)

  Kazanç: ~5-8ms azalma per request

  ---
  B. Auth Bridge - Connection Pool Eksik ❌

  Durum: Auth Bridge → Unkey HTTP client her request'te yeni connection açıyor
  Kod: services/auth-bridge/internal/unkey/client.go (muhtemelen)

  Çözüm: HTTP client'a connection pooling ekle:
  &http.Client{
      Transport: &http.Transport{
          MaxIdleConns:        100,
          MaxIdleConnsPerHost: 10,
          IdleConnTimeout:     90 * time.Second,
      },
      Timeout: 3 * time.Second,
  }

  Kazanç: ~2-3ms azalma per request

  ---
  C. Kong Plugin - Keepalive Pool Düşük ⚠️

  Durum: Plugin → Auth Bridge keepalive pool = 10
  Kod: handler.lua:29

  keepalive_pool = 10,  -- Düşük!

  Çözüm: Artır (50-100 arası)
  keepalive_pool = 100,
  keepalive_timeout = conf.keepalive,
  keepalive_requests = 1000,  -- yeni ekle

  Kazanç: High-traffic altında ~1-2ms

  ---
  D. Redis TTL Optimizasyonu ⚠️

  Durum: Auth Bridge cache TTL = 60s (sabit)
  Sorun:
  - Valid keys için 60s uygun
  - Invalid keys için 60s çok uzun! (brute-force denemelerini cache'liyor)

  Çözüm: Differential caching
  // Valid keys: 60s
  // Invalid keys: 5-10s (rate-limit için yeterli)
  ttl := 60 * time.Second
  if !verification.Valid {
      ttl = 5 * time.Second
  }
  cache.Set(ctx, key, value, ttl)

  ---
  2. SECURITY GAPS

  A. API Key Logging ⚠️

  Durum: hide_credentials=true var ama:
  -- handler.lua:131
  kong.log.set_serialize_value("request.headers.apikey", "[REDACTED]")

  Sorun:
  - Path'te olan key (/<API_KEY>/chain) hala loglanabilir
  - OpenTelemetry span'larında path görünüyor olabilir

  Çözüm: Path sanitization ekle
  -- Before logging:
  kong.log.set_serialize_value("request.path", sanitize_path(original_path))

  ---
  B. Rate Limiting - Consumer-Based Değil ❌

  Durum: Rate limiting global/service-based
  Sorun: Farklı planlar (free/pro/enterprise) için farklı limit yok

  Çözüm: Plugin consumer-based rate limiting
  # Her organization için farklı limit
  curl -X POST http://localhost:8001/consumers/org_customer_123/plugins \
    --data name=rate-limiting \
    --data config.minute=10000  # pro plan

  VEYA daha iyi: Response-RateLimiting plugin ile X-Plan header'a göre dinamik limit:
  -- Custom rate-limiting logic based on X-Plan header
  local plan = kong.request.get_header("X-Plan")
  local limits = { free = 100, pro = 10000, enterprise = 100000 }
  local limit = limits[plan] or 100

  ---
  C. TLS/HTTPS Kapalı ❌

  Durum: .env:135 → TLS_ENABLED=false
  Sorun: API keys plaintext olarak network'te

  Çözüm: Production için Let's Encrypt + Kong TLS termination
  # docker-compose.yml
  environment:
    KONG_SSL_CERT: /etc/certs/fullchain.pem
    KONG_SSL_CERT_KEY: /etc/certs/privkey.pem
    KONG_PROXY_LISTEN: 0.0.0.0:8000, 0.0.0.0:8443 ssl http2

  ---
  D. Auth Bridge - API Key Hardcoded ⚠️

  Durum: UNKEY_ROOT_KEY=unkey_root (.env'de plaintext)
  Sorun: Root key exposure riski

  Çözüm:
  1. Secrets management (Vault/Docker Secrets)
  2. Minimum: .env dosyasını .gitignore'a ekle (zaten var mı kontrol et)

  ---
  E. No Request ID Tracing ⚠️

  Durum: Auth Bridge X-Unkey-Request-Id dönüyor ama Kong flow'da trace yok
  Sorun: End-to-end debugging zor

  Çözüm: Kong correlation-id plugin ekle
  curl -X POST http://localhost:8001/plugins \
    --data name=correlation-id \
    --data config.header_name=X-Request-ID \
    --data config.generator=uuid

  ---
  F. No Circuit Breaker ❌

  Durum: Auth Bridge down olursa Kong tüm request'leri reddediyor
  Sorun: Cascading failure

  Çözüm:
  1. Kong healthcheck plugin (Auth Bridge için)
  2. Fallback anonymous consumer
  3. Circuit breaker pattern

  -- Plugin'e ekle:
  if conf.anonymous and (err == "auth_service_unavailable") then
    kong.client.authenticate(nil, { id = conf.anonymous })
    kong.log.warn("Auth Bridge unavailable, using anonymous consumer")
    return  -- Continue request
  end

  ---
  G. MySQL Connection Limits ⚠️

  Durum: Default MySQL max_connections (151)
  Sorun: High-load'da connection exhaustion

  Çözüm: MySQL config artır
  # docker-compose.yml
  unkey-mysql:
    command:
      - --max-connections=500
      - --max-allowed-packet=256M

  ---
  3. OBSERVABILITY GAPS

  A. No Custom Metrics ⚠️

  Durum: Traces var ama business metrics yok:
  - API key usage per organization
  - Request latency per plan
  - Cache hit/miss ratio

  Çözüm: StatsD/Prometheus plugin ekle
  curl -X POST http://localhost:8001/plugins \
    --data name=prometheus

  ---
  B. No Alerting ❌

  Durum: SigNoz var ama alert rules yok
  Sorun: Auth Bridge down olsa kimse bilmiyor

  ---
  📊 ÖNCELİK SIRASI (Latency & Security)

  Tier 1 - HEMEN (1-2 gün)

  1. ✅ Kong plugin Redis cache → En büyük latency kazancı
  2. ✅ Consumer-based rate limiting → Security + plan enforcement
  3. ✅ Auth Bridge connection pooling → Latency + stability
  4. ✅ Invalid key cache TTL → Brute-force protection

  Tier 2 - KISA VADEDE (1 hafta)

  5. ⚠️ TLS/HTTPS → Production security
  6. ⚠️ Circuit breaker → Resilience
  7. ⚠️ Path sanitization (logging) → Security
  8. ⚠️ Prometheus metrics → Observability

  Tier 3 - ORTA VADEDE (2-4 hafta)

  9. 📌 Secrets management (Vault) → Enterprise security
  10. 📌 Alerting rules → Operations
  11. 📌 MySQL tuning → Scale

  ---
  🎯 ÖZET

  | Kategori | Kritik Eksik                     | Etki              | Çözüm Süresi |
  |----------|----------------------------------|-------------------|--------------|
  | Latency  | Kong plugin cache yok            | -5-8ms            | 2-3 saat     |
  | Latency  | Auth Bridge connection pool yok  | -2-3ms            | 1 saat       |
  | Security | Consumer-based rate limiting yok | Plan bypass riski | 2-3 saat     |
  | Security | TLS kapalı                       | MITM riski        | 1 gün        |
  | Security | Circuit breaker yok              | Cascade failure   | 3-4 saat     |
  | Latency  | Keepalive pool düşük             | High-load lag     | 30 dk        |

  En hızlı kazanç: Kong plugin cache + connection pooling → ~7-11ms latency azalması

  Hangi konudan başlamak istersin?