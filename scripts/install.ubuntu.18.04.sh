#!/bin/bash

# Author
# original author:https://github.com/gongzili456
# modified by:https://github.com/haoel

# Ubuntu 18.04 系统环境

COLOR_ERROR="\e[38;5;198m"
COLOR_NONE="\e[0m"
COLOR_SUCC="\e[92m"

DOCKER_NAME="gost"

update_core(){
    echo -e "${COLOR_ERROR}当前系统内核版本太低 <$VERSION_CURR>,需要更新系统内核.${COLOR_NONE}"
    # 根据系统版本选择适当的 HWE 内核包
    UBUNTU_VERSION=$(lsb_release -rs)
    sudo apt install -y -qq --install-recommends linux-generic-hwe-"${UBUNTU_VERSION}"
    sudo apt autoremove

    echo -e "${COLOR_SUCC}内核更新完成,重新启动机器...${COLOR_NONE}"
    sudo reboot
}

check_bbr(){
    if grep -q "net.ipv4.tcp_congestion_control=bbr" /proc/sys/net/ipv4/tcp_congestion_control; then
        echo -e "${COLOR_SUCC}TCP BBR 已经启用${COLOR_NONE}"
        return 0
    fi
    
    # 检查是否支持 BBR
    if ! modprobe tcp_bbr &> /dev/null; then
        echo -e "${COLOR_ERROR}当前系统不支持 BBR${COLOR_NONE}"
        return 1
    fi
    
    start_bbr
}

start_bbr(){
    echo "启动 TCP BBR 拥塞控制算法"
    
    # 加载 BBR 模块
    if ! sudo modprobe tcp_bbr; then
        echo -e "${COLOR_ERROR}加载 tcp_bbr 模块失败${COLOR_NONE}"
        return 1
    fi
    
    # 设置开机自动加载
    if [ ! -d "/etc/modules-load.d" ]; then
        sudo mkdir -p /etc/modules-load.d
    fi
    echo "tcp_bbr" | sudo tee /etc/modules-load.d/bbr.conf > /dev/null

    # 创建新的 sysctl 配置文件，而不是直接修改 sysctl.conf
    if [ ! -d "/etc/sysctl.d" ]; then
        sudo mkdir -p /etc/sysctl.d
    fi
    
    # 将 BBR 配置写入独立的配置文件
    sudo tee /etc/sysctl.d/60-bbr.conf > /dev/null << EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

    # 应用 sysctl 配置
    if ! sudo sysctl --system; then
        echo -e "${COLOR_ERROR}应用 sysctl 配置失败${COLOR_NONE}"
        return 1
    fi

    # 验证配置是否生效
    local bbr_enabled=$(sudo sysctl -n net.ipv4.tcp_congestion_control)
    if [ "$bbr_enabled" = "bbr" ]; then
        echo -e "${COLOR_SUCC}BBR 已成功启用${COLOR_NONE}"
        return 0
    else
        echo -e "${COLOR_ERROR}BBR 启用失败，当前拥塞控制算法: $bbr_enabled${COLOR_NONE}"
        return 1
    fi
}

install_bbr() {
    # 如果内核版本号满足最小要求
    if [[ $VERSION_CURR > $VERSION_MIN ]]; then
        check_bbr
    else
        update_core
    fi
}


install_docker() {
    # 检查 Docker 是否已安装
    if ! command -v docker &> /dev/null; then
        echo "开始安装 Docker CE"

        # 卸载旧版本的 Docker（如果有的话）
        for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do 
            sudo apt-get remove -y $pkg &> /dev/null || true
        done

        # Add Docker's official GPG key:
        sudo apt-get update -qq
        sudo apt-get install -y ca-certificates curl gnupg
        sudo install -m 0755 -d /etc/apt/keyrings
        sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
        sudo chmod a+r /etc/apt/keyrings/docker.asc

        # Add the repository to Apt sources:
        echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt-get update -qq

        # 安装 Docker
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

        # 启动 Docker 服务
        sudo systemctl start docker
        # 等待 Docker 服务完全启动
        sleep 3

        sudo systemctl status docker --no-pager

        # 显示版本信息和服务状态
        echo "Docker 版本信息："
        sudo docker version
        
        echo -e "${COLOR_SUCC}Docker CE 安装成功并且可以正常运行${COLOR_NONE}"

    else
        echo -e "${COLOR_SUCC}Docker CE 已经安装成功了${COLOR_NONE}"
        
        # 确保 Docker 服务正在运行
        if ! sudo systemctl is-active docker &> /dev/null; then
            echo "Docker 服务未运行，正在启动..."
            sudo systemctl start docker
        fi
    fi
}


