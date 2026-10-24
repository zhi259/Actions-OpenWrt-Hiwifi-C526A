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

# 修改 rpcd-mod-luci 的 CMake 要求，自动定位文件
RPCD_MOD_LUCI_CMAKE=$(find feeds -path '*/rpcd-mod-luci/CMakeLists.txt' 2>/dev/null | head -n 1)
if [ -n "$RPCD_MOD_LUCI_CMAKE" ]; then
    sed -i 's/cmake_minimum_required(VERSION 3.31)/cmake_minimum_required(VERSION 3.25)/' "$RPCD_MOD_LUCI_CMAKE"
fi

# PassWall2 编译时如果 geoview 冲突，取消下面这行注释
# rm -rf feeds/packages/net/geoview
