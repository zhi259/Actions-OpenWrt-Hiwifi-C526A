#!/bin/bash
# diy-part2.sh —— 在 feeds update / install 之后、make 之前执行

set -e

echo "===== [1/5] 基础配置修改 ====="
# 默认管理地址
sed -i 's/192.168.1.1/192.168.5.1/g' package/base-files/files/bin/config_generate

# 默认主题切换为 argon
rm -rf feeds/kenzo/luci-theme-argon
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci-nginx/Makefile 2>/dev/null || true

echo "===== [2/5] 编译修复 ====="
# 全局降级 CMake，解决 rpcd-mod-luci 报错
grep -rl 'cmake_minimum_required(VERSION 3.31)' feeds/ \
  | xargs sed -i 's/cmake_minimum_required(VERSION 3.31)/cmake_minimum_required(VERSION 3.25)/g' 2>/dev/null || true

# haproxy QUIC/OpenSSL 修复
HAPROXY_MAKEFILE="feeds/packages/net/haproxy/Makefile"
if [ -f "$HAPROXY_MAKEFILE" ]; then
    sed -i 's/USE_QUIC=1/USE_QUIC=0/g' "$HAPROXY_MAKEFILE"
    sed -i 's/ USE_QUIC_OPENSSL_COMPAT=1//g' "$HAPROXY_MAKEFILE"
fi

echo "===== [3/5] 清理 lede 自带的 PassWall 冲突包 ====="
# 这些包在 lede feeds/packages 里是旧版本，会与 passwall_packages 源冲突
for pkg in xray-core v2ray-geodata sing-box chinadns-ng dns2socks hysteria \
           ipt2socks microsocks naiveproxy shadowsocks-rust shadowsocksr-libev \
           simple-obfs tcping v2ray-plugin xray-plugin geoview shadow-tls; do
    rm -rf "feeds/packages/net/$pkg"
done
rm -rf feeds/luci/applications/luci-app-passwall

echo "===== [4/5] 从 passwall_packages 源批量强制重新安装 ====="
# 关键修正：原脚本的 `./scripts/feeds install -f passwall_packages` 是错的——
# `-f` 后面跟的是"包名"，不是 feed 名。这行会静默失败或报 "unknown package"，
# 导致 tcping / geoview / v2ray-geodata 根本没有被链接进 package/feeds/。
# 正确语法：-a 表示"整个 feed 全部安装"，-p 指定 feed 名，-f 强制覆盖已有链接。
./scripts/feeds install -f -a -p passwall_packages

# luci-app-passwall2 来自 passwall2 源，单独强制安装
./scripts/feeds install -f luci-app-passwall2

echo "===== [5/5] 补全 .config 缺失依赖 ====="
# ucode-mod-log    → luci-base 依赖
# ucode-mod-socket → luci-mod-status 依赖
# cpufreq          → luci-app-cpufreq 依赖
for cfg in \
    CONFIG_PACKAGE_ucode-mod-log \
    CONFIG_PACKAGE_ucode-mod-socket \
    CONFIG_PACKAGE_cpufreq; do
    grep -q "^${cfg}=y" .config || echo "${cfg}=y" >> .config
done

# ===== 强制安装 23.05 LuCI 所需的 ucode 模块 =====
for pkg in ucode-mod-log ucode-mod-socket; do
    ./scripts/feeds install -f "$pkg"
done

# 如果上面提示 unknown package，尝试从 luci feed 全局重装
if ./scripts/feeds install -f ucode-mod-log 2>&1 | grep -q "unknown package"; then
    ./scripts/feeds install -a -p luci
fi

# 确保 cpufreq 被选中
grep -q '^CONFIG_PACKAGE_cpufreq=y' .config || echo 'CONFIG_PACKAGE_cpufreq=y' >> .config

echo "===== diy-part2.sh 执行完毕 ====="