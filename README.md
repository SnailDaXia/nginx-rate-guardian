#  Nginx-Rate-Guardian 

[中文文档](README_CN.md)

A distributed rate limiting and IP blocking system built with OpenResty/Nginx + Lua. Implements request frequency control at both IP and IP+URL dimensions with automatic locking/unlocking capabilities, backed by Redis storage and external HTTP API integration.

## Features

- **Dual-Mode Rate Limiting**
  - IP-based global rate limiting
  - IP+URL combined rate limiting for specific endpoints
- **Automatic Lock Management**
  - Auto-lock when rate limit exceeded
  - Auto-unlock after configured time period
- **Multi-Layer Storage**
  - Nginx shared memory (primary, high performance)
  - Redis (persistent configuration storage)
  - External HTTP API (lock record management)
- **Sliding Window Algorithm**
  - Accurate request counting with configurable time windows
  - Efficient memory usage with automatic cleanup

## Architecture

### Request Flow
1. Request enters Nginx → `access_by_lua_file` executes `lua/main.lua`
2. Filter static resources (`.js`, `.css`, images, etc.)
3. Load configuration from shared memory (fallback to Redis if missing)
4. Execute rate limiting based on `interceptType`:
   - `interceptType=0`: IP-based limiting
   - `interceptType=1`: IP+URL combined limiting
5. Return 429/503 if rate limit exceeded or IP locked

### Storage Hierarchy
1. **Nginx Shared Memory** (highest priority)
   - `intercept_config`: Rate limit rules (5MB)
   - `ip_rate_limit`: IP limiting state (10MB)
   - `ip_url_rate_limit`: IP+URL limiting state (100MB)
2. **Redis**: Persistent configuration storage
3. **External HTTP API**: Lock record CRUD operations

## Installation

### Prerequisites
- OpenResty 1.19.3.1 or higher
- Redis 5.0 or higher
- Lua 5.1 (included with OpenResty)

### Setup Steps

1. **Clone the repository**
```bash
git clone <repository-url>
cd lua_scripts
```

2. **Configure Redis and API endpoints**

Edit `config/lua.conf` according to your environment:
```json
{
  "redis": {
    "host": "your-redis-host",
    "port": 6379,
    "password": "your-password",
    "timeout": 2000,
    "pool-size": 20,
    "pool_max_idle_time": 10000
  },
  "intercept_url": {
    "intercept_record_list": "http://your-api/interceptRecord/listRecords",
    "intercept_record_add": "http://your-api/interceptRecord/add",
    "intercept_record_update_batch": "http://your-api/interceptRecord/updateBatch"
  }
}
```

3. **Deploy Lua scripts**
```bash
# Copy scripts to OpenResty directory
sudo mkdir -p /usr/local/openresty/lua_scripts
sudo cp -r lua/ config/ /usr/local/openresty/lua_scripts/
```

4. **Configure Nginx**

Add to your `nginx.conf` (inside `http` block):
```nginx
lua_package_path "/usr/local/openresty/lua_scripts/lua/?.lua;;";
lua_shared_dict intercept_config 5m;
lua_shared_dict ip_rate_limit 10m;
lua_shared_dict ip_url_rate_limit 100m;
```

Add to your `server` block:
```nginx
access_by_lua_file /usr/local/openresty/lua_scripts/lua/main.lua;
```

5. **Load rate limit configuration into Redis**

Store configuration in Redis with key `intercept_config`:
```json
[
  {
    "interceptType": 0,
    "requestLimit": 100,
    "timeLevel": 1,
    "forbidTime": 24,
    "urlAddress": "",
    "status": 0
  },
  {
    "interceptType": 1,
    "requestLimit": 10,
    "timeLevel": 1,
    "forbidTime": 2,
    "urlAddress": "/api/sensitive/endpoint",
    "status": 0
  }
]
```

6. **Test and reload Nginx**
```bash
sudo /usr/local/openresty/nginx/sbin/nginx -t
sudo /usr/local/openresty/nginx/sbin/nginx -s reload
```

## Configuration

### Rate Limit Rules

| Field | Type | Description |
|-------|------|-------------|
| `interceptType` | int | `0` = IP limiting, `1` = IP+URL limiting |
| `requestLimit` | int | Maximum requests allowed in time window |
| `timeLevel` | int | Time window in minutes |
| `forbidTime` | int | Lock duration in hours |
| `urlAddress` | string | Target URL (required for `interceptType=1`) |
| `status` | int | `0` = enabled, `1` = disabled |

### Example Configurations

**IP-based limiting (100 requests/minute)**
```json
{
  "interceptType": 0,
  "requestLimit": 100,
  "timeLevel": 1,
  "forbidTime": 24,
  "urlAddress": "",
  "status": 0
}
```

**IP+URL limiting (10 requests/minute for specific endpoint)**
```json
{
  "interceptType": 1,
  "requestLimit": 10,
  "timeLevel": 1,
  "forbidTime": 2,
  "urlAddress": "/api/file/upload",
  "status": 0
}
```

## API Integration

The system integrates with external HTTP APIs for lock record management:

### List Lock Records
```
GET {intercept_record_list}
Response: { "data": [...] }
```

### Add Lock Record
```
POST {intercept_record_add}
Body: {
  "requestList": [{
    "forbidTime": 24,
    "interceptType": 0,
    "ipAddress": "192.168.1.1",
    "lockTime": "2025-12-30 10:00:00",
    "status": 0,
    "urlAddress": ""
  }]
}
```

### Batch Unlock
```
POST {intercept_record_update_batch}
Body: [{
  "interceptType": 0,
  "ipAddress": "192.168.1.1",
  "urlAddress": ""
}]
```

## Manual Unlock

To manually unlock an IP, send POST request to `unlock_batch.lua`:
```bash
curl -X POST http://your-server/unlock_batch \
  -H "Content-Type: application/json" \
  -d '[{
    "interceptType": 0,
    "ipAddress": "192.168.1.1",
    "urlAddress": ""
  }]'
```

## Monitoring

View rate limiting logs:
```bash
tail -f /usr/local/openresty/nginx/logs/error.log
```

Enable debug logging (edit `nginx.conf`):
```nginx
error_log logs/error.log debug;
```

## Troubleshooting

### IP+URL limiting not working
1. Check if URL matches exactly (case-sensitive, no query parameters)
2. Verify `status=0` in configuration
3. Check if Nginx rewrites the URL path
4. Review error logs for configuration loading issues

### Configuration not loading
1. Verify Redis connection in `config/lua.conf`
2. Check Redis key `intercept_config` exists
3. Manually refresh: `curl http://your-server/refresh_config`

### High memory usage
Adjust shared memory sizes in `nginx.conf`:
```nginx
lua_shared_dict ip_rate_limit 20m;      # Increase if needed
lua_shared_dict ip_url_rate_limit 200m; # Increase if needed
```

## Performance

- **Throughput**: 10,000+ requests/second per worker
- **Latency**: <1ms overhead per request
- **Memory**: ~100MB for 100,000 active IP+URL combinations

## License

MIT License

## Contributing

Contributions are welcome! Please submit pull requests or open issues for bugs and feature requests.
