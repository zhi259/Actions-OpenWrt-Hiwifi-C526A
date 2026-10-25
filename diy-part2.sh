#!/bin/bash
# diy-part2.sh —— 在 feeds update / install 之后、make defconfig 之前执行

set -e

# =====================================================
# 修复阶段
# =====================================================
echo "===== [1/10] 基础配置修改（LAN IP） ====="
sed -i 's/192.168.1.1/192.168.5.1/g' package/base-files/files/bin/config_generate

echo "===== [设备支持] 从 LEDE R23.8.23 恢复 hiwifi_c526a ====="
SRC_BASE="https://raw.githubusercontent.com/coolsnowwolf/lede/20220401"

# 1) 下载 DTS 文件
DTS_DST="target/linux/ipq40xx/files/arch/arm/boot/dts/qcom-ipq4019-c526a.dts"
mkdir -p "$(dirname "$DTS_DST")"
if curl -sfL "$SRC_BASE/$DTS_DST" -o "$DTS_DST"; then
    echo "  [OK] DTS 下载成功: $DTS_DST"
else
    echo "  [ERROR] DTS 下载失败，检查源地址 $SRC_BASE/$DTS_DST"
    exit 1
fi

# 2) 下载 Wi-Fi 校准数据（二进制，必须单独下载）
CAL_DST="package/firmware/ipq-wifi/board-hiwifi_c526a.qca4019"
mkdir -p "$(dirname "$CAL_DST")"
if curl -sfL "$SRC_BASE/$CAL_DST" -o "$CAL_DST"; then
    echo "  [OK] 校准数据下载成功: $CAL_DST ($(stat -c%s "$CAL_DST") bytes)"
else
    echo "  [ERROR] 校准数据下载失败，检查源地址 $SRC_BASE/$CAL_DST"
    exit 1
fi

# 3) 修改 ipq-wifi Makefile，注册 hiwifi_c526a
IPQ_WIFI_MK="package/firmware/ipq-wifi/Makefile"
if [ -f "$IPQ_WIFI_MK" ]; then
    # 在 ALLWIFIBOARDS 列表里加入 hiwifi_c526a
    grep -q "hiwifi_c526a" "$IPQ_WIFI_MK" || \
        sed -i '/^ALLWIFIBOARDS:=/a\  hiwifi_c526a \\' "$IPQ_WIFI_MK"
    # 在 eval 调用区加入 generate-ipq-wifi-package
    grep -q "generate-ipq-wifi-package,hiwifi_c526a" "$IPQ_WIFI_MK" || \
        sed -i '/edgecore_oap100,Edgecore OAP100/a\$(eval $(call generate-ipq-wifi-package,hiwifi_c526a,HiWiFi C526A))' "$IPQ_WIFI_MK"
    echo "  [OK] ipq-wifi Makefile 已更新"
fi

# 4) 在 generic.mk 中追加 hiwifi_c526a 设备定义
IMAGE_MK="target/linux/ipq40xx/image/generic.mk"
if [ -f "$IMAGE_MK" ] && ! grep -q "Device/hiwifi_c526a" "$IMAGE_MK"; then
    cat >> "$IMAGE_MK" <<'EOF'

define Device/hiwifi_c526a
	$(Device/dsa-migration)
	DEVICE_VENDOR := HiWiFi
	DEVICE_MODEL := C526A
	DEVICE_DTS := qcom-ipq4019-c526a
	DEVICE_PACKAGES := ipq-wifi-hiwifi_c526a kmod-ath10k-ct ath10k-firmware-qca4019-ct \
		kmod-mt7615e kmod-mt7615-firmware
	IMAGE_SIZE := 128m
	KERNEL_SIZE := 4096k
	IMAGES := sysupgrade.bin factory.ubi
	IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
	IMAGE/factory.ubi := append-ubi
endef
TARGET_DEVICES += hiwifi_c526a
EOF
    echo "  [OK] generic.mk 已追加 hiwifi_c526a"
fi

# 5) 在 DTS Makefile patch 中注册 DTB（当前内核 5.4 对应 patches-5.4）
DTB_PATCH_DIR="target/linux/ipq40xx/patches-5.4"
if [ -d "$DTB_PATCH_DIR" ] && [ ! -f "$DTB_PATCH_DIR/903-arm-boot-add-dts-files.patch" ]; then
    cat > "$DTB_PATCH_DIR/903-arm-boot-add-dts-files.patch" <<'EOF'
--- a/arch/arm/boot/dts/Makefile
+++ b/arch/arm/boot/dts/Makefile
@@ -750,6 +750,7 @@ dtb-$(CONFIG_ARCH_QCOM) += \
 	qcom-ipq4019-ap.dk04.1-c3.dtb \
 	qcom-ipq4019-ap.dk07.1-c1.dtb \
 	qcom-ipq4019-ap.dk07.1-c2.dtb \
