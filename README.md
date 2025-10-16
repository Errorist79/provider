# Kong API Gateway for Ethereum RPC Nodes

This setup provides a Kong API Gateway in front of your Ethereum RPC nodes with the following features:
- Load balancing between multiple Ethereum nodes
- Rate limiting per API key
- API key authentication
- Detailed metrics and monitoring
- Request logging
- CORS support

## Features

- **Load Balancing**: Round-robin load balancing between your Ethereum nodes
- **Rate Limiting**: 1000 requests per minute per API key
- **Monitoring**: Prometheus metrics and Grafana dashboards
- **Authentication**: API key based authentication
- **Request Logging**: Detailed logging of all requests
- **CORS Support**: Pre-configured CORS settings

## Prerequisites

- Docker
- Docker Compose

## Getting Started

1. **Start the services**:
   ```bash
   docker-compose up -d
   ```

2. **Access the services**:
   - Kong Admin API: http://localhost:8001
   - Kong Proxy: http://localhost:8000
   - Prometheus: http://localhost:9090
   - Grafana: http://localhost:3000 (admin/admin)

3. **Make a request to your Ethereum node**:
   ```bash
   curl -X POST http://localhost:8000 \
     -H "Content-Type: application/json" \
     -H "x-api-key: your-secure-api-key-here" \
     -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
   ```

## Configuration

### API Keys
Default API keys are set in `kong/kong.yml`. To add a new API key:
1. Edit `kong/kong.yml`
2. Add a new consumer under the `consumers` section
3. Apply the changes:
   ```bash
   docker-compose restart kong
   ```

### Rate Limiting
Rate limiting is configured for 1000 requests per minute per API key. To modify:
1. Edit `kong/kong.yml`
2. Update the `rate-limiting` plugin configuration
3. Restart Kong

## Monitoring

### Grafana Setup
1. Log in to Grafana at http://localhost:3000 (admin/admin)
2. Add Prometheus as a data source:
   - URL: http://prometheus:9090
   - Save & Test

### Available Metrics
- Request rate
- Error rates
- Latency
- Rate limit usage
- Upstream health

## Security Notes

1. Change the default API keys in production
2. Consider enabling HTTPS
3. Restrict admin API access
4. Monitor your rate limits and adjust as needed
