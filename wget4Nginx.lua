local http = require "resty.http"
local url = require "socket.url"
local dns = require "resty.dns.resolver"

-- 配置区域 -------------------------------------------------
local IPV6_FIRST = false            -- true=IPv6优先，false=IPv4优先
local MAX_REDIRECTS = 5             -- 最大重定向次数
local CHUNK_SIZE = 8192             -- 分块传输大小
local ENABLE_RANGE = true           -- 启用断点续传
local DNS_TIMEOUT = 5000            -- DNS查询超时(ms)
local CONN_TIMEOUT = 5000           -- 连接超时(ms)
local ENABLE_SSL_VERIFY = true      -- 启用SSL证书验证
local DNS_SERVERS = {               -- DNS服务器列表
    "1.1.1.1", "8.8.8.8"
}
local ACL_MODE = "none"             -- 访问控制模式: "whitelist"/"blacklist"/"none"
local DOMAIN_WHITELIST = {          -- 白名单域名列表(ACL_MODE=whitelist时生效)
    "example.com",
    "*.example.com"
}
local DOMAIN_BLACKLIST = {          -- 黑名单域名列表(ACL_MODE=blacklist时生效)
    "example.cn",
    "*.example.cn"
}
local DEFAULT_UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36"
-- 结束配置 -------------------------------------------------

-- 连接管理 -------------------------------------------------
local current_httpc = nil

local function close_httpc()
    if current_httpc then
        pcall(current_httpc.close, current_httpc)
        current_httpc = nil
    end
end

ngx.on_abort(close_httpc)

local function error_response(status, message)
    close_httpc()
    ngx.status = status
    ngx.header["Content-Type"] = "text/plain"
    ngx.say(message)
    ngx.exit(status)
end

-- URL解析 -------------------------------------------------
local function parse_target_url(target_url)
    local parsed = url.parse(target_url)
    parsed.scheme = parsed.scheme or "http"
    parsed.port = parsed.port or (parsed.scheme == "https" and 443 or 80)
    parsed.host = parsed.host or ""
    parsed.path = parsed.path or "/"
    return parsed
end

-- 域名匹配 -------------------------------------------------
local function match_domain(pattern, domain)
    pattern = pattern:lower()
    domain = domain:lower():match("[^:]+")
    
    if pattern:sub(1,2) == "*." then
        local suffix = pattern:sub(3)
        -- 检查 domain 是否以 ".suffix" 结尾，确保匹配的是子域名而不是根域名
        return domain:match("%." .. suffix .. "$") ~= nil
    end
    return domain == pattern
end

-- ACL检查 --------------------------------------------------
local function check_domain_access(domain)
    if ACL_MODE:lower() == "whitelist" then
        for _, pattern in ipairs(DOMAIN_WHITELIST) do
            if match_domain(pattern, domain) then return true end
        end
        return false
    elseif ACL_MODE:lower() == "blacklist" then
        for _, pattern in ipairs(DOMAIN_BLACKLIST) do
            if match_domain(pattern, domain) then return false end
        end
        return true
    end
    return true
end

-- DNS解析 --------------------------------------------------
local function resolve_host(host)
    local resolver, err = dns:new{
        nameservers = DNS_SERVERS,
        retrans = 3,
        timeout = DNS_TIMEOUT,
    }
    if not resolver then return nil, "DNS init failed: "..(err or "unknown error") end

    local function query(qtype)
        local answers, err = resolver:query(host, { qtype = qtype })
        if not answers then return nil, err end
        if answers.errcode then return nil, answers.errstr end
        
        local results = {}
        for _, ans in ipairs(answers) do
            if ans.type == qtype and ans.address then
                table.insert(results, {
                    address = (qtype == dns.TYPE_AAAA and "["..ans.address.."]" or ans.address),
                    ttl = ans.ttl or 300
                })
            end
        end
        return #results > 0 and results or nil
    end

    local addresses = {}
    local aaaa = query(dns.TYPE_AAAA)
    local a = query(dns.TYPE_A)
    
    if IPV6_FIRST then
        if aaaa then for _, v in ipairs(aaaa) do table.insert(addresses, v) end end
        if a then for _, v in ipairs(a) do table.insert(addresses, v) end end
    else
        if a then for _, v in ipairs(a) do table.insert(addresses, v) end end
        if aaaa then for _, v in ipairs(aaaa) do table.insert(addresses, v) end end
    end
    
    if #addresses == 0 then
        return nil, "No DNS records found for "..host
    end
    return addresses
end

