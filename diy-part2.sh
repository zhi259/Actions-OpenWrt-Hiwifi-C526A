#!/bin/bash
# diy-part2.sh —— 在 feeds update / install 之后、make 之前执行

# 管理地址（按需保留或改掉）
sed -i 's/192.168.1.1/192.168.5.1/g' package/base-files/files/bin/config_generate

# 主机名（按需保留或改掉）
#sed -i 's/OpenWrt/OpenRoute/g' package/base-files/files/bin/config_generate

# 默认主题切换为 argon
rm -rf feeds/kenzo/luci-theme-argon
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci-nginx/Makefile 2>/dev/null || true

# 降级 rpcd-mod-luci 的 CMake 版本要求，兼容 Actions 环境
sed -i 's/cmake_minimum_required(VERSION 3.31)/cmake_minimum_required(VERSION 3.25)/' feeds/luci/libs/rpcd-mod-luci/CMakeLists.txt

# PassWall2 编译时如果 geoview 冲突，取消下面这行注释
# rm -rf feeds/packages/net/geoview
