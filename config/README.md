# Docker Compose Test Backends

This Docker Compose setup provides test backends for E11y integration testing.

## Services

| Service | Port | Purpose | Health Check |
|---------|------|---------|--------------|
| **Loki** | 3100 | Log aggregation | http://localhost:3100/ready |
| **Prometheus** | 9090 | Metrics collection | http://localhost:9090/-/healthy |
| **Elasticsearch** | 9200 | Log storage & search | http://localhost:9200/_cluster/health |
| **Redis** | 6379 | Caching & pub/sub | redis-cli ping |

## Usage

### Start all backends:
```bash
docker-compose up -d
```

### Check status:
```bash
docker-compose ps
```

### View logs:
```bash
docker-compose logs -f [service_name]
```

### Stop all backends:
```bash
docker-compose down
```

### Stop and remove volumes:
```bash
docker-compose down -v
```

## Configuration Files

- `config/loki-local-config.yaml` - Loki configuration
- `config/prometheus.yml` - Prometheus scrape configuration

## Integration Testing

These backends are used for:
- **Loki**: Testing `E11y::Adapters::LokiAdapter` (Phase 3)
- **Prometheus**: Testing Yabeda metrics integration (Phase 1)
- **Elasticsearch**: Testing `E11y::Adapters::ElasticsearchAdapter` (Phase 3)
- **Redis**: Testing rate limiting, caching (Phase 1)

## Resource Requirements

- **Memory**: ~2GB RAM total
- **Disk**: ~500MB for images + data volumes
- **Network**: Bridge network `e11y_network`

## Health Checks

All services include health checks with automatic retries:
- Loki: 10s interval, 5 retries
- Prometheus: 10s interval, 5 retries
- Elasticsearch: 10s interval, 10 retries (slower startup)
- Redis: 5s interval, 5 retries

## Troubleshooting

### Elasticsearch fails to start:
```bash
# Increase vm.max_map_count on Linux/macOS
sysctl -w vm.max_map_count=262144
```

### Port conflicts:
Edit `docker-compose.yml` and change port mappings.

## Production Note

⚠️ **This is for TESTING ONLY!** Do not use these configurations in production.

For production setup, see [QUICK-START](../docs/QUICK-START.md) and [CONFIGURATION](../docs/CONFIGURATION.md).
