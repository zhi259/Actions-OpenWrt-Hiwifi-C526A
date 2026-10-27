#!/bin/bash
# diy-part2.sh —— 适用于 LEDE R25.10.1，整合 cpufreq/ucode/主题/HAProxy QUIC 修复

set -e

echo "===== [1/10] 基础配置修改（LAN IP） ====="
sed -i 's/192.168.1.1/192.168.5.1/g' package/base-files/files/bin/config_generate

echo "===== [2/10] 主题：默认启用 Argon 并预设暗色模式 ====="
for pkg in luci-theme-argon luci-app-argon-config; do
    grep -q "^CONFIG_PACKAGE_${pkg}=y" .config || echo "CONFIG_PACKAGE_${pkg}=y" >> .config
done
sed -i '/CONFIG_PACKAGE_luci-theme-bootstrap/d' .config
sed -i '/CONFIG_DEFAULT_luci-theme-bootstrap/d' .config
rm -rf feeds/kenzo/luci-theme-argon 2>/dev/null || true
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile 2>/dev/null || true
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci-nginx/Makefile 2>/dev/null || true

ARGON_UCI_DIR="package/feeds/luci/luci-theme-argon/uci-defaults"
mkdir -p "$ARGON_UCI_DIR"
cat > "$ARGON_UCI_DIR/99-argon-dark" <<'EOF'
#!/bin/sh
uci -q batch <<-EOT
    set argon.@global[0].mode='dark'
    commit argon
EOT
exit 0
EOF
chmod +x "$ARGON_UCI_DIR/99-argon-dark"

echo "===== [3/10] 编译修复：cmake / HAProxy QUIC ====="
grep -rl 'cmake_minimum_required(VERSION 3.31)' feeds/ | xargs -r sed -i 's/3.31/3.25/g' 2>/dev/null || true

# 禁用 HAProxy QUIC（解决 enum ssl_encryption_level_t 缺失导致的编译失败）
HAPROXY_MK="feeds/packages/net/haproxy/Makefile"
if [ -f "$HAPROXY_MK" ]; then
    # 使用更通用的模式，确保能匹配 ADDON+=USE_QUIC=1 等形式
    sed -i 's/USE_QUIC=1//g' "$HAPROXY_MK"
    sed -i 's/USE_QUIC_OPENSSL_COMPAT=1//g' "$HAPROXY_MK"
    # 清理可能残留的 QUIC 相关配置
    sed -i '/CONFIG_PACKAGE_haproxy.*QUIC/d' .config
    echo "  OK: HAProxy QUIC 支持已禁用（通用模式）"
    # 打印修改后的 Makefile 片段，便于确认
    grep -n "USE_QUIC" "$HAPROXY_MK" || echo "  （Makefile 中已无 USE_QUIC 残留）"
else
    echo "  [WARN] 未找到 $HAPROXY_MK，跳过"
fi

echo "===== [4/10] 清理 ucode-mod / libcrypt-compat 依赖 ====="
find feeds/luci -type f -name Makefile -exec sed -i -E 's/[+]PACKAGE_ucode-mod-(log|socket):ucode-mod-(log|socket)//g; s/[+]ucode-mod-(log|socket)//g' {} \; 2>/dev/null || true
find feeds/luci -type f -name Makefile -exec sed -i 's/+libcrypt-compat//g' {} \; 2>/dev/null || true
find feeds/packages -type f -name Makefile -exec sed -i 's/+libcrypt-compat//g' {} \; 2>/dev/null || true

echo "===== [5/10] 修复 Kconfig 循环依赖（直接禁用 samba） ====="
# 如果不需要 Samba，直接移除这两个包，彻底消除循环依赖
sed -i '/CONFIG_PACKAGE_luci-app-samba/d' .config
sed -i '/CONFIG_PACKAGE_luci-app-samba4/d' .config
sed -i '/CONFIG_DEFAULT_luci-app-samba/d' .config
sed -i '/CONFIG_DEFAULT_luci-app-samba4/d' .config
./scripts/feeds uninstall luci-app-samba luci-app-samba4 2>/dev/null || true

# 保留 baresip 修复（如果需要）
for bp in feeds/packages/net/baresip/Makefile feeds/telephony/net/baresip/Makefile; do
    [ -f "$bp" ] && sed -i 's/+baresip-mod-avcodec//g' "$bp"
done
echo "  OK: samba 循环依赖已通过禁用解决"

echo "===== [5.5/10] 强制修复 R25.10.1 新增循环依赖 ====="
sed -i '/OPENVPN_.*_ENABLE_DCO/d' .config
for v in openssl wolfssl mbedtls; do
    grep -q "^# CONFIG_OPENVPN_${v}_ENABLE_DCO is not set" .config || echo "# CONFIG_OPENVPN_${v}_ENABLE_DCO is not set" >> .config
done
sed -i '/CONFIG_PACKAGE_luci-proto-openvpnc/d' .config
sed -i '/CONFIG_DEFAULT_luci-proto-openvpnc/d' .config
./scripts/feeds uninstall luci-proto-openvpnc 2>/dev/null || true

