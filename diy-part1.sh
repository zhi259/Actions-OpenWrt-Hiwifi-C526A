#!/bin/bash

# 添加 PassWall2 官方源
echo 'src-git passwall2 https://github.com/Openwrt-Passwall/openwrt-passwall2.git;main' >>feeds.conf.default
echo 'src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git;main' >>feeds.conf.default

# 添加 kenzo 源（提供依赖和常用插件）
echo 'src-git kenzo https://github.com/kenzok8/openwrt-packages' >>feeds.conf.default

echo "===== [dnsmasq] 直接修改 Makefile 默认值 ====="
DNSMASQ_MK="package/network/services/dnsmasq/Makefile"
if [ -f "$DNSMASQ_MK" ]; then
    # 将 dnsmasq 的默认配置从 y 改为 n
    sed -i 's/\(define Package\/dnsmasq\/config\).*/\1\n\tdefault n/' "$DNSMASQ_MK" 2>/dev/null || true
    # 更稳妥的方式：直接注释掉 default y 行（需谨慎，可能影响其他变体）
    sed -i '/^[[:space:]]*default y$/s/^/#/' "$DNSMASQ_MK" 2>/dev/null || true
    echo "  OK: $DNSMASQ_MK 默认值已修改"
fi