check_container(){
    has_container=$(sudo docker ps --format "{{.Names}}" | grep "$1")

    # test 命令规范： 0 为 true, 1 为 false, >1 为 error
    if [ -n "$has_container" ] ;then
        return 0
    else
        return 1
    fi
}


# 由于 Certbot 的 PPA 已被弃用，我们可以使用apt安装方法来获取最新版本
install_certbot() {
    echo "开始安装 certbot 命令行工具"
    sudo apt update -qq
    sudo apt-get install -y software-properties-common
    sudo apt-get install -y certbot
}

# ## 系统推荐的新的安装certbot的脚本，但是没有测试，是否会丢弃其他依赖，所有暂时还使用上面的完全版本
# install_certbot() {
#     echo "开始安装 certbot 命令行工具"
#     sudo apt update -qq
#     sudo apt install -y snapd
#     sudo snap install --classic certbot
#     sudo ln -s /snap/bin/certbot /usr/bin/certbot
# }

create_cert() {
    if ! [ -x "$(command -v certbot)" ]; then
        install_certbot
    fi

    echo "开始生成 SSL 证书"
    echo -e "${COLOR_ERROR}注意：生成证书前,需要将域名指向一个有效的 IP,否则无法创建证书.${COLOR_NONE}"
    read -r -p "是否已经将域名指向了 IP？[Y/n]" has_record

    if ! [[ "$has_record" = "Y" ]] ;then
        echo "请操作完成后再继续."
        return
    fi

    # 检查 80 端口
    echo "检查 80 端口状态..."
    if sudo lsof -i :80 > /dev/null 2>&1; then
        echo -e "${COLOR_ERROR}警告：80 端口被占用${COLOR_NONE}"
        echo "占用 80 端口的进程列表："
        sudo lsof -i :80
        read -r -p "是否要关闭这些进程？[y/N] " kill_process
        if [[ "$kill_process" =~ ^[Yy]$ ]]; then
            echo "正在停止占用 80 端口的进程..."
            sudo fuser -k 80/tcp
            sleep 2
        else
            echo "请手动释放 80 端口后再继续"
            return 1
        fi
    fi

    # 检查防火墙规则
    echo "检查防火墙规则..."
    if command -v ufw >/dev/null 2>&1; then
        if sudo ufw status | grep -q "active"; then
            if ! sudo ufw status | grep -q "80.*ALLOW"; then
                echo "正在添加防火墙规则允许 80 端口..."
                sudo ufw allow 80/tcp
            fi
        fi
    fi

    read -r -p "请输入你要使用的域名:" domain

    sudo certbot certonly --standalone -d "${domain}"
}

