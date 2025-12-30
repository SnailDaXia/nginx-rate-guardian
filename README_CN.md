# Nginx限流监控

[English Documentation](README.md)

基于 OpenResty/Nginx + Lua 的分布式限流与拦截系统。通过 Lua 脚本在 Nginx 层实现 IP 和 IP+URL 维度的请求频率限制、自动锁定和解锁功能，配合 Redis 存储配置和外部 HTTP API 同步拦截记录。

## 功能特性

- **双模式限流**
  - IP 全局限流
  - IP+URL 组合限流（针对特定接口）
- **自动锁定管理**
  - 超过限制自动锁定
  - 到期自动解锁
- **多层存储架构**
  - Nginx 共享内存（主存储，高性能）
  - Redis（配置持久化）
  - 外部 HTTP API（锁定记录管理）
- **滑动窗口算法**
  - 精确的请求计数
  - 可配置时间窗口
  - 自动清理过期数据

## 系统架构

### 请求处理流程
1. 请求进入 Nginx → `access_by_lua_file` 执行 `lua/main.lua`
2. 过滤静态资源（`.js`、`.css`、图片等）
3. 从共享内存加载配置（缺失时从 Redis 加载）
4. 根据 `interceptType` 执行限流策略：
   - `interceptType=0`：IP 限流
   - `interceptType=1`：IP+URL 限流
5. 超限或锁定时返回 429/503 状态码

### 存储层次
1. **Nginx 共享内存**（优先级最高）
   - `intercept_config`：拦截规则配置（5MB）
   - `ip_rate_limit`：IP 限流状态（10MB）
   - `ip_url_rate_limit`：IP+URL 限流状态（100MB）
2. **Redis**：配置持久化存储
3. **外部 HTTP API**：锁定记录的增删改查

## 安装部署

### 环境要求
- OpenResty 1.19.3.1 或更高版本
- Redis 5.0 或更高版本
- Lua 5.1（OpenResty 自带）

### 部署步骤

1. **克隆代码仓库**
```bash
git clone <repository-url>
cd lua_scripts
```

2. **配置 Redis 和 API 地址**

根据实际环境修改 `config/lua.conf`：
```json
{
  "redis": {
    "host": "你的Redis地址",
    "port": 6379,
    "password": "你的密码",
    "timeout": 2000,
    "pool-size": 20,
    "pool_max_idle_time": 10000
  },
  "intercept_url": {
    "intercept_record_list": "http://你的API地址/interceptRecord/listRecords",
    "intercept_record_add": "http://你的API地址/interceptRecord/add",
    "intercept_record_update_batch": "http://你的API地址/interceptRecord/updateBatch"
  }
}
```

3. **部署 Lua 脚本**
```bash
# 复制脚本到 OpenResty 目录
sudo mkdir -p /usr/local/openresty/lua_scripts
sudo cp -r lua/ config/ /usr/local/openresty/lua_scripts/
```

4. **配置 Nginx**

在 `nginx.conf` 的 `http` 块中添加：
```nginx
lua_package_path "/usr/local/openresty/lua_scripts/lua/?.lua;;";
lua_shared_dict intercept_config 5m;
lua_shared_dict ip_rate_limit 10m;
lua_shared_dict ip_url_rate_limit 100m;
```

在 `server` 块中添加：
```nginx
access_by_lua_file /usr/local/openresty/lua_scripts/lua/main.lua;
```

5. **在 Redis 中加载限流配置**

在 Redis 中设置 key 为 `intercept_config` 的配置：
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

6. **测试并重载 Nginx**
```bash
sudo /usr/local/openresty/nginx/sbin/nginx -t
sudo /usr/local/openresty/nginx/sbin/nginx -s reload
```

## 配置说明

### 限流规则字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `interceptType` | int | `0` = IP 限流，`1` = IP+URL 限流 |
| `requestLimit` | int | 时间窗口内允许的最大请求数 |
| `timeLevel` | int | 时间窗口（分钟） |
| `forbidTime` | int | 锁定时长（小时） |
| `urlAddress` | string | 目标 URL（`interceptType=1` 时必填） |
| `status` | int | `0` = 启用，`1` = 禁用 |

### 配置示例

**IP 限流（每分钟 100 次请求）**
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

**IP+URL 限流（特定接口每分钟 10 次请求）**
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

## API 接口集成

系统通过外部 HTTP API 管理锁定记录：

### 查询锁定记录
```
GET {intercept_record_list}
响应: { "data": [...] }
```

### 添加锁定记录
```
POST {intercept_record_add}
请求体: {
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

### 批量解锁
```
POST {intercept_record_update_batch}
请求体: [{
  "interceptType": 0,
  "ipAddress": "192.168.1.1",
  "urlAddress": ""
}]
```

## 手动解锁

向 `unlock_batch.lua` 发送 POST 请求手动解锁 IP：
```bash
curl -X POST http://你的服务器/unlock_batch \
  -H "Content-Type: application/json" \
  -d '[{
    "interceptType": 0,
    "ipAddress": "192.168.1.1",
    "urlAddress": ""
  }]'
```

## 监控日志

查看限流日志：
```bash
tail -f /usr/local/openresty/nginx/logs/error.log
```

启用调试日志（编辑 `nginx.conf`）：
```nginx
error_log logs/error.log debug;
```

## 故障排查

### IP+URL 限流不生效
1. 检查 URL 是否完全匹配（区分大小写，不含查询参数）
2. 确认配置中 `status=0`
3. 检查 Nginx 是否重写了 URL 路径
4. 查看错误日志确认配置加载情况

### 配置未加载
1. 验证 `config/lua.conf` 中的 Redis 连接配置
2. 检查 Redis 中是否存在 `intercept_config` 键
3. 手动刷新配置：`curl http://你的服务器/refresh_config`

### 内存占用过高
调整 `nginx.conf` 中的共享内存大小：
```nginx
lua_shared_dict ip_rate_limit 20m;      # 根据需要增加
lua_shared_dict ip_url_rate_limit 200m; # 根据需要增加
```

## 性能指标

- **吞吐量**：单 worker 进程 10,000+ 请求/秒
- **延迟**：每个请求增加 <1ms 开销
- **内存**：100,000 个活跃 IP+URL 组合约占用 100MB

## 开源协议

MIT License

## 贡献指南

欢迎提交 Pull Request 或提出 Issue 报告问题和功能建议。
