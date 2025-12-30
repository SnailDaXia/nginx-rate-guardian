-- 引入所需的库
local cjson = require "cjson"
local intercept_config_module = require("get_intercept_config")
local ip_limit = require("ip_rate_limit")
local ip_url_limit = require("ip_url_rate_limit")
local headers = ngx.req.get_headers()

-- 获取请求者的IP和请求的URL
local ip = ngx.var.remote_addr
local url = ngx.var.uri

-- 安全解码JSON字符串的函数
local function safe_decode(json_str)
    local ok, result = pcall(cjson.decode, json_str)
    if not ok then
        ngx.log(ngx.ERR, "JSON解码失败: ", result) -- 在解码失败时记录错误
        return {}
    else
        return result
    end
end

-- 从配置模块获取配置信息，并尝试解码
local i_config = safe_decode(intercept_config_module.get_intercept_config('intercept_config'))
-- 获取锁定记录
intercept_config_module.refresh_intercept_record()

if headers["user-agent"] == "LangShen" then
    ngx.log(ngx.ERR, "LangShen限流:" .. url)
    ngx.status = 503
    ngx.header.content_type = "application/json"
    ngx.say(cjson.encode({ status = "Ip Locked" }))
    ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
end


-- 过滤静态文件
local patterns = {
    "^/.*static/.*",
    "^/.*assets/.*"
}

for _, pattern in ipairs(patterns) do
    if ngx.re.match(url, pattern) then
        return
    end
end

-- 根据配置进行请求限制和锁定检查
if i_config then
    for _, config in ipairs(i_config) do
        if config.interceptType == 0 then
            local ok, err = ip_limit.check_and_lock(ip, config.requestLimit, config.timeLevel * 60, config.forbidTime)
            if not ok then
                if err == "locked" then
                    ngx.status = 503
                    ngx.header.content_type = "application/json"
                    ngx.say(cjson.encode({ status = "Ip Locked" }))
                    ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
                else
                    ngx.status = 429
                    ngx.header.content_type = "application/json"
                    ngx.say(cjson.encode({ status = "Rate limit exceeded" }))
                    ngx.exit(ngx.HTTP_TOO_MANY_REQUESTS)
                end
            end
        elseif config.interceptType == 1 and config.status == 0 and config.urlAddress == url then
            local ok, err = ip_url_limit.check_and_lock(ip, url, config.requestLimit, config.timeLevel * 60, config.forbidTime)
            if not ok then
                ngx.status = 429
                ngx.header.content_type = "application/json"
                ngx.say(cjson.encode({ status = "Rate limit exceeded" }))
                ngx.exit(ngx.status)
            end
        end
    end
end