install_gost() {
    # 检查 Docker 是否安装
    if ! command -v docker &> /dev/null; then
        echo -e "${COLOR_ERROR}未发现 Docker，是否要安装 Docker？[y/N] ${COLOR_NONE}"
        read -r install_docker_answer
        if [[ "$install_docker_answer" =~ ^[Yy]$ ]]; then
            install_docker
        else
            return 1
        fi
    fi

    # 检查 Docker 服务是否运行
    if ! sudo systemctl is-active docker &> /dev/null; then
        echo -e "${COLOR_ERROR}Docker 服务未运行，正在尝试启动...${COLOR_NONE}"
        sudo systemctl start docker
        sleep 2  # 等待服务启动
    fi

    # 再次检查 Docker 服务状态
    if ! sudo systemctl is-active docker &> /dev/null; then
        echo -e "${COLOR_ERROR}无法启动 Docker 服务，请检查系统日志${COLOR_NONE}"
        return 1
    fi

    # 检查已存在的 Gost 容器
    if check_container gost; then
        echo -e "${COLOR_ERROR}发现正在运行的 Gost 容器。${COLOR_NONE}"
        read -r -p "是否要停止并删除现有容器重新安装？[y/N] " remove_container
        if [[ "$remove_container" =~ ^[Yy]$ ]]; then
            echo "正在停止并删除现有 Gost 容器..."
            sudo docker stop gost
            sudo docker rm gost
        else
            return 1
        fi
    fi

    echo "准备启动 Gost 代理程序,为了安全,需要使用用户名与密码进行认证."
    read -r -p "请输入你要使用的域名：" DOMAIN
    read -r -p "请输入你要使用的用户名:" USER
    read -r -p "请输入你要使用的密码:" PASS
    read -r -p "请输入HTTP/2需要侦听的端口号(443)：" PORT

    if [[ -z "${PORT// }" ]] || ! [[ "${PORT}" =~ ^[0-9]+$ ]] || ! { [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ]; }; then
        echo -e "${COLOR_ERROR}非法端口,使用默认端口 443 !${COLOR_NONE}"
        PORT=443
    fi

    # 检查端口是否被占用
    if sudo lsof -i :"$PORT" > /dev/null 2>&1; then
        echo -e "${COLOR_ERROR}端口 $PORT 已被占用，请选择其他端口或释放该端口${COLOR_NONE}"
        return 1
    fi

    BIND_IP=0.0.0.0
    CERT_DIR=/etc/letsencrypt
    CERT=${CERT_DIR}/live/${DOMAIN}/fullchain.pem
    KEY=${CERT_DIR}/live/${DOMAIN}/privkey.pem

    # # 验证证书文件是否存在
    # if [ ! -f "$CERT" ] || [ ! -f "$KEY" ]; then
    #     echo -e "${COLOR_ERROR}证书文件不存在！请先运行'创建 SSL 证书'选项来生成证书。${COLOR_NONE}"
    #     echo "需要的文件："
    #     echo "- $CERT"
    #     echo "- $KEY"
    #     return 1
    # fi

    # # 检查证书权限
    # if [ ! -r "$CERT" ] || [ ! -r "$KEY" ]; then
    #     echo -e "${COLOR_ERROR}证书文件权限不正确，正在尝试修复...${COLOR_NONE}"
    #     sudo chmod 644 "$CERT" "$KEY"
    # fi

    echo "正在启动 Gost 容器..."
    ## 此处的--name gost是自定义的容器实例名称
    ## ginuerzh/gost是V2版本的容器
    ## gogost/gost是V3版本的容器
    sudo docker run -d --name gost \
        -v ${CERT_DIR}:${CERT_DIR}:ro \
        --net=host ginuerzh/gost \
        -L "http2://${USER}:${PASS}@${BIND_IP}:${PORT}?cert=${CERT}&key=${KEY}&probe_resist=code:400&knock=www.google.com"
}

crontab_exists() {
    crontab -l 2>/dev/null | grep "$1" >/dev/null 2>/dev/null
}


create_cron_job() {
    # 检查定时任务是否已经存在
    crontab_exists() {
        local task="$1"
        crontab -l 2>/dev/null | grep -Fxq "$task"
    }

    # 添加 certbot 定时任务
    CERTBOT_TASK="0 0 1 * * /usr/bin/certbot renew --force-renewal"
    if ! crontab_exists "$CERTBOT_TASK"; then
        (crontab -l 2>/dev/null; echo "$CERTBOT_TASK") | crontab -
        echo -e "${COLOR_SUCC}成功安装证书renew定时作业！${COLOR_NONE}"
    else
        echo -e "${COLOR_SUCC}证书renew定时作业已经安装过！${COLOR_NONE}"
    fi

    # 添加 docker restart gost 定时任务
    GOST_TASK="5 0 1 * * /usr/bin/docker restart gost"
    if ! crontab_exists "$GOST_TASK"; then
        (crontab -l 2>/dev/null; echo "$GOST_TASK") | crontab -
        echo -e "${COLOR_SUCC}成功安装gost更新证书定时作业！${COLOR_NONE}"
    else
        echo -e "${COLOR_SUCC}gost更新证书定时作业已经安装过！${COLOR_NONE}"
    fi
}

