local redis = require 'resty.redis'
local util = require "util"
local gcfg = require "ratelimit.cfg"

local err = util.err
local ipmatch = util.ipmatch
local split = util.split
local ipv4 = ngx.var.remote_addr

-- 检查是否配置限速策略
local cfg = ipmatch(gcfg, ipv4)
if not cfg then
  return
end

local red = redis:new()
red:set_timeout(1000)
local ok, error = red:connect(ngx.var.redis_host, ngx.var.redis_port)
if not ok then
  return err(ngx.HTTP_INTERNAL_SERVER_ERROR, 'Redis connect error: ' .. error)
end

-- 取 bucket 内剩余量和上次访问时间
local bucket, error = red:get(ipv4 .. ':' .. ngx.var.bucket_status)
if not bucket then
  return err(ngx.HTTP_INTERNAL_SERVER_ERROR, 'Redis get operation error: ' .. error)
end

local last_access_time = 0
local last_remain = 0
if bucket ~= ngx.null then
  bucket = tostring(bucket):split('%#')
  last_access_time = bucket[1]
  last_remain = bucket[2]
end

-- throttle
-- 弹性配额策略 (无锁实现不损失性能)
-- TODO: 使用一个 agent 进程周期性搜集 throttle workers 统计数据, 做动态负载分流
local current_access_time = ngx.now() * 1000
local duration = current_access_time - last_access_time

local used = math.max(0, last_remain - cfg['rate'] * duration)
if used + 1 > cfg['capicity'] then
  red:set_keepalive(ngx.var.max_idle_ms, ngx.var.pool_size)
  return err(429, 'Max rate limit quota exceeded')
else
  last_remain = used + 1
  last_access_time = current_access_time
end

-- 放行后更新 bucket 的使用量和最后一次访问时间
local res, error = red:set(ipv4 .. ':' .. ngx.var.bucket_status, last_access_time .. '#' .. last_remain)

red:set_keepalive(ngx.var.max_idle_ms, ngx.var.pool_size)
