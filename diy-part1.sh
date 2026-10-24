#!/bin/bash
# diy-part1.sh —— 在 feeds update 之前执行

# PassWall2 官方源（放最前面，优先级最高）
echo 'src-git passwall2 https://github.com/Openwrt-Passwall/openwrt-passwall2.git;main' >>feeds.conf.default
echo 'src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git;main' >>feeds.conf.default

# kenzo 源，提供其他 LuCI 应用和依赖
echo 'src-git kenzo https://github.com/kenzok8/openwrt-packages' >>feeds.conf.default

src-git luci https://github.com/coolsnowwolf/luci