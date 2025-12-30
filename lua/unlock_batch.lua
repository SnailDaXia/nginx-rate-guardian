local ip_limit = require("ip_rate_limit")
local config_module = require("get_config")
local http = require "resty.http"

local ip_url_limit = require("ip_url_rate_limit")
if ngx.var.request_method ~= "POST" then
    ngx.status = 405
    return
end
ngx.req.read_body() -- 读取请求体  
local args = ngx.req.get_post_args() -- 获取POST参数，但这只适用于x-www-form-urlencoded格式  
ngx.header.content_type = "application/json"
  
local cjson = require "cjson"  
local body, err = ngx.req.get_body_data()  
if body then  
    local request_data = cjson.decode(body) -- 解析JSON请求体  
    if request_data then  
        for _, req in ipairs(request_data) do
            if req.interceptType == 0 then
                ip_limit.unlock(req.ipAddress)
            elseif req.interceptType == 1 then
                ip_url_limit.unlock(req.ipAddress,req.urlAddress)
            else
            end 
        end
        ngx.status = 200  
        ngx.say(cjson.encode({status = "success"}))  
        return  
    else  
        ngx.status = 400 
        ngx.say(cjson.encode({status = "fail",err="Failed to parse JSON body"}))  
        return  
    end  
else  
    ngx.status = 400  
    ngx.say(cjson.encode({status = "fail", err="No body in request"}))  
    return  
end
