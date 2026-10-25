#!/bin/bash
# diy-part2.sh —— 在 feeds update / install 之后、make defconfig 之前执行
# 增强诊断版：10 个诊断模块，覆盖主题/ucode/uhttpd/passwall2/feeds/kconfig/编译产物

set -e

# =====================================================
# 修复阶段
# =====================================================
echo "===== [1/9] 基础配置修改（LAN IP） ====="
sed -i 's/192.168.1.1/192.168.5.1/g' package/base-files/files/bin/config_generate
echo "OK: LAN IP 已修改为 192.168.5.1"

echo "===== [2/9] 主题：默认启用 Argon 并预设暗色模式 ====="
for pkg in luci-theme-argon luci-app-argon-config; do
    if ! grep -q "^CONFIG_PACKAGE_${pkg}=y" .config; then
        echo "CONFIG_PACKAGE_${pkg}=y" >> .config
    fi
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
echo "OK: Argon 主题 + 暗色预设已就绪"

echo "===== [3/9] 编译修复（cmake / haproxy QUIC） ====="
grep -rl 'cmake_minimum_required(VERSION 3.31)' feeds/ \
  | xargs -r sed -i 's/cmake_minimum_required(VERSION 3.31)/cmake_minimum_required(VERSION 3.25)/g' 2>/dev/null || true

HAPROXY_MAKEFILE="feeds/packages/net/haproxy/Makefile"
if [ -f "$HAPROXY_MAKEFILE" ]; then
    sed -i 's/USE_QUIC=1/USE_QUIC=0/g' "$HAPROXY_MAKEFILE"
    sed -i 's/ USE_QUIC_OPENSSL_COMPAT=1//g' "$HAPROXY_MAKEFILE"
fi
echo "OK: cmake / haproxy 修复完成"

echo "===== [4/9] 清理 ucode-mod / libcrypt-compat 依赖 ====="
find feeds/luci -type f -name Makefile -exec sed -i -E 's/[+]PACKAGE_ucode-mod-(log|socket):ucode-mod-(log|socket)//g; s/[+]ucode-mod-(log|socket)//g' {} \; 2>/dev/null || true
find feeds/luci -type f -name Makefile -exec sed -i 's/+libcrypt-compat//g' {} \; 2>/dev/null || true
find feeds/packages -type f -name Makefile -exec sed -i 's/+libcrypt-compat//g' {} \; 2>/dev/null || true
echo "OK: ucode-mod / libcrypt-compat 依赖已清理"

echo "===== [5/9] 修复 Kconfig 循环依赖 ====="
BARESIP_MK="feeds/packages/net/baresip/Makefile"
[ -f "$BARESIP_MK" ] && sed -i 's/+baresip-mod-avcodec//g' "$BARESIP_MK"
SAMBA_APP_MK="feeds/luci/applications/luci-app-samba/Makefile"
SAMBA4_APP_MK="feeds/luci/applications/luci-app-samba4/Makefile"
[ -f "$SAMBA_APP_MK" ] && sed -i 's/+luci-app-samba4//g' "$SAMBA_APP_MK"
[ -f "$SAMBA4_APP_MK" ] && sed -i 's/+luci-app-samba//g' "$SAMBA4_APP_MK"
echo "OK: 循环依赖已处理"

echo "===== [6/9] PassWall2 修复 ====="
for pkg in xray-core v2ray-geodata sing-box chinadns-ng dns2socks hysteria \
           ipt2socks microsocks naiveproxy shadowsocks-rust shadowsocksr-libev \
           simple-obfs tcping v2ray-plugin xray-plugin geoview shadow-tls; do
    rm -rf "feeds/packages/net/$pkg" 2>/dev/null || true
done
rm -rf feeds/luci/applications/luci-app-passwall 2>/dev/null || true

PW2_MAKEFILE="feeds/luci/applications/luci-app-passwall2/Makefile"
if [ -f "$PW2_MAKEFILE" ]; then
    sed -i 's/+geoview//g' "$PW2_MAKEFILE"
    for dep in xray-core v2ray-geoip v2ray-geosite; do
        sed -i "s/+${dep}//g" "$PW2_MAKEFILE"
    done
fi

sed -i '/CONFIG_PACKAGE_luci-app-passwall2_Nftables_Transparent_Proxy=y/d' .config
grep -q "^CONFIG_PACKAGE_luci-app-passwall2_Iptables_Transparent_Proxy=y" .config || \
    echo "CONFIG_PACKAGE_luci-app-passwall2_Iptables_Transparent_Proxy=y" >> .config

