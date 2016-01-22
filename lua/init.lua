-- init openresty lua plugins system
-- local pathtb = {
--   plugins_path = '/plugins/?.lua';
--   main_path = '/?.lua';
-- }

-- for _, path in pairs(pathtb) do
--   package.path = package.path .. ';' .. ngx.var.lua_package_path .. path
-- end

plugins = {}

local plg_lst = require "plugin-list"
for _, plg_name in ipairs(plg_lst) do
  table.insert(plugins, require("plugins." .. plg_name .. '.main'):init())
end

table.sort(plugins, function (pa, pb)
  return pa.PRIORI > pb.PRIORI
end)
