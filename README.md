# wget4Nginx - Nginx反向代理下载任意文件

[简体中文](./README.md) | [English](./README_en.md)

通过 Nginx + Lua实现智能反向代理下载服务，支持多次自动跟随重定向、域名黑白名单、流式传输、断点续传、智能 DNS解析等功能。

## 🚀 功能特性

- ✅ 自动跟随重定向（可配置最大次数）
- ✅ 分块流式传输（内存优化）
- ✅ 断点续传支持（Range头处理）
- ✅ 智能 DNS解析（IPv4/IPv6双栈优先）
- ✅ 域名访问控制（黑白名单机制）
- ✅ 自定义 DNS服务器
- ✅ SSL证书验证开关
- ✅ 自定义 User-Agent
- ✅ 连接超时控制
- ✅ 支持 GET和 POST请求

## 📦 安装部署

### 环境要求
- OpenResty(推荐) / Nginx (with lua-nginx-module)
- LuaSocket

### 部署步骤
1. **安装 OpenResty**  
   请根据发行版参考官方文档安装：  
   📚 [OpenResty官方预编译包安装](https://openresty.org/cn/linux-packages.html)

2. **安装 LuaSocket**  
   建议通过 LuaRocks安装
    ```bash
    # 安装 LuaRocks
    sudo apt install luarocks
    # 安装 LuaSocket
    luarocks install luasocket
    ```

3. **部署配置文件**
    ```bash
    # conf文件仅供参考，使用前请按需修改！
    # 关键在于使用 content_by_lua_file加载本项目的 lua脚本
    # 创建目录
    sudo mkdir -p /usr/local/openresty/nginx/lua

    # 复制配置文件
    cp wget4Nginx.lua /usr/local/openresty/nginx/lua/
    cp wget4Nginx.conf /usr/local/openresty/nginx/conf/
    ```

4. **重载服务**
    ```bash
    sudo systemctl reload openresty
    ```

## 🛠 配置详解

### Lua脚本配置 (`wget4Nginx.lua`)

```lua
-- 网络协议优先级
local IPV6_FIRST = false            -- 启用 IPv6解析优先（默认为 IPV4优先）

-- 重定向控制
local MAX_REDIRECTS = 5             -- 最大重定向次数（防止死循环）

-- 传输优化
local CHUNK_SIZE = 8192             -- 分块传输大小(bytes)
local ENABLE_RANGE = true           -- 启用断点续传支持

-- 超时设置
local DNS_TIMEOUT = 5000            -- DNS查询超时(ms)
local CONN_TIMEOUT = 5000           -- 后端连接超时(ms)

-- 安全配置
local ENABLE_SSL_VERIFY = true      -- 开启 SSL证书验证
local ACL_MODE = "none"             -- 访问控制模式: 
                                   -- "whitelist"|"blacklist"|"none"

-- DNS服务器配置
local DNS_SERVERS = {               -- 自定义 DNS服务器池
    "1.1.1.1", 
    "8.8.8.8"
}

-- 自定义 UA
local DEFAULT_UA = "Mozilla/5.0..." -- 缺省 UA（默认使用客户端 UA，仅当客户端 UA为空时使用，如不需要可置空）
```

### 域名访问控制

```lua
-- 白名单配置（当ACL_MODE=whitelist时生效）
local DOMAIN_WHITELIST = {          
    "example.com",                 -- 精确匹配
    "*.example.com"                -- 通配符匹配子域名（不包括example.com）
}

-- 黑名单配置（当ACL_MODE=blacklist时生效）
local DOMAIN_BLACKLIST = {          
    "example.cn",
    "*.example.cn"
}
```

## 🧰 使用示例

### 基础使用
```bash
# 基本链接格式
https://wget4Nginx.example.com/{file_url}

# 下载示例
wget https://wget4Nginx.example.com/https://github.com/example/repo.zip

# 脚本将自动补充 http://
wget https://wget4Nginx.example.com/github.com/example/repo.zip

# 脚本支持网址编码
wget https://wget4Nginx.example.com/https%3A%2F%2Fgithub.com%2Fexample%2Frepo.zip
```

### 断点续传
```bash
wget --continue https://wget.example.com/http://example.org/bigfile.tar.gz
```

### 指定下载范围
```bash
curl -H "Range: bytes=100-200" https://wget.example.com/http://example.com/testfile
```

