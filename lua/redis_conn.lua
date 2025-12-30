local redis = require "resty.redis"
local config_module = require("get_config")

local _M = {}
function _M.redis_connection()
    local redis_config = config_module.get_redis_config()
    local red = redis:new()
 
    -- 设置连接超时时间
    red:set_timeout(redis_config.timeout)
    
    red.pool = {redis_config.pool_max_idle_time,redis_config.pool_size}

    -- 连接到Redis服务器
    local ok, err = red:connect(redis_config.host, redis_config.port)
    if not ok then
        ngx.log(ngx.ERR, "连接Redis失败: ", err)
        return nil, err
    else
        ngx.log(ngx.INFO,"连接Redis成功")
    end
 
    -- 进行密码认证（如果配置了密码）
    if redis_config.password and redis_config.password ~= "" then
        local auth_ok, auth_err = red:auth(redis_config.password)
        if not auth_ok then
            ngx.log(ngx.ERR, "Redis认证失败: ", auth_err)
            return nil, auth_err
        end
    end
 
    return red
end

return _M

