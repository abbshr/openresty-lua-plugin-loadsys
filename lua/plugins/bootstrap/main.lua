local _M = {
  PRIORI = 0
}

function _M:exec (ctx)
  -- plugin logic
  local failure = true
  ctx.result = {
    err_code = failure
    err_msg = "Not Implement!"
  }

  -- must return the state of the execute result: true/false
  return failure
end

function _M:init (ctx)
  -- initialize
  print("Empty")
  -- must return self
  return self
end

return _M
