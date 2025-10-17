## Signal Tipine Göre Güncel Tablo Versiyonları

**Logs için:**
- ✅ `distributed_logs_v2` → **Güncel versiyon** (v0.55'ten beri)
- ❌ `distributed_logs` → Eski versiyon

**Traces için:**
- ✅ `distributed_signoz_index_v3` → **Güncel versiyon** (v0.64'ten beri)
- ❌ `distributed_signoz_index_v2` → Eski versiyon

**Metrics için:**
- ✅ `time_series_v4`, `time_series_v4_6hrs`, `time_series_v4_1day` → **Güncel versiyon**
- ✅ `samples_v4`, `samples_v4_6hrs`, `samples_v4_1day` → **Güncel versiyon**

## Neden _v2 Görüyorsunuz?

Muhtemelen **logs** verilerini görüyorsunuz. Eğer öyleyse, `_v2` tabloları **doğru ve güncel** tablolardır.

## Kontrol Etmek İçin

```sql
-- Hangi tabloların olduğunu kontrol edin:
SHOW TABLES FROM signoz_logs;
SHOW TABLES FROM signoz_traces;
SHOW TABLES FROM signoz_metrics;
```