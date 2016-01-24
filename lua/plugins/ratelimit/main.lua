local redis = require 'resty.redis'
local util = require "util"

local strategy = require "plugins.ratelimit.strategy"
local config = require "plugins.ratelimit.config"

local _M = {
  PRIORI = 1
}

function _M:exec (ctx)
  local ipv4 = ngx.var.remote_addr

  -- 检查是否配置限速策略
  local cfg = util.ipmatch(strategy, ipv4)
  if not cfg then
    ctx.result = nil
    return
  end

  local red = redis:new()
  red:set_timeout(config.REDIS_CONN_TIMEOUT)
  local ok, error = red:connect(config.REDIS_HOST, config.REDIS_PORT)
  if not ok then
    ctx.result = {
      err_code = ngx.HTTP_INTERNAL_SERVER_ERROR;
      err_msg = 'Redis connect error: ' .. error;
    }
    return true
  end

  -- 取 bucket 内剩余量和上次访问时间
  local bucket, error = red:get(ipv4 .. ':' .. config.BUCKET_STATUS)
  if not bucket then
    ctx.result = {
      err_code = ngx.HTTP_INTERNAL_SERVER_ERROR;
      err_msg = 'Redis get operation error: ' .. error;
    }
    return true
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
  local rate = cfg.capicity / cfg.interval

  local used = math.max(0, last_remain - rate * duration)
  if used + 1 > cfg['capicity'] then
    red:set_keepalive(config.REDIS_CONN_MAX_IDLE_MS, config.REDIS_CONN_POOL_SIZE)
    ctx.result = {
      err_code = 429;
      err_msg = 'Max rate limit quota exceeded';
    }
    return true
  else
    last_remain = used + 1
    last_access_time = current_access_time
  end

  -- 放行后更新 bucket 的使用量和最后一次访问时间
  local res, error = red:set(ipv4 .. ':' .. config.BUCKET_STATUS, last_access_time .. '#' .. last_remain)
  if res then
    red:set_keepalive(config.REDIS_CONN_MAX_IDLE_MS, config.REDIS_CONN_POOL_SIZE)
  end
end

function _M:init (args)
  -- body...
  return self
end

return _M