+	qcom-ipq4019-c526a.dtb \
 	qcom-ipq4019-habanero-dvk.dtb \
 	qcom-ipq4019-wifi.dtb \
 	qcom-ipq4019-ap.dk01.1-c1.dtb \
EOF
    echo "  [OK] DTB Makefile patch 已生成"
fi

echo "===== [设备锁定] 强制为 hiwifi_c526a 单设备构建 ====="
# 使用 single-profile 模式（最稳定）
sed -i '/CONFIG_TARGET_MULTI_PROFILE=y/d' .config
sed -i '/CONFIG_TARGET_PER_DEVICE_ROOTFS=y/d' .config
sed -i '/CONFIG_TARGET_DEVICE_ipq40xx_DEVICE_/d' .config
sed -i '/CONFIG_TARGET_DEVICE_PACKAGES_ipq40xx_DEVICE_/d' .config
sed -i '/CONFIG_TARGET_ipq40xx_DEVICE_/d' .config
# 确保 PROFILE 指向 hiwifi_c526a
sed -i '/CONFIG_TARGET_PROFILE=/d' .config
echo 'CONFIG_TARGET_PROFILE="DEVICE_hiwifi_c526a"' >> .config

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


echo "===== [设备支持诊断] 检查 hiwifi_c526a 是否存在于当前源码 ====="

# 1. 检查设备树文件
DTS_FILE="target/linux/ipq40xx/files/arch/arm/boot/dts/qcom-ipq4019-c526a.dts"
if [ -f "$DTS_FILE" ]; then
    echo "  [OK] DTS 文件存在: $DTS_FILE"
else
    echo "  [ERROR] DTS 文件缺失！设备支持可能已被移除。"
fi

# 2. 检查镜像 Makefile 中的设备定义
IMAGE_MK="target/linux/ipq40xx/image/generic.mk"
if [ -f "$IMAGE_MK" ]; then
    if grep -q "hiwifi_c526a" "$IMAGE_MK"; then
        echo "  [OK] 镜像 Makefile 中包含 hiwifi_c526a 定义"
        grep -n "hiwifi_c526a" "$IMAGE_MK" | head -5
    else
        echo "  [ERROR] 镜像 Makefile 中未找到 hiwifi_c526a！设备可能已被移除。"
    fi
else
    echo "  [ERROR] 镜像 Makefile 不存在: $IMAGE_MK"
fi

# 3. 检查内核配置
KCONFIG_FILE="target/linux/ipq40xx/config-5.4"
if [ -f "$KCONFIG_FILE" ]; then
    if grep -q "HIWIFI_C526A" "$KCONFIG_FILE"; then
        echo "  [OK] 内核配置中包含 HIWIFI_C526A"
    else
        echo "  [WARN] 内核配置中未显式包含 HIWIFI_C526A（不一定代表不支持）"
    fi
fi

# =====================================================
# 阶段一诊断：静态文件检查（diy-part2.sh 末尾）
# =====================================================
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║   DIAG-STATIC：设备支持静态文件检查                    ║"
echo "╚══════════════════════════════════════════════════════╝"

DIAG_FAIL=0

# ---------- DIAG-S1：DTS 文件 ----------
echo ""
echo "[DIAG-S1] DTS 设备树文件"
DTS_FILE="target/linux/ipq40xx/files/arch/arm/boot/dts/qcom-ipq4019-c526a.dts"
if [ -f "$DTS_FILE" ]; then
    size=$(stat -c%s "$DTS_FILE")
    if [ "$size" -gt 1000 ]; then
        echo "  [OK] 存在，大小 ${size} bytes"
    else
        echo "  [ERR] 存在但大小异常（${size} bytes，可能下载了 404 页面）"
        head -3 "$DTS_FILE" | sed 's/^/         /'
        DIAG_FAIL=1
    fi
else
    echo "  [ERR] 缺失: $DTS_FILE"
    DIAG_FAIL=1
fi

# ---------- DIAG-S2：校准数据（二进制） ----------
echo ""
echo "[DIAG-S2] Wi-Fi 校准数据 (qca4019)"
CAL_FILE="package/firmware/ipq-wifi/board-hiwifi_c526a.qca4019"
if [ -f "$CAL_FILE" ]; then
    size=$(stat -c%s "$CAL_FILE")
    if [ "$size" -gt 10000 ]; then
        echo "  [OK] 存在，大小 ${size} bytes"
    else
        echo "  [ERR] 存在但大小异常（${size} bytes，正常应 >10000）"
        DIAG_FAIL=1
    fi
else
    echo "  [ERR] 缺失: $CAL_FILE"
    DIAG_FAIL=1
fi

