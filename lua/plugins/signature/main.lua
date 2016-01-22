local redis = require "resty.redis"
local util = require "util"

local exception_rules = require "plugins.signature.rules"
local config = require "config"

local ispassaway = util.ispassaway
local encodeURIComponent = util.encodeURIComponent

local _M = {
  PRIORI = 2
}

function _M:exec (ctx)
  -- check exception
  if ispassaway(exception_rules, ngx.var.uri) then
    -- 不需要验证签名
    return
  end

  local header = ngx.req.get_headers()
  local method = ngx.var.request_method
  local fullpath = ngx.var.request_uri
  local deviceid = header['deviceid']
  local nonce = header['nonce']
  local timestamp = header['timestamp']
  local dev_mode = header['dev']
  local signature = header['signature']

  if dev_mode == 'true' then
    -- forward
    return
  elseif not deviceid then
    ctx.result = {
      err_code = ngx.HTTP_FORBIDDEN;
      err_msg = 'Signature verification failed: deviceid is needed';
    }
    return true
  elseif not nonce then
    ctx.result = {
      err_code = ngx.HTTP_FORBIDDEN;
      err_msg = 'Signature verification failed: nonce is needed';
    }
    return true
  elseif not timestamp then
    ctx.result = {
      err_code = ngx.HTTP_FORBIDDEN;
      err_msg = 'Signature verification failed: timestamp is needed';
    }
    return true
  elseif not signature then
    ctx.result = {
      err_code = ngx.HTTP_FORBIDDEN;
      err_msg = 'Signature verification failed: signature is needed';
    }
    return true
  end

  -- check nonce
  local hash = ngx.md5(timestamp):sub(1, 4)
  if nonce ~= hash then
    ctx.result = {
      err_code = ngx.HTTP_FORBIDDEN;
      err_msg = 'Signature verification failed: invalid nonce';
    }
    return true
  end

  -- check timestamp
  -- pass: 前后不超过 5 分钟
  local now = ngx.now() * 1000
  if math.abs(now - timestamp) > 1000 * 60 * 5 then
    ctx.result = {
      err_code = ngx.HTTP_FORBIDDEN;
      err_msg = 'Signature verification failed: invalid timestamp';
    }
    return true
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

  local exist, error = red:get(deviceid .. nonce)
  if not exist then
    ctx.result = {
      err_code = ngx.HTTP_INTERNAL_SERVER_ERROR;
      err_msg = 'Redis get operation error: ' .. error;
    }
    return true
  end

  -- check expire
  -- pass: 6 分钟内 key 不能有重复
  if exist ~= ngx.null then
    -- 放回连接池
    red:set_keepalive(config.REDIS_CONN_MAX_IDLE_MS, config.REDIS_CONN_POOL_SIZE)
    ctx.result = {
      err_code = ngx.HTTP_FORBIDDEN;
      err_msg = 'Signature verification failed: key existed';
    }
    return true
  end

  -- handle large body
  -- 延后读取 body, 减轻 Nginx Worker 负载保证处理能力
  ngx.req.read_body()
  local body = ngx.req.get_body_data() or ngx.req.get_body_file() or ""

  local plaintext = table.concat({
    method, fullpath, deviceid, nonce, timestamp, body
  }, '&')
  plaintext = encodeURIComponent(plaintext)

  -- check signature (binary-encoding)
  local sign = ngx.hmac_sha1(config.HMAC_KEY, plaintext)
  local digest = ngx.encode_base64(sign)

  if digest ~= signature then
    red:set_keepalive(config.REDIS_CONN_MAX_IDLE_MS, config.REDIS_CONN_POOL_SIZE)
    ctx.result = {
      err_code = ngx.HTTP_FORBIDDEN;
      err_msg = "Signature verification failed: can not verify the signature";
    }
    return true
  end

  -- set nonce in redis with 6 min-expire
  -- pass: non-exist
  local res, error = red:set(deviceid .. nonce, 1, "EX", 6 * 60 + 1, "NX")
  if not res then
    ctx.result = {
      err_code = ngx.HTTP_INTERNAL_SERVER_ERROR;
      err_msg = 'Redis set operation error: ' .. error;
    }
    return true
  end

  red:set_keepalive(config.REDIS_CONN_MAX_IDLE_MS, config.REDIS_CONN_POOL_SIZE)
end

function _M:init (args)
  -- body...
  return self
end

return _M