echo "===== [6/10] PassWall2 修复（透明代理固定 iptables） ====="
for pkg in xray-core v2ray-geodata sing-box chinadns-ng dns2socks hysteria ipt2socks microsocks naiveproxy shadowsocks-rust shadowsocksr-libev simple-obfs tcping v2ray-plugin xray-plugin geoview shadow-tls; do
    rm -rf "feeds/packages/net/$pkg" 2>/dev/null || true
done
rm -rf feeds/luci/applications/luci-app-passwall 2>/dev/null || true
PW2_MAKEFILE="feeds/luci/applications/luci-app-passwall2/Makefile"
if [ -f "$PW2_MAKEFILE" ]; then
    sed -i 's/+geoview//g' "$PW2_MAKEFILE"
    for dep in xray-core v2ray-geoip v2ray-geosite; do sed -i "s/+${dep}//g" "$PW2_MAKEFILE"; done
fi
sed -i '/CONFIG_PACKAGE_luci-app-passwall2_Nftables_Transparent_Proxy=y/d' .config
grep -q "^CONFIG_PACKAGE_luci-app-passwall2_Iptables_Transparent_Proxy=y" .config || echo "CONFIG_PACKAGE_luci-app-passwall2_Iptables_Transparent_Proxy=y" >> .config
./scripts/feeds install -f -a -p passwall_packages
./scripts/feeds install -f luci-app-passwall2

echo "===== [7/10] 强制移除 cpufreq / turboacc ====="
for pkg in luci-app-cpufreq luci-app-turboacc; do
    sed -i "/CONFIG_PACKAGE_${pkg}=/d" .config
    sed -i "/CONFIG_DEFAULT_${pkg}=/d" .config
    ./scripts/feeds uninstall "$pkg" 2>/dev/null || true
done
sed -i '/CONFIG_PACKAGE_cpufreq=/d' .config

echo "===== [8/10] 补全 uhttpd 与 ucode 关键组件 ====="
for pkg in uhttpd uhttpd-mod-ucode uhttpd-mod-lua ucode libucode ucode-mod-fs ucode-mod-log ucode-mod-socket ucode-mod-math ucode-mod-ubus ucode-mod-uci; do
    grep -q "^CONFIG_PACKAGE_${pkg}=y" .config || echo "CONFIG_PACKAGE_${pkg}=y" >> .config
done

echo "===== [9/10] 清理 openvpn DCO 残留 ====="
for ovpn in openvpn-openssl openvpn-wolfssl openvpn-mbedtls; do
    if grep -q "^CONFIG_PACKAGE_${ovpn}=y" .config; then
        sed -i "/CONFIG_PACKAGE_kmod-ovpn-dco/d" .config
    fi
done
echo "===== [dnsmasq] 最终强制互斥检查 ====="
# 删除所有启用形式的基础 dnsmasq（只删 =y 行，保留 # ... is not set）
sed -i '/^CONFIG_PACKAGE_dnsmasq=y/d' .config
sed -i '/^CONFIG_PACKAGE_dnsmasq-dhcpv6=y/d' .config
sed -i '/^CONFIG_PACKAGE_dnsmasq-nftset=y/d' .config

# 确保 dnsmasq-full 启用
grep -q "^CONFIG_PACKAGE_dnsmasq-full=y" .config || echo "CONFIG_PACKAGE_dnsmasq-full=y" >> .config

# 精确验证：只检查基础 dnsmasq 是否被启用（=y），忽略注释和 dnsmasq_full_ 子选项
DNSMASQ_ENABLED=$(grep -E "^CONFIG_PACKAGE_dnsmasq(=|-dhcpv6=|-nftset=)y" .config 2>/dev/null)
if [ -n "$DNSMASQ_ENABLED" ]; then
    echo "  [FATAL] 基础 dnsmasq 仍被启用："
    echo "$DNSMASQ_ENABLED" | sed 's/^/    /'
    exit 1
fi
echo "  OK: 基础 dnsmasq 已禁用，仅保留 dnsmasq-full"

# 诊断前最后一次强制清理 bootstrap，防止被任何步骤写回
sed -i '/^CONFIG_PACKAGE_luci-theme-bootstrap/d' .config
sed -i '/^CONFIG_DEFAULT_luci-theme-bootstrap/d' .config

DIAG_FAIL=0
for k in CONFIG_PACKAGE_uhttpd-mod-ucode CONFIG_PACKAGE_luci-theme-argon; do
    grep -q "^${k}=y" .config && echo "  [OK] $k" || { echo "  [ERR] $k 缺失"; DIAG_FAIL=1; }
done
for k in CONFIG_PACKAGE_luci-app-cpufreq CONFIG_PACKAGE_luci-app-turboacc CONFIG_PACKAGE_luci-theme-bootstrap; do
    if grep -q "^${k}=y" .config; then
        echo "  [ERR] $k 不应启用"
        DIAG_FAIL=1
    else
        echo "  [OK] $k 已禁用"
    fi
done
[ "$DIAG_FAIL" -eq 1 ] && { echo "❌ 诊断失败，终止编译"; exit 1; }
echo "✅ 诊断通过"
echo "===== diy-part2.sh 完成 ====="
