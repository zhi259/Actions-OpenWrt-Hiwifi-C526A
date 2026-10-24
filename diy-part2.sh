#!/bin/bash
# diy-part2.sh —— 在 feeds update / install 之后、make 之前执行

# 修改默认管理地址和主机名（按你自己的喜好保留）
sed -i 's/192.168.1.1/192.168.5.1/g' package/base-files/files/bin/config_generate
#sed -i 's/OpenWrt/OpenRoute/g' package/base-files/files/bin/config_generate

# 默认主题切换为 argon
rm -rf feeds/kenzo/luci-theme-argon
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci-nginx/Makefile 2>/dev/null || true

# 核心修复：全局降级 CMake 版本要求，彻底解决 rpcd-mod-luci 报错
grep -rl 'cmake_minimum_required(VERSION 3.31)' feeds/ | xargs sed -i 's/cmake_minimum_required(VERSION 3.31)/cmake_minimum_required(VERSION 3.25)/g' 2>/dev/null || true