./scripts/feeds install -f -a -p passwall_packages
./scripts/feeds install -f luci-app-passwall2
echo "OK: PassWall2 修复完成"

echo "===== [7/9] 强制移除 cpufreq / turboacc ====="
for pkg in luci-app-cpufreq luci-app-turboacc; do
    sed -i "/CONFIG_PACKAGE_${pkg}=/d" .config
    sed -i "/CONFIG_DEFAULT_${pkg}=/d" .config
    ./scripts/feeds uninstall "$pkg" 2>/dev/null || true
done
sed -i '/CONFIG_PACKAGE_cpufreq=/d' .config
echo "OK: cpufreq / turboacc 已移除"

echo "===== [8/9] 补全 uhttpd 与 ucode 关键组件 ====="
for pkg in uhttpd uhttpd-mod-ucode uhttpd-mod-lua \
           ucode libucode ucode-mod-fs ucode-mod-log ucode-mod-socket \
           ucode-mod-math ucode-mod-ubus ucode-mod-uci; do
    grep -q "^CONFIG_PACKAGE_${pkg}=y" .config || \
        echo "CONFIG_PACKAGE_${pkg}=y" >> .config
done
echo "OK: uhttpd/ucode 关键组件已补全"

echo "===== [9/9] 修复阶段结束，进入诊断 ====="

# =====================================================
# 诊断阶段（set +e，任何失败都不会中断）
# =====================================================
set +e

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║                 DIAG 增强诊断开始                      ║"
echo "╚══════════════════════════════════════════════════════╝"

# ---------- [DIAG-1] .config 关键项完整性 ----------
echo ""
echo "===== [DIAG-1] .config 关键项检查 ====="
check_cfg() {
    local key="$1"
    if grep -q "^${key}=y" .config; then
        echo "  [OK]   $key"
    else
        echo "  [MISS] $key  <-- 缺失!"
    fi
}
for k in CONFIG_PACKAGE_luci-theme-argon \
         CONFIG_PACKAGE_luci-app-argon-config \
         CONFIG_PACKAGE_uhttpd \
         CONFIG_PACKAGE_uhttpd-mod-ucode \
         CONFIG_PACKAGE_uhttpd-mod-lua \
         CONFIG_PACKAGE_ucode \
         CONFIG_PACKAGE_libucode \
         CONFIG_PACKAGE_ucode-mod-fs \
         CONFIG_PACKAGE_ucode-mod-log \
         CONFIG_PACKAGE_ucode-mod-socket \
         CONFIG_PACKAGE_ucode-mod-math \
         CONFIG_PACKAGE_ucode-mod-ubus \
         CONFIG_PACKAGE_ucode-mod-uci \
         CONFIG_PACKAGE_luci-app-passwall2 \
         CONFIG_PACKAGE_luci-app-passwall2_Iptables_Transparent_Proxy; do
    check_cfg "$k"
done

echo ""
echo "  反向检查（应为空）:"
for k in CONFIG_PACKAGE_luci-app-cpufreq CONFIG_PACKAGE_luci-app-turboacc \
         CONFIG_PACKAGE_luci-theme-bootstrap \
         CONFIG_PACKAGE_luci-app-passwall2_Nftables_Transparent_Proxy; do
    if grep -q "^${k}=y" .config; then
        echo "  [ERR!] $k 仍被启用!"
    else
        echo "  [OK]   $k 未启用"
    fi
done

# ---------- [DIAG-2] 主题依赖完整性 ----------
echo ""
echo "===== [DIAG-2] Argon 主题依赖检查 ====="
ARGON_MK="feeds/luci/themes/luci-theme-argon/Makefile"
if [ -f "$ARGON_MK" ]; then
    echo "  Makefile 存在"
    echo "  依赖声明:"
    grep -E "PKG_VERSION|PKG_RELEASE|LUCI_DEPENDS|LUCI_PKGARCH" "$ARGON_MK" | sed 's/^/    /'
    # 检查依赖是否存在
    deps=$(grep -oP 'LUCI_DEPENDS:=\+\K[^+]+' "$ARGON_MK" 2>/dev/null | tr ' ' '\n')
    for d in $deps; do
        if [ -d "feeds/luci/$d" ] || [ -d "package/feeds/luci/$d" ] || \
           [ -d "feeds/luci/libs/$d" ] || [ -d "feeds/luci/modules/$d" ]; then
            echo "    [OK]   依赖 $d 存在"
        else
            echo "    [WARN] 依赖 $d 目录未找到（可能来自 packages feed）"
        fi
    done
