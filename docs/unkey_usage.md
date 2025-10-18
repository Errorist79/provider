  🎯 Unkey Nerede ve Neden Kullanılıyor?

  Unkey'in Rolü: API Key Vault (Tek Kaynak Doğruluk)

  Mimarinizde Unkey, tüm API key'lerin tek ve güvenli deposudur. Yani:

  ┌─────────────────────────────────────────────────────────┐
  │  Unkey = API Key'lerin Secret'ının Saklandığı Yer      │
  │  PostgreSQL = API Key'lerin METADATA'sının Saklandığı  │
  └─────────────────────────────────────────────────────────┘

  İstek Akışı (Çok Kritik!)

  1. Müşteri → http://localhost:8000/{API_KEY}/eth-mainnet
                                      └─────┬─────┘
                                            │
  2. Kong Gateway                           │
     ├─ API key'i path'den extract eder ────┘
     ├─ Auth Bridge'e gönderir
     │
  3. Auth Bridge Service (8081)
     ├─ Redis cache'e bakar (varsa direkt döner, 60s TTL)
     │  └─ YOKSA ↓
     ├─ Unkey'e POST /v2/keys.verifyKey
     │  └─ Authorization: Bearer {ROOT_KEY}  ← İŞTE BURADA!
     │  └─ Body: {"key": "{müşterinin_api_key'i}"}
     │
  4. Unkey (3001)
     ├─ Root key'i verify eder (database'de hash kontrolü)
     ├─ Müşteri key'ini verify eder
     ├─ Döner: {valid: true, organizationId, plan, permissions}
     │
  5. Auth Bridge → Kong'a döner
     └─ Kong bu metadata ile rate limit uygular
     └─ Upstream RPC node'a request gönderir

  Root Key vs Müşteri Key'leri

  İşte kafanız karıştıran kısım:

  ┌─────────────────────────────────────────────────────────────┐
  │  ROOT KEY (unkey_root veya production'da random)            │
  │  ├─ Sahibi: SİZ (RPC provider)                             │
  │  ├─ Kullanım: Auth Bridge → Unkey iletişimi                │
  │  ├─ Yetki: Unkey API'sini kullanma (key verify, create)    │
  │  ├─ Nerede: .env → AUTH_BRIDGE_UNKEY_API_KEY               │
  │  └─ ASLA müşteriye verilmez!                               │
  └─────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────┐
  │  MÜŞTERİ KEY'LERİ (sk_test_xxx, sk_prod_xxx)                │
  │  ├─ Sahibi: MÜŞTERİLERİNİZ                                  │
  │  ├─ Kullanım: RPC request'lerinde URL'de                    │
  │  ├─ Yetki: RPC endpoint'lerinize erişim                     │
  │  ├─ Nerede: Müşteriye dashboard'dan veriyorsunuz           │
  │  └─ Unkey tarafından verify ediliyor                        │
  └─────────────────────────────────────────────────────────────┘

  ---
  🔐 Root Key Nasıl Kullanılıyor?

  1. Development (Mevcut Setup)

  # 05-seed-root-key.sql otomatik çalışır
  INSERT INTO keys VALUES (
    'key_local_root',
    'TO_BASE64(SHA256("unkey_root"))',  # Hardcoded
    ...
  );

  # .env
  AUTH_BRIDGE_UNKEY_API_KEY=unkey_root

  Auth Bridge başladığında:
  // services/auth-bridge/internal/unkey/client.go:19
  func New(cfg config.UnkeyConfig) (*Client, error) {
      opts := []v2.SDKOption{
          v2.WithSecurity(cfg.APIKey), // ← "unkey_root" buradan geliyor
          ...
      }
  }

  Her verify request'inde:
  // services/auth-bridge/internal/unkey/client.go:45
  func (c *Client) VerifyKey(ctx context.Context, apiKey string) {
      // SDK otomatik olarak root key'i Authorization header'a ekler:
      // Authorization: Bearer unkey_root

      resp, err := c.sdk.Keys.VerifyKey(ctx, components.V2KeysVerifyKeyRequestBody{
          Key: apiKey, // ← müşterinin key'i
      })
  }

  ---
  2. Production (Güvenli Setup)

  Adım 1: Secure Key Üret

  openssl rand -base64 32
  # Çıktı: xK9mP2nQ4rS5tU6vW7xY8zA1bC2dE3fG4hI5jK6lM7nO8

  Adım 2: Secrets Manager'a Kaydet

  # AWS Secrets Manager
  aws secretsmanager create-secret \
    --name prod/rpc-gateway/unkey-root-key \
    --secret-string "xK9mP2nQ4rS5tU6vW7xY8zA1bC2dE3fG4hI5jK6lM7nO8"

  # Veya HashiCorp Vault
  vault kv put secret/rpc-gateway/unkey root_key="xK9mP..."

  Adım 3: Database'den Development Root Key'i Kaldır

  # Bu dosyayı production'da ÇALIŞTIRMAYIN
  rm database/mysql/init/05-seed-root-key.sql

  # Veya rename edin
  mv database/mysql/init/05-seed-root-key.sql \
     database/mysql/init/05-seed-root-key.sql.DEVELOPMENT_ONLY

  Adım 4: Container Başladıktan Sonra Root Key'i Inject Et

  # Secrets manager'dan çek
  export UNKEY_ROOT_KEY=$(aws secretsmanager get-secret-value \
    --secret-id prod/rpc-gateway/unkey-root-key \
    --query SecretString --output text)

  # Script ile database'e yükle
  ./scripts/init-root-key.sh

  Script ne yapar:
  # scripts/init-root-key.sh:34-40
  HASH=$(python3 -c "
  import hashlib
  import base64
  key = '$ROOT_KEY'  # ← Secrets manager'dan gelen
  hash_obj = hashlib.sha256(key.encode())
  print(base64.b64encode(hash_obj.digest()).decode())
  ")

  # Database'e ekler
  INSERT INTO keys VALUES (
    'key_production_root',
    '$HASH',  # ← SHA256 + base64
    ...
  );

  Adım 5: Environment Variable Olarak Set Et

  # Production .env (gitignore'da!)
  AUTH_BRIDGE_UNKEY_API_KEY=xK9mP2nQ4rS5tU6vW7xY8zA1bC2dE3fG4hI5jK6lM7nO8

  # Veya docker-compose.yml'de override
  services:
    auth-bridge:
      environment:
        - AUTH_BRIDGE_UNKEY_API_KEY=${UNKEY_ROOT_KEY}

  ---
  📊 PostgreSQL vs Unkey - Veri Ayrımı

  | Veri Türü         | PostgreSQL                   | Unkey                     |
  |-------------------|------------------------------|---------------------------|
  | API Key Secret    | ❌ ASLA                       | ✅ Hash olarak             |
  | Key Metadata      | ✅ key_id, prefix, created_at | ✅ name, expires, enabled  |
  | Organization      | ✅ org_id, name, plan         | ✅ metadata.organizationId |
  | Rate Limit Config | ✅ plans tablosu              | ✅ identity.ratelimits     |
  | Usage Stats       | ✅ ClickHouse                 | ❌                         |
  | Billing           | ✅ PostgreSQL                 | ❌                         |

  Neden bu ayrım?

  ARCHITECTURE.md:66-68'den:
  # Security (key in URL, but hardened)
  * Secret custody: full API key ONLY in Unkey (KMS at rest).
    No key/secret hash in our DB.

  ---
  🔄 Müşteri Key'i Nasıl Oluşturuluyor?

  1. Dashboard/API ile Create Request

  curl -X POST http://localhost:3001/v2/keys.createKey \
    -H "Authorization: Bearer unkey_root" \  # ← ROOT KEY
    -H "Content-Type: application/json" \
    -d '{
      "apiId": "api_local_root_keys",
      "name": "Customer Acme Corp",
      "prefix": "sk_prod",
      "meta": {
        "organizationId": "org_123",
        "plan": "pro"
      }
    }'

  2. Unkey Yanıtı

  {
    "data": {
      "key": "sk_prod_A1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P6",
      "keyId": "key_xyz789"
    }
  }

  3. PostgreSQL'e Metadata Kaydet

  -- Bu SİZİN backend'inizin görevi
  INSERT INTO api_keys (
    unkey_key_id,
    key_prefix,
    organization_id,
    plan_id,
    status
  ) VALUES (
    'key_xyz789',
    'sk_prod',
    'org_123',
    'plan_pro',
    'active'
  );

  4. Müşteriye Key'i Ver

  Müşteriye: "sk_prod_A1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P6"

  5. Müşteri Kullanır

  curl -X POST http://your-gateway.com/sk_prod_A1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P6/eth-mainnet \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

  ---
  🎭 Root Key Rolleri

  06-seed-root-permissions.sql'den:
  -- Root key'in yapabilecekleri:
  INSERT INTO permissions VALUES
    ('api.*.create_key'),   -- ✅ Müşteri key'i oluştur
    ('api.*.verify_key'),   -- ✅ Müşteri key'ini doğrula
    ('api.*.read_api'),     -- ✅ API bilgilerini oku
    ('api.*.read_key');     -- ✅ Key bilgilerini oku

  -- Root key'in YAPAMAYACAKLARI:
  -- ❌ Workspace yönetimi
  -- ❌ Billing işlemleri
  -- ❌ Diğer root key'leri yönetme

  ---
  📝 Özet: Kafanızı Karıştıran Kısım

  Sorunuz: "Production'da root key nasıl atayacağız?"

  Cevap:
  1. Development: SQL seed file otomatik yükler (unkey_root)
  2. Production:
    - SQL seed dosyasını KALDIRIN
    - Secrets manager'dan çekin
    - init-root-key.sh ile database'e yükleyin
    - Auth Bridge'e environment variable olarak verin

  Root key'i kim kullanıyor?
  - ✅ Auth Bridge servisi (her verify request'inde)
  - ✅ Dashboard backend'iniz (müşteri key'i create/revoke)
  - ❌ Müşterileriniz (onlar kendi key'lerini kullanır)

  Analoji:
  Root Key = Anahtar Fabrikasının Ana Anahtarı
  Müşteri Key'leri = Fabrikada üretilen müşteri anahtarları

  Fabrika sahibi (siz) = Root key ile yeni anahtarlar üretir
  Müşteriler = Kendi anahtarları ile kapıları açar

  ---
  Artık daha net oldu mu? Başka bir belirsizlik var mı?