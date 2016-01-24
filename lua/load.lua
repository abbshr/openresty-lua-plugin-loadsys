for _, plugin in ipairs(plugins) do
  if plugin:exec(ngx.ctx) then
    return err(ngx.ctx.result.err_code, ngx.ctx.result.err_msg)
  end
end

-- forward