else
    echo "  [WARN] Argon Makefile 不存在"
fi
echo ""
echo "  UCI 默认脚本:"
for f in package/feeds/luci/luci-theme-argon/uci-defaults/98-argon-default \
         package/feeds/luci/luci-theme-argon/uci-defaults/99-argon-dark; do
    if [ -f "$f" ]; then
        echo "  [OK]   $f"
        head -3 "$f" | sed 's/^/    /'
    else
        echo "  [MISS] $f"
    fi
done

# ---------- [DIAG-3] ucode 源码与模块 ----------
echo ""
echo "===== [DIAG-3] ucode 源码与模块 ====="
UCODE_MK="package/utils/ucode/Makefile"
if [ -f "$UCODE_MK" ]; then
    echo "  ucode Makefile 存在"
    echo "  PKG_VERSION: $(grep -oP 'PKG_VERSION:=\K[^\s]+' $UCODE_MK | head -1)"
    echo "  子包定义:"
    grep -oP 'define Package/\Kucode-mod-[a-z]+' "$UCODE_MK" | sort -u | sed 's/^/    /'
    echo "  .config 中启用的 ucode-mod:"
    grep -oP '^CONFIG_PACKAGE_\Kucode-mod-[a-z]+(?==y)' .config | sed 's/^/    /'
else
    echo "  [ERROR] ucode Makefile 缺失!"
fi

# ---------- [DIAG-4] uhttpd 插件完整性 ----------
echo ""
echo "===== [DIAG-4] uhttpd 插件检查 ====="
UHTTPD_MK="package/network/services/uhttpd/Makefile"
if [ -f "$UHTTPD_MK" ]; then
    echo "  定义的子包:"
    grep -oP 'define Package/\K[u]httpd[a-z-]*' "$UHTTPD_MK" | sort -u | sed 's/^/    /'
    echo "  uhttpd-mod-ucode 在 Makefile 中:"
    grep -q "uhttpd-mod-ucode" "$UHTTPD_MK" && echo "    [OK] 存在" || echo "    [ERR] 未定义!"
else
    echo "  [ERROR] uhttpd Makefile 缺失!"
fi

# ---------- [DIAG-5] feeds 一致性 ----------
echo ""
echo "===== [DIAG-5] feeds 一致性检查 ====="
echo "  feed 目录:"
for d in feeds/packages feeds/luci feeds/routing feeds/telephony feeds/kenzo feeds/small feeds/passwall_packages; do
    [ -d "$d" ] && echo "    [OK]   $d" || echo "    [MISS] $d"
done
echo ""
echo "  feeds.conf.default 内容:"
sed 's/^/    /' feeds.conf.default 2>/dev/null || echo "    (不存在)"
echo ""
echo "  luci collection 当前主题引用:"
grep -o "luci-theme-[a-z]*" feeds/luci/collections/luci/Makefile 2>/dev/null | sort -u | sed 's/^/    /'

# ---------- [DIAG-6] 已知 WARNING 清单 ----------
echo ""
echo "===== [DIAG-6] 已知依赖缺失 WARNING 清单 ====="
echo "  以下警告来自 feeds 声明但 Makefile 中不存在的依赖："
echo "  （这些不会导致编译失败，但会刷屏日志）"
warn_count=0
for mk in $(find feeds/ -name Makefile 2>/dev/null); do
    grep -l "kmod-xdp-sockets-diag\|libcrypt-compat\|kmod-fs-cifsd\|libmpfr\|cpufreq\|kmod-qca-nss-drv-igs\|unetd\|unet-cli\|quectel-cm\|libopenssl-legacy" "$mk" 2>/dev/null
done | head -30 | while read f; do
    echo "    $f"
done
echo "  （如仍出现大量 libcrypt-compat，检查 [4/9] 步骤是否生效）"

# ---------- [DIAG-7] PassWall2 依赖树 ----------
echo ""
echo "===== [DIAG-7] PassWall2 依赖树 ====="
if [ -f "$PW2_MAKEFILE" ]; then
    echo "  当前 LUCI_DEPENDS:"
    grep -E "LUCI_DEPENDS" "$PW2_MAKEFILE" | sed 's/^/    /'
    echo ""
    echo "  透明代理相关:"
    grep -E "Iptables_Transparent_Proxy|Nftables_Transparent_Proxy" "$PW2_MAKEFILE" | sed 's/^/    /'
