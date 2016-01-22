-- 基于 IPv4 的限流参数配置
local ip_cfg = {
  ['127.0.0.1'] = {
    interval = 1000 * 60;
    capicity = 10;
  };
  ['192.168.*.*'] = {
    interval = 1000 * 60;
    capicity = 1000;
  };
  ['172.16.0.5'] = {
    interval = 1000 * 60;
    capicity = 500;
  };
}

for _, cfg in pairs(ip_cfg) do
  cfg.rate = cfg.capicity / cfg.interval
end

return ip_cfg
