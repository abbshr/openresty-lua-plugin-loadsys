local json = require "cjson"

local _M = {}

function _M.err (code, message)
  -- resp
  local res = {
    err_code = code;
    err_msg = message;
  }

  ngx.status = ngx.HTTP_OK
  ngx.header["Content-Type"] = 'application/json'
  ngx.say(json.encode(res))
  ngx.exit(ngx.HTTP_OK)
end

-- https://github.com/daurnimator/lua-http/blob/master/http/util.lua
function _M.char_to_pchar (c)
	return string.format("%%%02X", c:byte(1,1))
end
-- https://github.com/daurnimator/lua-http/blob/master/http/util.lua
function _M.encodeURIComponent (str)
	return (str:gsub("[^%w%-_%.%!%~%*%'%(%)]", char_to_pchar))
end

function string:split (pat)
   local t = {}  -- NOTE: use {n = 0} in Lua-5.0
   local fpat = "(.-)" .. pat
   local last_end = 1
   local s, e, cap = self:find(fpat, 1)
   while s do
      if s ~= 1 or cap ~= "" then
	       table.insert(t,cap)
      end
      last_end = e+1
      s, e, cap = self:find(fpat, last_end)
   end
   if last_end <= #self then
      cap = self:sub(last_end)
      table.insert(t, cap)
   end
   return t
end

function _M.ispassaway (rules, path)
  for _, epatt in ipairs(rules) do
    -- 开启 pattern 缓存
    local m, err = ngx.re.match(path, epatt, 'o')
    if m then
      return true
    end
  end
end

function _M.ipmatch (cfg, ip)
  -- body...
  local matched
  local tokens = ip:split('%.')
  for rule, cfg in pairs(cfg) do
    for i, patt in ipairs(rule:split('%.')) do
      if patt ~= '*' and tokens[i] ~= patt then
        matched = false
        break
      end
      matched = true
    end
    if matched then
      return cfg
    end
  end
end

return _M
