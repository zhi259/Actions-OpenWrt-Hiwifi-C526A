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

echo "===== [4.5/5] 修复 ucode Makefile，添加 log 和 socket 模块 ====="
UCODE_MAKEFILE="package/utils/ucode/Makefile"
if [ ! -f "$UCODE_MAKEFILE" ]; then
    echo "错误: 未找到 $UCODE_MAKEFILE，无法修复 ucode 模块"
    exit 1
fi

python3 - "$UCODE_MAKEFILE" <<'PYEOF'
import sys

path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

anchor = '$(eval $(call BuildPackage,libucode))'
if anchor not in content:
    print("错误: 在 ucode Makefile 中未找到锚点，无法插入")
    sys.exit(1)

insert_lines = []

# 检查是否已通过 UcodeModule 宏定义了 log 模块
if not any('log' in line and 'UcodeModule' in content[max(0, content.find(line)-50):content.find(line)+len(line)] for line in content.splitlines()):
    # 使用与官方一致的格式：模块名在下一行
    log_def = """$(eval $(call UcodeModule, \\
\tlog, LOG_SUPPORT, , \\
))
"""
    insert_lines.append(log_def)

# 检查 socket 模块
if not any('socket' in line and 'UcodeModule' in content[max(0, content.find(line)-50):content.find(line)+len(line)] for line in content.splitlines()):
    socket_def = """$(eval $(call UcodeModule, \\
\tsocket, SOCKET_SUPPORT, , \\
))
"""
    insert_lines.append(socket_def)

if insert_lines:
    new_block = ''.join(insert_lines) + '\n' + anchor
    content = content.replace(anchor, new_block, 1)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"已向 {path} 插入 log / socket 模块定义")
else:
    print(f"{path} 中 log / socket 模块定义已存在，无需插入")
PYEOF

echo "===== [5/5] 补全 .config 缺失依赖 ====="

# 3. 诊断：确认 ucode 核心源码存在（这是 ucode-mod-* 能被编译的前提）
if [ -f package/utils/ucode/Makefile ]; then
    echo "OK: package/utils/ucode/Makefile 存在，ucode-mod-* 可被编译"
else
    echo "WARNING: package/utils/ucode/Makefile 不存在！ucode-mod-* 将无法编译"
fi

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
echo "===== [诊断] 结束 ====="

echo "===== diy-part2.sh 执行完毕 ====="
