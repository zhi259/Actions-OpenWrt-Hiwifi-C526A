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

echo "===== [5/5] 补全 .config 缺失依赖 ====="
# 1. 确保 ucode 核心包及其子模块在 .config 中被选中
#    ucode-mod-* 是 package/utils/ucode 核心包的子模块，不在任何 feed 里，
#    通过 feeds install 无法安装，只能在 .config 中选中让 make 编译出来。
for cfg in \
    CONFIG_PACKAGE_ucode \
    CONFIG_PACKAGE_libucode \
    CONFIG_PACKAGE_ucode-mod-log \
    CONFIG_PACKAGE_ucode-mod-socket \
    CONFIG_PACKAGE_ucode-mod-math \
    CONFIG_PACKAGE_ucode-mod-ubus \
    CONFIG_PACKAGE_ucode-mod-uci; do
    grep -q "^${cfg}=y" .config || echo "${cfg}=y" >> .config
done

# 2. 移除 cpufreq 残留配置（luci-app-cpufreq 已从 .config 移除）
sed -i '/^CONFIG_PACKAGE_cpufreq=/d' .config 2>/dev/null || true

# 3. 诊断：确认 ucode 核心源码存在（这是 ucode-mod-* 能被编译的前提）
if [ -f package/utils/ucode/Makefile ]; then
    echo "OK: package/utils/ucode/Makefile 存在，ucode-mod-* 可被编译"
else
    echo "WARNING: package/utils/ucode/Makefile 不存在！ucode-mod-* 将无法编译"
fi
# （可选）开启内核 CPU 调频框架，不影响构建
for opt in \
  CONFIG_CPU_FREQ=y \
  CONFIG_CPU_FREQ_GOV_ONDEMAND=y \
  CONFIG_CPU_FREQ_DEFAULT_GOV_ONDEMAND=y; do
  grep -q "^${opt}$" target/linux/ipq40xx/config-5.4 2>/dev/null \
    || echo "${opt}" >> target/linux/ipq40xx/config-5.4
done

echo "===== [诊断] 关键源码与 feed 链接检查 ====="

# ucode 核心源码（ucode-mod-* 的父包）
if [ -f package/utils/ucode/Makefile ]; then
    echo "OK: package/utils/ucode/Makefile 存在"
else
    echo "WARNING: package/utils/ucode/Makefile 缺失，ucode-mod-* 无法编译"
fi

# 检查 ucode Makefile 是否定义了 log/socket 子模块
for mod in log socket; do
    if grep -q "UcodeModule, \\\\" package/utils/ucode/Makefile 2>/dev/null; then
        :
    fi
done
grep -q 'UcodeModule,.*log' package/utils/ucode/Makefile 2>/dev/null \
    && echo "OK: ucode Makefile 定义了 log 模块" \
    || echo "WARNING: ucode Makefile 未找到 log 模块定义"

grep -q 'UcodeModule,.*socket' package/utils/ucode/Makefile 2>/dev/null \
    && echo "OK: ucode Makefile 定义了 socket 模块" \
    || echo "WARNING: ucode Makefile 未找到 socket 模块定义"

# 关键 feed 目录
for d in feeds/passwall_packages feeds/luci feeds/packages package/feeds/passwall_packages; do
    [ -e "$d" ] && echo "OK: $d 存在" || echo "WARNING: $d 缺失"
done

# .config 中关键配置是否真的写入
for cfg in CONFIG_PACKAGE_ucode CONFIG_PACKAGE_libucode \
           CONFIG_PACKAGE_ucode-mod-log CONFIG_PACKAGE_ucode-mod-socket; do
    grep -q "^${cfg}=y" .config \
        && echo "OK: .config 包含 ${cfg}=y" \
        || echo "WARNING: .config 缺少 ${cfg}=y"
done

# 残留 cpufreq 配置检查（应不存在）
if grep -q '^CONFIG_PACKAGE_cpufreq=' .config 2>/dev/null; then
    echo "WARNING: .config 仍有 CONFIG_PACKAGE_cpufreq，建议删除"
else
    echo "OK: .config 无 CONFIG_PACKAGE_cpufreq 残留"
fi

echo "===== [诊断] 结束 ====="

echo "===== diy-part2.sh 执行完毕 ====="