else
    echo "  [WARN] PassWall2 Makefile 不存在"
fi

# ---------- [DIAG-8] Kconfig 递归依赖扫描 ----------
echo ""
echo "===== [DIAG-8] Kconfig 递归依赖风险扫描 ====="
echo "  检查常见的递归依赖模式（samba / baresip / luci-app-xxx 互依）:"
FOUND_RECURSION=0
# samba 互依
if [ -f "$SAMBA_APP_MK" ] && [ -f "$SAMBA4_APP_MK" ]; then
    if grep -q "luci-app-samba4" "$SAMBA_APP_MK" && grep -q "luci-app-samba" "$SAMBA4_APP_MK"; then
        echo "    [ERR] samba 循环依赖仍存在!"
        FOUND_RECURSION=1
    else
        echo "    [OK] samba 循环依赖已消除"
    fi
fi
# baresip
if [ -f "$BARESIP_MK" ]; then
    if grep -q "baresip-mod-avcodec" "$BARESIP_MK" && \
       grep -q "baresip-mod-avformat.*avcodec\|avcodec.*avformat" "$BARESIP_MK"; then
        echo "    [WARN] baresip 可能存在 avcodec/avformat 互依"
    else
        echo "    [OK] baresip 循环依赖已消除"
    fi
fi
[ $FOUND_RECURSION -eq 0 ] && echo "    [OK] 未发现已知递归依赖"

# ---------- [DIAG-9] 关键包的 ipk 产物（编译后才有） ----------
echo ""
echo "===== [DIAG-9] 编译产物检查（仅在编译完成后有效） ====="
IPK_DIR="bin/packages/arm_cortex-a7_neon-vfpv4"
if [ -d "$IPK_DIR" ]; then
    echo "  查找关键 ipk:"
    for p in uhttpd-mod-ucode ucode-mod-fs ucode-mod-log ucode-mod-socket \
             luci-theme-argon luci-app-argon-config luci-app-passwall2; do
        found=$(find "$IPK_DIR" -name "${p}_*.ipk" 2>/dev/null | head -1)
        if [ -n "$found" ]; then
            echo "    [OK]   $p  ->  $(basename $found)"
        else
            echo "    [MISS] $p  (第一次编译前正常)"
        fi
    done
else
    echo "  $IPK_DIR 不存在（尚未编译，正常）"
fi

# ---------- [DIAG-10] 最终汇总 ----------
echo ""
echo "===== [DIAG-10] 最终汇总 ====="
err=0
miss=0
# .config 关键缺失
for k in CONFIG_PACKAGE_uhttpd-mod-ucode CONFIG_PACKAGE_ucode-mod-log \
         CONFIG_PACKAGE_ucode-mod-socket CONFIG_PACKAGE_luci-theme-argon; do
    grep -q "^${k}=y" .config || { miss=$((miss+1)); echo "  [MISS] $k"; }
done
# 反向检查
for k in CONFIG_PACKAGE_luci-app-cpufreq CONFIG_PACKAGE_luci-app-turboacc \
         CONFIG_PACKAGE_luci-theme-bootstrap; do
    grep -q "^${k}=y" .config && { err=$((err+1)); echo "  [ERR]  $k 仍启用"; }
done
# 脚本文件检查
[ -f package/feeds/luci/luci-theme-argon/uci-defaults/99-argon-dark ] || { miss=$((miss+1)); echo "  [MISS] Argon 暗色 UCI 脚本"; }
[ -f package/feeds/luci/luci-theme-argon/uci-defaults/98-argon-default ] || { miss=$((miss+1)); echo "  [MISS] Argon 默认主题 UCI 脚本"; }

echo ""
if [ $err -eq 0 ] && [ $miss -eq 0 ]; then
    echo "  ✅ 全部检查通过，可以进入 make defconfig / make"
else
    echo "  ⚠️  发现 $err 个错误，$miss 个缺失，请检查上方 [DIAG-1] ~ [DIAG-9]"
fi

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║                 DIAG 诊断结束                          ║"
echo "╚══════════════════════════════════════════════════════╝"
echo "===== diy-part2.sh 执行完毕 ====="