# ---------- DIAG-S3：generic.mk 设备定义 ----------
echo ""
echo "[DIAG-S3] generic.mk 中的 hiwifi_c526a 设备定义"
IMAGE_MK="target/linux/ipq40xx/image/generic.mk"
if [ -f "$IMAGE_MK" ]; then
    if grep -q "Device/hiwifi_c526a" "$IMAGE_MK"; then
        echo "  [OK] Device/hiwifi_c526a 已定义"
        # 检查关键字段是否齐全
        block=$(awk '/define Device\/hiwifi_c526a/,/endef/' "$IMAGE_MK")
        for field in "DEVICE_DTS" "DEVICE_PACKAGES" "IMAGE_SIZE" "IMAGES"; do
            echo "$block" | grep -q "$field" && echo "         OK: $field" || { echo "         [ERR] 缺少 $field"; DIAG_FAIL=1; }
        done
        # 检查是否已注册到 TARGET_DEVICES
        grep -q "TARGET_DEVICES += hiwifi_c526a" "$IMAGE_MK" && \
            echo "         OK: 已加入 TARGET_DEVICES" || { echo "         [ERR] 未加入 TARGET_DEVICES"; DIAG_FAIL=1; }
    else
        echo "  [ERR] generic.mk 中不存在 Device/hiwifi_c526a"
        DIAG_FAIL=1
    fi
else
    echo "  [ERR] generic.mk 不存在"
    DIAG_FAIL=1
fi

# ---------- DIAG-S4：ipq-wifi Makefile 注册 ----------
echo ""
echo "[DIAG-S4] ipq-wifi Makefile 注册"
IPQ_WIFI_MK="package/firmware/ipq-wifi/Makefile"
if [ -f "$IPQ_WIFI_MK" ]; then
    grep -q "hiwifi_c526a" "$IPQ_WIFI_MK" && echo "  [OK] hiwifi_c526a 已注册" || { echo "  [ERR] ipq-wifi 未注册 hiwifi_c526a"; DIAG_FAIL=1; }
else
    echo "  [ERR] ipq-wifi Makefile 不存在"
    DIAG_FAIL=1
fi

# ---------- DIAG-S5：DTB patch（针对内核 5.4） ----------
echo ""
echo "[DIAG-S5] DTB Makefile patch（patches-5.4）"
DTB_PATCH="target/linux/ipq40xx/patches-5.4/903-arm-boot-add-dts-files.patch"
if [ -f "$DTB_PATCH" ]; then
    grep -q "qcom-ipq4019-c526a.dtb" "$DTB_PATCH" && echo "  [OK] patch 已包含 c526a.dtb" || { echo "  [ERR] patch 不含 c526a.dtb"; DIAG_FAIL=1; }
else
    echo "  [WARN] patch 文件不存在（如果 DTS 已在 Makefile 中可忽略）"
fi

# ---------- DIAG-S6：.config 设备选择格式 ----------
echo ""
echo "[DIAG-S6] .config 中的设备选择"
if grep -q '^CONFIG_TARGET_PROFILE="DEVICE_hiwifi_c526a"' .config; then
    echo "  [OK] CONFIG_TARGET_PROFILE 已指向 DEVICE_hiwifi_c526a"
else
    echo "  [ERR] CONFIG_TARGET_PROFILE 未指向 hiwifi_c526a"
    echo "         当前值: $(grep '^CONFIG_TARGET_PROFILE=' .config || echo '未设置')"
    DIAG_FAIL=1
fi
if grep -q "CONFIG_TARGET_ipq40xx_DEVICE_hiwifi_c526a=y" .config; then
    echo "  [OK] CONFIG_TARGET_ipq40xx_DEVICE_hiwifi_c526a=y"
else
    echo "  [WARN] 未显式启用 CONFIG_TARGET_ipq40xx_DEVICE_hiwifi_c526a（部分版本用 PROFILE 控制即可）"
fi

# ---------- DIAG-S7：之前修复项复查 ----------
echo ""
echo "[DIAG-S7] 之前修复项复查"
check_cfg_y() {
    grep -q "^$1=y" .config && echo "  [OK] $1" || { echo "  [ERR] 缺少 $1"; DIAG_FAIL=1; }
}
check_cfg_n() {
    grep -q "^$1=y" .config && { echo "  [ERR] $1 不应启用"; DIAG_FAIL=1; } || echo "  [OK] $1 已禁用"
}
check_cfg_y "CONFIG_PACKAGE_uhttpd-mod-ucode"
check_cfg_y "CONFIG_PACKAGE_ucode-mod-log"
check_cfg_y "CONFIG_PACKAGE_ucode-mod-socket"
check_cfg_y "CONFIG_PACKAGE_luci-theme-argon"
check_cfg_n "CONFIG_PACKAGE_luci-app-cpufreq"
check_cfg_n "CONFIG_PACKAGE_luci-app-turboacc"
check_cfg_n "CONFIG_PACKAGE_luci-theme-bootstrap"

# ---------- 结果汇总 ----------
echo ""
if [ "$DIAG_FAIL" -eq 1 ]; then
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║   ❌ 阶段一诊断失败，终止编译                          ║"
    echo "╚══════════════════════════════════════════════════════╝"
    exit 1
else
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║   ✅ 阶段一诊断通过                                    ║"
    echo "╚══════════════════════════════════════════════════════╝"
fi

echo "===== diy-part2.sh 执行完毕 ====="
