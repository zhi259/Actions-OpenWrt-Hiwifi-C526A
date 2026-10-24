#!/bin/bash

# 添加 PassWall2 官方源
echo 'src-git passwall2 https://github.com/Openwrt-Passwall/openwrt-passwall2.git;main' >>feeds.conf.default
echo 'src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git;main' >>feeds.conf.default

# 添加 kenzo 源（提供依赖和常用插件）
echo 'src-git kenzo https://github.com/kenzok8/openwrt-packages' >>feeds.conf.default