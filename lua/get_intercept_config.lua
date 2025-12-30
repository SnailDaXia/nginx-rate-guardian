local cjson = require "cjson"
local config_module = require("get_config")
local redis_conn = require("redis_conn")
local http = require "resty.http"
local function parseDateTime(dateTimeStr)
    local year, month, day, hour, min, sec = dateTimeStr:match("(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
    return os.time({year=year, month=month, day=day, hour=hour, min=min, sec=sec})
end


local _M = {}
function _M.get_intercept_config(key)
    -- 尝试从共享内存获取配置
    local shared_memory = ngx.shared.intercept_config
    local intercept_config = shared_memory:get(key)
    if not intercept_config then
        ngx.log(ngx.DEBUG, "未从内存中获取到"..key..",开始从Redis中获取配置")
        local red, err = redis_conn.redis_connection()
        if not red then
            ngx.log(ngx.ERR, "获取Redis连接失败: ", err)
            return
        end
        intercept_config, err = red:get(key)
        if not intercept_config or intercept_config == ngx.null then
            ngx.log(ngx.ERR, "未从Redis中获取到"..key.."配置: ", err)
            shared_memory:set(key, "[]")
        else
            -- 将配置存入共享内存
            ngx.log(ngx.INFO, "从Redis中获取配置"..key.."内容如下: ",intercept_config)
            shared_memory:set(key, intercept_config)
        end
    else
        ngx.log(ngx.DEBUG, "从内存中获取到"..key..": ",intercept_config)
    end

    return intercept_config 
end
function _M.refresh_intercept_record()
    -- 尝试从共享内存获取配置
    local shared_memory = ngx.shared.intercept_config
    local ip_limit = ngx.shared.ip_rate_limit
    local ip_url_limit = ngx.shared.ip_url_rate_limit
    local intercept_record = shared_memory:get("intercept_record")
    if not intercept_record then
        -- 调用外部接口获取锁定数据
        ngx.log(ngx.DEBUG,"未从内存中获取锁定记录,开始从接口获取")
        local httpc = http.new()
        local intercept_record_list_url = config_module.get_intercept_url().intercept_record_list 
        local res, err = httpc:request_uri(intercept_record_list_url, {
                  method = "GET",
                  headers = {
                      ["Content-Type"] = "application/json",
                  }
              })

        --处理调用结果
        if not res then
            ngx.log(ngx.ERR, "Failed to request record list api: ", err)
            return
        end

        if res.status ~= 200 then
            ngx.log(ngx.ERR, "Request record list api failed with status: ", res.status)
            return
        end
        ngx.log(ngx.INFO,"从接口中获取到锁定记录,内容为: "..res.body)
        shared_memory:set("intercept_record", res.body)
        local res_data = cjson.decode(res.body)
        if res_data and res_data.data then
            for _, data in ipairs(res_data.data) do
                if data.interceptType == 0 then
                    local ip_lock_key = "lock:"..data.ipAddress
                    ngx.log(ngx.ERR,ip_lock_key)
                    local ip_endtime_key = "lock_endtime:" .. data.ipAddress
                    local ip_lock_endtime = parseDateTime(data.lockTime) + data.forbidTime*3600
                    ip_limit:set(ip_lock_key, true, data.forbidTime*3600)
                    ip_limit:set(ip_endtime_key, ip_lock_endtime)
                elseif data.interceptType == 1 then
                    local ip_url_lock_key = "lock:"..data.ipAddress.."_"..data.urlAddress
                    local ip_url_endtime_key = "lock_endtime:"..data.ipAddress.."_"..data.urlAddress
                    local ip_url_lock_endtime = parseDateTime(data.lockTime) + data.forbidTime*3600
                    ip_url_limit:set(ip_url_lock_key, true, data.forbidTime*3600)
                    ip_url_limit:set(ip_url_endtime_key, ip_url_lock_endtime)
                else
                end

            end
        
        end
    end
end

return _M

