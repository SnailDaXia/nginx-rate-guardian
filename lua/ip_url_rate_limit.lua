local ngx_shared = ngx.shared.ip_url_rate_limit
local cjson = require "cjson"
local config_module = require("get_config")
local http = require "resty.http"
local _M = {}

function _M.check_and_lock(ip, url, limit, period, lock_time)
    local key = "req:"..ip.."_"..url
    local lock_key = "lock:"..ip.."_"..url
    local endtime_key = "lock_endtime:"..ip.."_"..url
    local now = ngx.now()

    -- 检查IP是否已过锁定时间
    local locked_endtime = ngx_shared:get(endtime_key)
    if locked_endtime and locked_endtime ~= ngx.null then
        local current_timestamp = os.time()
        if current_timestamp > locked_endtime then
            _M.unlock(ip,url)   
            -- 调用外部接口解除锁定
            local httpc = http.new()
            local req_body = {
                      {
                        interceptType = 1,
                        ipAddress = ip,
                        urlAddress = url
                      }
                  }
            local intercept_record_update_batch_url = config_module.get_intercept_url().intercept_record_update_batch 
            local res, err = httpc:request_uri(intercept_record_update_batch_url, {
                    method = "POST",
                    body = cjson.encode(req_body),
                    headers = {
                        ["Content-Type"] = "application/json",
                    }
             })

             --处理调用结果
             if not res then
                 ngx.log(ngx.ERR, "Failed to request update record api: ", err)
             end
                
             if res.status ~= 200 then
                 ngx.log(ngx.ERR, "Request update record api failed with status: ", res.status)
             end

        end
    end


    -- 检查 IP 是否已被锁定
    local locked = ngx_shared:get(lock_key)
    if locked then
        return false, "locked"
    end

    local value, flags = ngx_shared:get(key)
    if not value then
        -- 第一次请求，初始化计数器
        ngx_shared:set(key, 1, period)
        ngx_shared:set(key..":time", now)
    else
        -- 增加计数
        if now - (ngx_shared:get(key..":time") or 0) <= period then
            if value + 1 > limit then
                -- 达到限制，锁定 IP URL
                local current_timestamp = os.time()
                local lock_endtime = current_timestamp + lock_time*3600
                ngx_shared:set(lock_key, true, lock_time*3600)
                ngx_shared:set(endtime_key, lock_endtime)

                 -- 调用外部接口上传锁定数据
                local httpc = http.new()
                local intercept_record_add_url = config_module.get_intercept_url().intercept_record_add  
                local req_body = {
                    requestList = {
                      {
                        forbidTime = lock_time,
                        interceptType = 1,
                        ipAddress = ip,
                        lockTime = os.date("%Y-%m-%d %H:%M:%S", current_timestamp),
                        status = 0,
                        urlAddress = url
                      }
                  }
                }
                local res, err = httpc:request_uri(intercept_record_add_url, {
                    method = "POST",
                    body = cjson.encode(req_body),
                    headers = {
                        ["Content-Type"] = "application/json",
                    }
                })

                --处理调用结果
                if not res then
                    ngx.log(ngx.ERR, "failed to call lock IP API: ", err)
                end


                return false, "locked"
            else
                ngx_shared:incr(key, 1)
            end
        else
            -- 超过周期时间，重置计数器
            ngx_shared:set(key, 1, period)
            ngx_shared:set(key..":time", now)
        end
    end
    return true
end

function _M.unlock(ip,url)
    local key = "req:" .. ip .."_"..url
    local lock_key = "lock:" .. ip.."_"..url
    local endtime_key = "lock_endtime:"..ip.."_"..url
    ngx_shared:delete(key)
    ngx_shared:delete(lock_key)
    ngx_shared:delete(endtime_key)
end


return _M

