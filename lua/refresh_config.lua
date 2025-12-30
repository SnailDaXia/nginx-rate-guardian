local cjson = require "cjson"
local config_module = require("get_config")
local redis_conn = require("redis_conn")
local shared_memory = ngx.shared.intercept_config
ngx.header.content_type = "application/json"

-- 从Redis获取配置并更新到共享内存
local function update_config_from_redis(key)
    local red, err = redis_conn.redis_connection()
    if not red then
        ngx.log(ngx.ERR, "获取Redis连接失败: ", err)
        ngx.say(cjson.encode({status = "fail"}))
        return
    end
    intercept_config, err = red:get(key)
    if intercept_config or intercept_config ~= ngx.null then
        -- 将配置存入共享内存
        shared_memory:set(key, intercept_config)
    end
end

-- 执行更新配置操作
update_config_from_redis('intercept_config')
update_config_from_redis('intercept_record')
update_config_from_redis('intercept_unlock')
ngx.say(cjson.encode({status = "success"}))