install_shadowsocks(){
    if ! [ -x "$(command -v docker)" ]; then
        echo -e "${COLOR_ERROR}未发现Docker，请求安装 Docker ! ${COLOR_NONE}"
        return
    fi

    if check_container ss ; then
        echo -e "${COLOR_ERROR}ShadowSocks 容器已经在运行了，你可以手动停止容器，并删除容器，然后再执行本命令来重新安装 ShadowSocks。${COLOR_NONE}"
        return
    fi

    echo "准备启动 ShadowSocks 代理程序,为了安全,需要使用用户名与密码进行认证."
    read -r -p "请输入你要使用的密码:" PASS
    read -r -p "请输入ShadowSocks需要侦听的端口号(1984)：" PORT

    BIND_IP=0.0.0.0

    if [[ -z "${PORT// }" ]] || ! [[ "${PORT}" =~ ^[0-9]+$ ]] || ! { [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ]; }; then
        echo -e "${COLOR_ERROR}非法端口,使用默认端口 1984 !${COLOR_NONE}"
        PORT=1984
    fi

    sudo docker run -dt --name ss \
        -p "${PORT}:${PORT}" mritd/shadowsocks \
        -s "-s ${BIND_IP} -p ${PORT} -m aes-256-cfb -k ${PASS} --fast-open"
}

install_vpn(){
    if ! [ -x "$(command -v docker)" ]; then
        echo -e "${COLOR_ERROR}未发现Docker，请求安装 Docker ! ${COLOR_NONE}"
        return
    fi

    if check_container vpn ; then
        echo -e "${COLOR_ERROR}VPN 容器已经在运行了，你可以手动停止容器，并删除容器，然后再执行本命令来重新安装 VPN。${COLOR_NONE}"
        return
    fi

    echo "准备启动 VPN/L2TP 代理程序,为了安全,需要使用用户名与密码进行认证."
    read -r -p "请输入你要使用的用户名:" USER
    read -r -p "请输入你要使用的密码:" PASS
    read -r -p "请输入你要使用的PSK Key:" PSK

    sudo docker run -d --name vpn --privileged \
        -e PSK="${PSK}" \
        -e USERNAME="${USER}" -e PASSWORD="${PASS}" \
        -p 500:500/udp \
        -p 4500:4500/udp \
        -p 1701:1701/tcp \
        -p 1194:1194/udp  \
        siomiz/softethervpn
}

install_brook(){
    brook_file="/usr/local/brook/brook"
    [[ -e ${brook_file} ]] && echo -e "${COLOR_ERROR}Brook 已经安装，请检查!" && return
    wget -N --no-check-certificate https://raw.githubusercontent.com/ToyoDAdoubi/doubi/master/brook.sh &&\
        chmod +x brook.sh && sudo bash brook.sh
}

# uninstall

# uninstall_services() {
#     echo "开始卸载服务..."

#     # 获取 Gost 容器的域名
#     if command -v docker &> /dev/null && sudo docker ps -a --format '{{.Names}}' | grep -q gost; then
#         gost_domain=$(sudo docker inspect gost | grep -oP '(?<=cert=\/etc\/letsencrypt\/live\/)[^/]+')
#         echo -e "${COLOR_SUCC}检测到 Gost 使用的域名: $gost_domain${COLOR_NONE}"
#     else
#         echo -e "${COLOR_ERROR}未检测到 Gost 容器${COLOR_NONE}"
#         gost_domain=""
#     fi

#     # 停止并移除容器
#     if command -v docker &> /dev/null; then
#         for container in gost ss vpn; do
#             if sudo docker ps -a --format '{{.Names}}' | grep -q $container; then
#                 sudo docker stop $container
#                 sudo docker rm $container
#                 echo -e "${COLOR_SUCC}成功停止并移除容器 $container${COLOR_NONE}"
#             else
#                 echo -e "${COLOR_ERROR}容器 $container 未找到${COLOR_NONE}"
#             fi
#         done
#     fi

#     # 卸载 Docker
#     if command -v docker &> /dev/null; then
#         echo "正在卸载 Docker..."
#         # 停止服务
#         sudo systemctl stop docker.socket docker.service
        
#         # 卸载所有 Docker 包
#         sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
#         sudo apt-get autoremove -y --purge
        
#         # 删除 Docker 配置和数据
#         sudo rm -rf /var/lib/docker
#         sudo rm -rf /etc/docker
#         sudo rm -rf /etc/apt/keyrings/docker.asc
#         sudo rm -rf /etc/apt/sources.list.d/docker.list
        
#         echo -e "${COLOR_SUCC}Docker 已完全卸载${COLOR_NONE}"
#     else
#         echo -e "${COLOR_ERROR}Docker 未安装${COLOR_NONE}"
#     fi

