#!/bin/bash
# diy-part2.sh —— 在 feeds update / install 之后、make 之前执行

set -e

echo "===== [1/5] 基础配置修改 ====="
sed -i 's/192.168.1.1/192.168.5.1/g' package/base-files/files/bin/config_generate

rm -rf feeds/kenzo/luci-theme-argon
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci-nginx/Makefile 2>/dev/null || true

echo "===== [2/5] 编译修复 ====="
grep -rl 'cmake_minimum_required(VERSION 3.31)' feeds/ \
  | xargs sed -i 's/cmake_minimum_required(VERSION 3.31)/cmake_minimum_required(VERSION 3.25)/g' 2>/dev/null || true

HAPROXY_MAKEFILE="feeds/packages/net/haproxy/Makefile"
if [ -f "$HAPROXY_MAKEFILE" ]; then
    sed -i 's/USE_QUIC=1/USE_QUIC=0/g' "$HAPROXY_MAKEFILE"
    sed -i 's/ USE_QUIC_OPENSSL_COMPAT=1//g' "$HAPROXY_MAKEFILE"
fi

echo "===== [2.5/5] 解决新版 luci 与旧版 ucode 的依赖冲突 ====="
# 1. 移除 luci 对不存在的 ucode-mod-log / ucode-mod-socket 的硬依赖
#    兼容两种写法：+ucode-mod-xxx 和 +PACKAGE_ucode-mod-xxx:ucode-mod-xxx
find feeds/luci -type f -name Makefile -exec sed -i -E 's/[+]PACKAGE_ucode-mod-(log|socket):ucode-mod-(log|socket)//g; s/[+]ucode-mod-(log|socket)//g' {} \;

# 2. 顺手移除 musl 环境下不需要的 libcrypt-compat 依赖（日志中大量重复 WARNING 来自这里）
find feeds/luci -type f -name Makefile -exec sed -i 's/+libcrypt-compat//g' {} \;
find feeds/packages -type f -name Makefile -exec sed -i 's/+libcrypt-compat//g' {} \;

# 3. 验证关键 luci 包的依赖已被清理
for f in feeds/luci/modules/luci-base/Makefile feeds/luci/modules/luci-mod-status/Makefile; do
    if [ -f "$f" ]; then
        if grep -q 'ucode-mod-log\|ucode-mod-socket' "$f"; then
            echo "WARNING: $f 仍包含 ucode-mod-log/socket 依赖"
        else
            echo "OK: $f 依赖已清理"
        fi
    fi
done

echo "===== [3/5] 清理 lede 自带的 PassWall 冲突包 ====="
for pkg in xray-core v2ray-geodata sing-box chinadns-ng dns2socks hysteria \
           ipt2socks microsocks naiveproxy shadowsocks-rust shadowsocksr-libev \
           simple-obfs tcping v2ray-plugin xray-plugin geoview shadow-tls; do
    rm -rf "feeds/packages/net/$pkg"
done
rm -rf feeds/luci/applications/luci-app-passwall

echo "===== [4/5] 从 passwall_packages 源批量强制重新安装 ====="
./scripts/feeds install -f -a -p passwall_packages
./scripts/feeds install -f luci-app-passwall2

echo "===== [5/5] 诊断 ====="
# 1. ucode 核心源码存在性（仅确认父包源码在）
if [ -f package/utils/ucode/Makefile ]; then
    echo "OK: package/utils/ucode/Makefile 存在"
else
    echo "WARNING: package/utils/ucode/Makefile 缺失"
fi

# 2. 关键 feed 目录
for d in feeds/passwall_packages feeds/luci feeds/packages package/feeds/passwall_packages; do
    [ -e "$d" ] && echo "OK: $d 存在" || echo "WARNING: $d 缺失"
done

# 3. 确认 luci-base / luci-mod-status 的依赖已清理
if grep -q 'ucode-mod-log\|ucode-mod-socket' feeds/luci/modules/luci-base/Makefile 2>/dev/null; then
    echo "WARNING: luci-base 仍包含 ucode-mod-log/socket 依赖"
else
    echo "OK: luci-base 依赖已清理"
fi
if grep -q 'ucode-mod-socket' feeds/luci/modules/luci-mod-status/Makefile 2>/dev/null; then
    echo "WARNING: luci-mod-status 仍包含 ucode-mod-socket 依赖"
else
    echo "OK: luci-mod-status 依赖已清理"
fi

echo "===== diy-part2.sh 执行完毕 ====="
