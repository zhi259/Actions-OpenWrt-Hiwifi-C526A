#!/bin/bash
set -e

echo "===== [1/5] 基础配置（LAN IP） ====="
sed -i 's/192.168.1.1/192.168.5.1/g' package/base-files/files/bin/config_generate

echo "===== [2/5] 设备锁定（强制 hiwifi_c526a） ====="
sed -i '/CONFIG_TARGET_MULTI_PROFILE[= ]/d' .config
sed -i '/CONFIG_TARGET_PER_DEVICE_ROOTFS[= ]/d' .config
sed -i '/CONFIG_TARGET_DEVICE_ipq40xx_DEVICE_/d' .config
sed -i '/CONFIG_TARGET_DEVICE_PACKAGES_ipq40xx_DEVICE_/d' .config
sed -i '/CONFIG_TARGET_ipq40xx_DEVICE_/d' .config
sed -i '/CONFIG_TARGET_PROFILE=/d' .config

cat >> .config <<'EOF'
CONFIG_TARGET_PROFILE="DEVICE_hiwifi_c526a"
CONFIG_TARGET_MULTI_PROFILE=y
CONFIG_TARGET_PER_DEVICE_ROOTFS=y
CONFIG_TARGET_DEVICE_ipq40xx_DEVICE_hiwifi_c526a=y
CONFIG_TARGET_ipq40xx_DEVICE_hiwifi_c526a=y
EOF

grep -q '^CONFIG_TARGET_PROFILE="DEVICE_hiwifi_c526a"' .config || { echo "[FATAL] PROFILE 锁定失败"; exit 1; }
echo "  OK: PROFILE 已锁定"

echo "===== [rpcd-mod-luci] 修复 CMake 版本要求过高 ====="
RPCD_LUCI_CMAKE="feeds/luci/libs/rpcd-mod-luci/src/CMakeLists.txt"
if [ -f "$RPCD_LUCI_CMAKE" ]; then
    # 将 3.31 降回 3.25（与 LEDE 20230609 内置 cmake 版本匹配）
    sed -i 's/cmake_minimum_required(VERSION 3.31)/cmake_minimum_required(VERSION 3.25)/' "$RPCD_LUCI_CMAKE"
    # 同时兜底处理 rrdns（同一提交也改了这个包）
    RPCD_RRDNS_CMAKE="feeds/luci/libs/rpcd-mod-rrdns/src/CMakeLists.txt"
    [ -f "$RPCD_RRDNS_CMAKE" ] && sed -i 's/cmake_minimum_required(VERSION 3.31)/cmake_minimum_required(VERSION 3.25)/' "$RPCD_RRDNS_CMAKE"
    echo "  OK: rpcd-mod-luci/rrdns 的 CMake 最低版本已降回 3.25"
else
    echo "  [WARN] 未找到 $RPCD_LUCI_CMAKE，跳过"
fi

echo "===== [3/5] Web 核心与主题 ====="
# 强制清理 bootstrap
sed -i '/^CONFIG_PACKAGE_luci-theme-bootstrap/d' .config
sed -i '/^CONFIG_DEFAULT_luci-theme-bootstrap/d' .config

# 确保 Argon 和 uhttpd 核心存在
for pkg in luci-theme-argon luci-app-argon-config uhttpd uhttpd-mod-ucode ucode libucode ucode-mod-log ucode-mod-socket; do
    grep -q "^CONFIG_PACKAGE_${pkg}=y" .config || echo "CONFIG_PACKAGE_${pkg}=y" >> .config
done

# Argon 暗色 UCI 预设
ARGON_DIR="package/feeds/luci/luci-theme-argon/uci-defaults"
mkdir -p "$ARGON_DIR"
cat > "$ARGON_DIR/99-argon-dark" <<'EOF'
#!/bin/sh
uci -q batch <<-EOT
    set argon.@global[0].mode='dark'
    commit argon
EOT
exit 0
EOF
chmod +x "$ARGON_DIR/99-argon-dark"

echo "===== [4/5] IPv6 / DDNS / FakeHTTP 依赖检查 ====="
# IPv6 与 DDNS 核心包（如果 .config 中没有，这里补充）
for pkg in luci-proto-ipv6 odhcp6c odhcpd-ipv6only kmod-ipv6 ddns-scripts luci-app-ddns ddns-scripts_aliyun ddns-scripts_dnspod; do
    grep -q "^CONFIG_PACKAGE_${pkg}=y" .config || echo "CONFIG_PACKAGE_${pkg}=y" >> .config
done

# FakeHTTP / FakeSIP 内核依赖
for pkg in kmod-nfnetlink-queue kmod-ipt-nfqueue iptables-mod-nfqueue; do
    grep -q "^CONFIG_PACKAGE_${pkg}=y" .config || echo "CONFIG_PACKAGE_${pkg}=y" >> .config
done

# 检查 FakeHTTP/FakeSIP 是否在 feed 中
if [ -d "feeds/packages/net/fakehttp" ] || [ -d "feeds/kenzo/fakehttp" ]; then
    echo "  OK: FakeHTTP 源码已存在于 feed 中"
    grep -q "^CONFIG_PACKAGE_fakehttp=y" .config || echo "CONFIG_PACKAGE_fakehttp=y" >> .config
else
    echo "  [WARN] 当前 feed 中未找到 fakehttp 包。"
    echo "         FakeHTTP 是独立工具，通常需要手动下载 musl 静态编译版本，"
    echo "         或在 diy-part1.sh 中启用 kenzo 源。本次编译将不包含 fakehttp 二进制。"
fi

if [ -d "feeds/packages/net/fakesip" ] || [ -d "feeds/kenzo/fakesip" ]; then
    echo "  OK: FakeSIP 源码已存在于 feed 中"
    grep -q "^CONFIG_PACKAGE_fakesip=y" .config || echo "CONFIG_PACKAGE_fakesip=y" >> .config
else
    echo "  [WARN] 当前 feed 中未找到 fakesip 包。"
fi

echo "===== [5/5] 最终诊断 ====="
DIAG_FAIL=0
grep -q '^CONFIG_TARGET_PROFILE="DEVICE_hiwifi_c526a"' .config || { echo "[ERR] PROFILE 错误"; DIAG_FAIL=1; }
grep -q '^CONFIG_PACKAGE_uhttpd-mod-ucode=y' .config || { echo "[ERR] uhttpd-mod-ucode 缺失"; DIAG_FAIL=1; }
grep -q '^CONFIG_PACKAGE_luci-theme-argon=y' .config || { echo "[ERR] Argon 缺失"; DIAG_FAIL=1; }
grep -q '^CONFIG_PACKAGE_luci-proto-ipv6=y' .config || { echo "[ERR] IPv6 协议缺失"; DIAG_FAIL=1; }
grep -q '^CONFIG_PACKAGE_ddns-scripts=y' .config || { echo "[ERR] DDNS 缺失"; DIAG_FAIL=1; }

if [ "$DIAG_FAIL" -eq 1 ]; then
    echo "❌ 诊断失败，终止编译"
    exit 1
fi
echo "✅ 诊断通过"
echo "===== diy-part2.sh 完成 ====="
