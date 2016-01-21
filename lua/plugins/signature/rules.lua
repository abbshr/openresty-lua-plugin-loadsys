-- 签名例外规则 (posix regexp)
return {
  [[^/variants/\d+/?$]],
  [[^/tokenservice/?$]],
  [[^/reviews/?$]],
  [[^/alipay/?$]],
  [[^/config/?$]],
  [[^/netease/?$]]
}
