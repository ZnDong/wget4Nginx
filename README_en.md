# wget4Nginx - Nginx Reverse Proxy for Downloading Any Files

[English](./README_en.md) | [简体中文](./README.md)

Implement smart reverse proxy download service using Nginx + Lua, supporting features like automatic redirect following, domain whitelist/blacklist, streaming transmission, resumable downloads, smart DNS resolution, etc.

## 🚀 Features

- ✅ Auto redirect following (configurable max attempts)
- ✅ Chunked streaming transmission (memory optimized)
- ✅ Resumable downloads support (Range header handling)
- ✅ Smart DNS resolution (IPv4/IPv6 dual-stack priority)
- ✅ Domain access control (whitelist/blacklist mechanism)
- ✅ Custom DNS servers
- ✅ SSL certificate verification toggle
- ✅ Custom User-Agent
- ✅ Connection timeout control
- ✅ GET/POST request support

## 📦 Installation

### Requirements
- OpenResty (Recommended) / Nginx (with lua-nginx-module)
- LuaSocket

### Deployment Steps
1. **Install OpenResty**  
   Refer to official documentation for your distribution:  
   📚 [OpenResty Prebuilt Packages Installation](https://openresty.org/en/linux-packages.html)

2. **Install LuaSocket**  
   Recommended via LuaRocks:
    ```bash
    # Install LuaRocks
    sudo apt install luarocks
    # Install LuaSocket
    luarocks install luasocket
    ```

3. **Deploy Configuration Files**
    ```bash
    # Conf files are for reference only - modify as needed before use!
    # Key configuration: Use content_by_lua_file to load the Lua script
    # Create directory
    sudo mkdir -p /usr/local/openresty/nginx/lua

    # Copy config files
    cp wget4Nginx.lua /usr/local/openresty/nginx/lua/
    cp wget4Nginx.conf /usr/local/openresty/nginx/conf/
    ```

4. **Reload Service**
    ```bash
    sudo systemctl reload openresty
    ```

## 🛠 Configuration Guide

### Lua Script Configuration (`wget4Nginx.lua`)

```lua
-- Network protocol priority
local IPV6_FIRST = false            -- Enable IPv6 priority (default: IPv4)

-- Redirect control
local MAX_REDIRECTS = 5             -- Max redirect attempts (prevent infinite loops)

-- Transmission optimization
local CHUNK_SIZE = 8192             -- Chunk size in bytes
local ENABLE_RANGE = true           -- Enable resumable downloads

-- Timeout settings
local DNS_TIMEOUT = 5000            -- DNS query timeout (ms)
local CONN_TIMEOUT = 5000           -- Backend connection timeout (ms)

-- Security
local ENABLE_SSL_VERIFY = true      -- Enable SSL certificate verification
local ACL_MODE = "none"             -- Access control mode: 
                                   -- "whitelist"|"blacklist"|"none"

-- DNS servers
local DNS_SERVERS = {               -- Custom DNS servers
    "1.1.1.1", 
    "8.8.8.8"
}

-- Custom UA
local DEFAULT_UA = "Mozilla/5.0..." -- Default UA (used when client UA is empty)
```

### Domain Access Control

```lua
-- Whitelist (effective when ACL_MODE=whitelist)
local DOMAIN_WHITELIST = {          
    "example.com",                 -- Exact match
    "*.example.com"                -- Wildcard subdomains (excluding example.com)
}

-- Blacklist (effective when ACL_MODE=blacklist)
local DOMAIN_BLACKLIST = {          
    "example.cn",
    "*.example.cn"
}
```

## 🧰 Usage Examples

### Basic Usage
```bash
# Basic URL format
https://wget4Nginx.example.com/{file_url}

# Download example
wget https://wget4Nginx.example.com/https://github.com/example/repo.zip

# Auto-prepend http://
wget https://wget4Nginx.example.com/github.com/example/repo.zip

# Supports URL encoding
wget https://wget4Nginx.example.com/https%3A%2F%2Fgithub.com%2Fexample%2Frepo.zip
```

### Resumable Downloads
```bash
wget --continue https://wget.example.com/http://example.org/bigfile.tar.gz
```

### Partial Content Request
```bash
curl -H "Range: bytes=100-200" https://wget.example.com/http://example.com/testfile
```