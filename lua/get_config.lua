local cjson = require "cjson.safe"
local config_path = "/usr/local/openresty/lua_scripts/config/lua.conf" -- 更改为你的配置文件实际路径

local function read_config(file_path)
    local file, err = io.open(file_path, "r")
    if not file then
        ngx.log(ngx.ERR, "Failed to open config file: ", err)
        return nil
    end

    local content = file:read("*a") -- Reads the entire file content
    file:close()

    local parsed_config, err = cjson.decode(content)  -- Renamed to avoid shadowing the global config table
    if not parsed_config then
        ngx.log(ngx.ERR, "Failed to decode config file: ", err)
        return nil
    end

    return parsed_config
end

local config = {}

function config.get_redis_config()
    local cfg = read_config(config_path)  -- Changed the variable name to avoid shadowing the outer config table
    if not cfg or not cfg.redis then
        ngx.log(ngx.ERR, "Redis config not found")
        return nil
    end

    return cfg.redis
end
function config.get_intercept_url()
    local cfg = read_config(config_path)  -- Changed the variable name to avoid shadowing the outer config table
    if not cfg or not cfg.intercept_url then
        ngx.log(ngx.ERR, "intercept_url config not found")
        return nil
    end

    return cfg.intercept_url
end

return config

