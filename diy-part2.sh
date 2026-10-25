#!/bin/bash
# diy-part2.sh —— 在 feeds update / install 之后、make defconfig 之前执行
# 增强版：覆盖 R25.10.1 新增的 OpenVPN DCO / luci-proto-openvpnc 循环依赖

set -e

# =====================================================
# 修复阶段
# =====================================================
echo "===== [1/10] 基础配置修改（LAN IP） ====="
sed -i 's/192.168.1.1/192.168.5.1/g' package/base-files/files/bin/config_generate

echo "===== [2/10] 主题：默认启用 Argon 并预设暗色模式 ====="
for pkg in luci-theme-argon luci-app-argon-config; do
    grep -q "^CONFIG_PACKAGE_${pkg}=y" .config || echo "CONFIG_PACKAGE_${pkg}=y" >> .config
done
sed -i '/CONFIG_PACKAGE_luci-theme-bootstrap=y/d' .config
rm -rf feeds/kenzo/luci-theme-argon 2>/dev/null || true
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile 2>/dev/null || true
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci-nginx/Makefile 2>/dev/null || true

ARGON_UCI_DEFAULTS="package/feeds/luci/luci-theme-argon/uci-defaults"
mkdir -p "$ARGON_UCI_DEFAULTS"
cat > "$ARGON_UCI_DEFAULTS/99-argon-dark" <<'EOF'
#!/bin/sh
uci -q batch <<-EOT
    set argon.@global[0].mode='dark'
    commit argon
EOT
exit 0
EOF
chmod +x "$ARGON_UCI_DEFAULTS/99-argon-dark"
cat > "$ARGON_UCI_DEFAULTS/98-argon-default" <<'EOF'
#!/bin/sh
uci -q batch <<-EOT
    set luci.main.mediaurlbase='/luci-static/argon'
    commit luci
EOT
exit 0
EOF
chmod +x "$ARGON_UCI_DEFAULTS/98-argon-default"

echo "===== [3/10] 编译修复（cmake / haproxy QUIC） ====="
grep -rl 'cmake_minimum_required(VERSION 3.31)' feeds/ | xargs -r sed -i 's/cmake_minimum_required(VERSION 3.31)/cmake_minimum_required(VERSION 3.25)/g' 2>/dev/null || true
HAPROXY_MAKEFILE="feeds/packages/net/haproxy/Makefile"
[ -f "$HAPROXY_MAKEFILE" ] && { sed -i 's/USE_QUIC=1/USE_QUIC=0/g' "$HAPROXY_MAKEFILE"; sed -i 's/ USE_QUIC_OPENSSL_COMPAT=1//g' "$HAPROXY_MAKEFILE"; }

echo "===== [4/10] 清理 ucode-mod / libcrypt-compat 依赖 ====="
find feeds/luci -type f -name Makefile -exec sed -i -E 's/[+]PACKAGE_ucode-mod-(log|socket):ucode-mod-(log|socket)//g; s/[+]ucode-mod-(log|socket)//g' {} \; 2>/dev/null || true
find feeds/luci -type f -name Makefile -exec sed -i 's/+libcrypt-compat//g' {} \; 2>/dev/null || true
find feeds/packages -type f -name Makefile -exec sed -i 's/+libcrypt-compat//g' {} \; 2>/dev/null || true

echo "===== [5/10] 修复 Kconfig 循环依赖（samba / baresip 基础处理） ====="
# baresip：R25.10.1 中可能在 telephony feed
for bp in feeds/packages/net/baresip/Makefile feeds/telephony/net/baresip/Makefile; do
    [ -f "$bp" ] && sed -i 's/+baresip-mod-avcodec//g' "$bp"
done
# samba 互依
for sf in feeds/luci/applications/luci-app-samba/Makefile feeds/luci/applications/luci-app-samba4/Makefile; do
    [ -f "$sf" ] && { sed -i 's/+luci-app-samba4//g' "$sf"; sed -i 's/+luci-app-samba//g' "$sf"; }
done

echo "===== [5.5/10] 强制修复 R25.10.1 新增循环依赖 ====="
# 1) OpenVPN DCO 自循环：删除所有 ENABLE_DCO 配置，防止 Kconfig 自依
sed -i '/OPENVPN_.*_ENABLE_DCO/d' .config
for v in openssl wolfssl mbedtls; do
    grep -q "^# CONFIG_OPENVPN_${v}_ENABLE_DCO is not set" .config || \
        echo "# CONFIG_OPENVPN_${v}_ENABLE_DCO is not set" >> .config
done

# 2) luci-proto-openvpnc 自依赖：禁用该包
sed -i '/CONFIG_PACKAGE_luci-proto-openvpnc/d' .config
sed -i '/CONFIG_DEFAULT_luci-proto-openvpnc/d' .config
./scripts/feeds uninstall luci-proto-openvpnc 2>/dev/null || true

# 3) baresip avcodec/avformat：双保险，再次清理 telephony 路径
for bp in feeds/telephony/net/baresip/Makefile feeds/packages/net/baresip/Makefile; do
    [ -f "$bp" ] && sed -i 's/+baresip-mod-avcodec//g' "$bp"
done

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

echo "===== [9/10] 清理 openvpn DCO 相关残留（预防 make defconfig 回写） ====="
# 如果 .config 中存在 openvpn 包，且带有 DCO 依赖的 kmod，一并清理
for ovpn in openvpn-openssl openvpn-wolfssl openvpn-mbedtls; do
    if grep -q "^CONFIG_PACKAGE_${ovpn}=y" .config; then
        sed -i "/CONFIG_PACKAGE_kmod-ovpn-dco/d" .config
        echo "# 注意：${ovpn} 已启用，但 DCO kmod 依赖已移除"
    fi
done

echo "===== [10/10] 修复阶段结束，进入诊断 ====="
set +e

# （诊断部分与你上一版相同，此处省略以保持简洁；实际使用时请保留你之前的 DIAG-1 ~ DIAG-10 代码）
echo "===== [DIAG] 关键循环依赖风险复查 ====="
echo "--- OpenVPN DCO 残留 ---"
grep -n "OPENVPN_.*_ENABLE_DCO" .config && echo "  [ERR] 仍有残留" || echo "  OK: 已清理"
echo "--- luci-proto-openvpnc 残留 ---"
grep -q "luci-proto-openvpnc" .config && echo "  [ERR] 仍存在" || echo "  OK: 已移除"
echo "--- baresip avcodec 依赖 ---"
grep -q "+baresip-mod-avcodec" feeds/telephony/net/baresip/Makefile 2>/dev/null && echo "  [WARN] telephony 中仍有残留" || echo "  OK"
echo "--- samba 互依 ---"
grep -q "luci-app-samba4" feeds/luci/applications/luci-app-samba/Makefile 2>/dev/null && echo "  [WARN] 仍有残留" || echo "  OK"

echo "===== diy-part2.sh 执行完毕 ====="