-- 请求头处理 -----------------------------------------------
local function process_request_headers(parsed)
    local hop_headers = {
        ["connection"] = true,
        ["keep-alive"] = true,
        ["proxy-authenticate"] = true,
        ["proxy-authorization"] = true,
        ["te"] = true,
        ["trailers"] = true,
        ["transfer-encoding"] = true,
        ["upgrade"] = true,
        ["content-length"] = true,
        ["host"] = true
    }

    local headers = {}
    local req_headers = ngx.req.get_headers()
    
    for k, v in pairs(req_headers) do
        if not hop_headers[k:lower()] then
            headers[k] = type(v) == "table" and table.concat(v, ", ") or v
        end
    end

    headers.Host = parsed.host
    headers["User-Agent"] = headers["User-Agent"] or DEFAULT_UA
    headers.Accept = headers.Accept or "*/*"
    
    if not ENABLE_RANGE then
        headers.Range = nil
    end

    return headers
end

-- 建立后端连接 ---------------------------------------------
local function connect_backend(parsed, addresses)
    for _, addr in ipairs(addresses) do
        current_httpc = http.new()
        current_httpc:set_timeout(CONN_TIMEOUT)

        local ok, err = current_httpc:connect{
            host = addr.address,
            port = parsed.port,
            scheme = parsed.scheme,
            ssl_verify = false
        }

        if ok and parsed.scheme == "https" then
            ok, err = current_httpc:ssl_handshake(true, parsed.host, ENABLE_SSL_VERIFY)
        end

        if ok then return true end
        ngx.log(ngx.WARN, "Connection failed to "..addr.address..": "..(err or "unknown"))
        close_httpc()
    end
    return false, "All connection attempts failed"
end

-- 处理响应数据 ---------------------------------------------
local function process_response(res)
    -- 需要跳过的响应头
    local exclude_headers = {
        ["transfer-encoding"] = true,
        ["connection"] = true,
        ["content-length"] = (res.status == 206)
    }

    -- 设置响应头
    for k, v in pairs(res.headers) do
        if not exclude_headers[k:lower()] then
            ngx.header[k] = v
        end
    end

    -- 流式传输
    local reader = res.body_reader
    repeat
        local chunk, err = reader(CHUNK_SIZE)
        if err then
            ngx.log(ngx.ERR, "Stream read error: ", err)
            break
        end
        if chunk then
            local ok, send_err = ngx.print(chunk)
            ngx.flush(true)
            if not ok then
                ngx.log(ngx.INFO, "Client disconnected: ", send_err)
                break
            end
        end
    until not chunk
end

-- 主流程 ---------------------------------------------------
local function main()
    local redirect_count = 0
    local target_url = ngx.unescape_uri(ngx.var.request_uri:gsub("^/+", ""))
    target_url = target_url:find("^https?://") and target_url or "http://"..target_url

    while redirect_count <= MAX_REDIRECTS do
        -- host检查
        local parsed = parse_target_url(target_url)
        if parsed.host == "" then
            error_response(400, "Invalid URL: Missing hostname")
        end

        -- 域名检查
        if not check_domain_access(parsed.host) then
            error_response(403, "Access denied for domain: "..domain)
        end

        -- DNS解析
        local addresses, err = resolve_host(parsed.host)
        if not addresses then
            error_response(502, "DNS resolution failed for host: " .. parsed.host ..  
                "\nError: " .. err ..
                "\nTarget URL: " .. target_url)
        end

        -- 建立连接
        local ok, conn_err = connect_backend(parsed, addresses)
        if not ok then
            error_response(502, "Connection failed: "..conn_err)
        end

        -- 构造请求
        local path = parsed.path
        if parsed.query then path = path.."?"..parsed.query end

        local res, req_err = current_httpc:request{
            method = ngx.req.get_method(),
            path = path,
            headers = process_request_headers(parsed),
            body = ngx.req.get_method() == "POST" and ngx.req.get_body_data() or nil
        }

        if not res then
            error_response(502, "Backend request failed: "..req_err)
        end

        -- 处理重定向
        if res.status >= 300 and res.status < 400 then
            local location = res.headers.Location or res.headers.location
            if location then
                redirect_count = redirect_count + 1
                target_url = url.absolute(target_url, location)
                close_httpc()
                ngx.log(ngx.INFO, "Redirecting to: ", target_url)
            else
                error_response(502, "Redirect missing Location header")
            end
        else
            ngx.status = res.status
            process_response(res)
            close_httpc()
            return
        end
    end
    error_response(508, "Too many redirects (max "..MAX_REDIRECTS..")")
end

-- 启动执行 -------------------------------------------------
main()