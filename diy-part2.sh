#!/bin/bash
# diy-part2.sh —— 在 feeds update / install 之后、make 之前执行

# 修改默认管理地址和主机名（按你自己的喜好保留）
sed -i 's/192.168.1.1/192.168.5.1/g' package/base-files/files/bin/config_generate
#sed -i 's/OpenWrt/OpenRoute/g' package/base-files/files/bin/config_generate

# 默认主题切换为 argon
rm -rf feeds/kenzo/luci-theme-argon
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci-nginx/Makefile 2>/dev/null || true

# 核心修复：全局降级 CMake 版本要求，彻底解决 rpcd-mod-luci 报错
grep -rl 'cmake_minimum_required(VERSION 3.31)' feeds/ | xargs sed -i 's/cmake_minimum_required(VERSION 3.31)/cmake_minimum_required(VERSION 3.25)/g' 2>/dev/null || true

# 移除 lede feeds 自带的 PassWall 核心冲突库
rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,v2ray-plugin,xray-plugin,geoview,shadow-tls}

# 移除 lede 自带的过时 PassWall LuCI 应用
rm -rf feeds/luci/applications/luci-app-passwall

# 1. 清理 lede 自带的冲突核心库（与之前列表一致，这是基础）
rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,hysteria,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,v2ray-plugin,xray-plugin,geoview}

# 2. 关键：确保 passwall_packages 源正确安装（如果之前 install 过，-f 强制刷新）
./scripts/feeds install -f passwall_packages
./scripts/feeds install -f luci-app-passwall2

# 3. 可选：如果 geoview 仍然报错，尝试从 passwall_packages 单独强制安装
# ./scripts/feeds install -f geoview

# 修复 haproxy 的 QUIC/OpenSSL 编译错误
HAPROXY_MAKEFILE="feeds/packages/net/haproxy/Makefile"
if [ -f "$HAPROXY_MAKEFILE" ]; then
    sed -i 's/USE_QUIC=1/USE_QUIC=0/g' "$HAPROXY_MAKEFILE"
    sed -i 's/ USE_QUIC_OPENSSL_COMPAT=1//g' "$HAPROXY_MAKEFILE"
fi


