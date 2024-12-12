#!/bin/bash


# Ubuntu 18.04 系统环境
COLOR_ERROR="\e[38;5;198m"
COLOR_NONE="\e[0m"
COLOR_SUCC="\e[92m"

# 获取 Gost 容器的域名
if sudo docker ps -a --format '{{.Names}}' | grep -q gost; then
	gost_domain=$(sudo docker inspect gost | grep -oP '(?<=cert=\/etc\/letsencrypt\/live\/)[^/]+')
	echo -e "${COLOR_SUCC}检测到 Gost 使用的域名: $gost_domain${COLOR_NONE}"
else
	echo -e "${COLOR_ERROR}未检测到 Gost 容器${COLOR_NONE}"
	gost_domain=""
fi

echo -e "${COLOR_SUCC}检测到 Gost 使用的域名: $gost_domain${COLOR_NONE}"