#     # 卸载 Certbot 并删除证书文件
#     if command -v certbot &> /dev/null; then
#         if [ -n "$gost_domain" ]; then
#             domain=$gost_domain
#         else
#             echo "请输入要删除证书的域名:"
#             read -r domain
#         fi
        
#         # 卸载 Certbot
#         sudo apt-get purge -y certbot
#         sudo apt-get autoremove -y --purge

#         # 删除证书文件（如果存在）
#         if [ -n "$domain" ]; then
#             sudo rm -rf "/etc/letsencrypt/live/$domain"
#             sudo rm -rf "/etc/letsencrypt/archive/$domain"
#             sudo rm -rf "/etc/letsencrypt/renewal/$domain.conf"
#         fi
        
#         echo -e "${COLOR_SUCC}Certbot 和 SSL 证书已删除${COLOR_NONE}"
#     else
#         echo -e "${COLOR_ERROR}Certbot 未安装${COLOR_NONE}"
#     fi

#     # 卸载 BBR
#     # if lsmod | grep -q bbr; then
#     #     sudo rmmod tcp_bbr
#     #     sudo sed -i '/tcp_bbr/d' /etc/modules-load.d/modules.conf
#     #     sudo sed -i '/net.core.default_qdisc=fq/d' /etc/sysctl.conf
#     #     sudo sed -i '/net.ipv4.tcp_congestion_control=bbr/d' /etc/sysctl.conf
#     #     sudo sysctl -p
#     #     echo -e "${COLOR_SUCC}BBR 已卸载${COLOR_NONE}"
#     # else
#     #     echo -e "${COLOR_ERROR}BBR 未安装${COLOR_NONE}"
#     # fi

#     # 卸载 Brook
#     if [ -e /usr/local/brook/brook ]; then
#         sudo rm /usr/local/brook/brook
#         echo -e "${COLOR_SUCC}Brook 已卸载${COLOR_NONE}"
#     else
#         echo -e "${COLOR_ERROR}Brook 未安装${COLOR_NONE}"
#     fi

#     # 删除 Cron Jobs
#     crontab -l 2>/dev/null | grep -v "/usr/bin/certbot renew --force-renewal" | crontab -
#     crontab -l 2>/dev/null | grep -v "/usr/bin/docker restart gost" | crontab -
#     echo -e "${COLOR_SUCC}Cron Jobs 已删除${COLOR_NONE}"

#     echo -e "${COLOR_SUCC}所有操作已完成，即将重启系统...${COLORNONE}" 
#     sudo reboot
# }

# end uninstall

# TODO: install v2ray

init(){
    VERSION_CURR=$(uname -r | awk -F '-' '{print $1}')
    VERSION_MIN="4.9.0"

    OIFS=$IFS  # Save the current IFS (Internal Field Separator)
    IFS=','    # New IFS

    COLUMNS=50
    echo -e "\n菜单选项\n"

    while true
    do
        PS3="Please select an option:"
        re='^[0-9]+$'
        select opt in "安装 TCP BBR 拥塞控制算法" \
                    "安装 Docker 服务程序" \
                    "创建 SSL 证书" \
                    "安装 Gost HTTP/2 代理服务" \
                    "安装 ShadowSocks 代理服务" \
                    "安装 VPN/L2TP 服务" \
                    "安装 Brook 代理服务" \
                    "创建证书更新 CronJob" \
                    "退出" ; do

            if ! [[ $REPLY =~ $re ]] ; then
                echo -e "${COLOR_ERROR}Invalid option. Please input a number.${COLOR_NONE}"
                break;
            elif (( REPLY == 1 )) ; then
                install_bbr
                break;
            elif (( REPLY == 2 )) ; then
                install_docker
                break
            elif (( REPLY == 3 )) ; then
                create_cert
                break
            elif (( REPLY == 4 )) ; then
                install_gost
                break
            elif (( REPLY == 5 )); then
                install_shadowsocks
                break
            elif (( REPLY == 6 )); then
                install_vpn
                break
            elif (( REPLY == 7 )); then
                install_brook
                break
            elif (( REPLY == 8 )); then
                create_cron_job
                break
            elif (( REPLY == 9 )); then
                exit
            else
                echo -e "${COLOR_ERROR}Invalid option. Try another one.${COLOR_NONE}"
            fi
        done
    done

    echo "${opt}"
    IFS=$OIFS  # Restore the IFS
}

init
