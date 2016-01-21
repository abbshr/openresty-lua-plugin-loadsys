local redis = require "resty.redis"
local exception_rules = require "signature.rules"
local util = require "util"

local err = util.err
local ispassaway = util.ispassaway
local encodeURIComponent = util.encodeURIComponent

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
local key = ngx.var.hmac_key
local pool_size = ngx.var.redis_conn_pool_size
local max_idle_ms = ngx.var.redis_conn_max_idle_ms

if dev_mode == 'true' then
  -- forward
  return
elseif not deviceid then
  return err(ngx.HTTP_FORBIDDEN, 'Signature verification failed: deviceid is needed')
elseif not nonce then
  return err(ngx.HTTP_FORBIDDEN, 'Signature verification failed: nonce is needed')
elseif not timestamp then
  return err(ngx.HTTP_FORBIDDEN, 'Signature verification failed: timestamp is needed')
elseif not signature then
  return err(ngx.HTTP_FORBIDDEN, 'Signature verification failed: signature is needed')
end

-- check nonce
local hash = ngx.md5(timestamp):sub(1, 4)
if nonce ~= hash then
  return err(ngx.HTTP_FORBIDDEN, 'Signature verification failed: invalid nonce')
end

-- check timestamp
-- pass: 前后不超过 5 分钟
local now = ngx.now() * 1000
if math.abs(now - timestamp) > 1000 * 60 * 5 then
  return err(ngx.HTTP_FORBIDDEN, 'Signature verification failed: invalid timestamp')
end

local red = redis:new()
red:set_timeout(1000)

local ok, error = red:connect(ngx.var.redis_host, ngx.var.redis_port)
if not ok then
  return err(ngx.HTTP_INTERNAL_SERVER_ERROR, 'Redis connect error: ' .. error)
end

local exist, error = red:get(deviceid .. nonce)
if not exist then
  return err(ngx.HTTP_INTERNAL_SERVER_ERROR, 'Redis get operation error: ' .. error)
end

-- check expire
-- pass: 6 分钟内 key 不能有重复
if exist ~= ngx.null then
  -- 放回连接池
  red:set_keepalive(max_idle_ms, pool_size)
  return err(ngx.HTTP_FORBIDDEN, 'Signature verification failed: key existed')
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
local sign = ngx.hmac_sha1(key, plaintext)
local digest = ngx.encode_base64(sign)

if digest ~= signature then
  red:set_keepalive(max_idle_ms, pool_size)
  return err(ngx.HTTP_FORBIDDEN, 'Signature verification failed: can not verify the signature')
end

-- set nonce in redis with 6 min-expire
-- pass: non-exist
local res, error = red:set(deviceid .. nonce, 1, "EX", 6 * 60 + 1, "NX")
if not res then
  return err(ngx.HTTP_INTERNAL_SERVER_ERROR, 'Redis set operation error: ' .. error)
end

red:set_keepalive(max_idle_ms, pool_size)
-- forward
return
