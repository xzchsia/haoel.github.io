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
    sudo modprobe tcp_bbr
    echo "tcp_bbr" | sudo tee --append /etc/modules-load.d/modules.conf
    echo "net.core.default_qdisc=fq" | sudo tee --append /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee --append /etc/sysctl.conf
    echo "net.ipv4.tcp_available_congestion_control=bbr" | sudo tee --append /etc/sysctl.conf
    sudo sysctl -p
    sysctl net.ipv4.tcp_available_congestion_control
    sysctl net.ipv4.tcp_congestion_control
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

        # 添加 Docker 官方 GPG 密钥
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

        # 设置 Docker 源（仅支持 Ubuntu 20.04 及以上）
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

        # 安装 Docker CE
        sudo apt-get update -qq
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io

        # 将当前用户添加到 docker 用户组
        sudo usermod -aG docker $USER

        # 确保 Docker 服务启动并设置开机自启
        sudo systemctl start docker
        sudo systemctl enable docker

        # 验证 Docker 服务状态
        if ! sudo systemctl is-active --quiet docker; then
            echo -e "${COLOR_ERROR}Docker 服务启动失败，请检查系统日志${COLOR_NONE}"
            return 1
        fi

        echo -e "${COLOR_SUCC}Docker CE 安装成功并已启动，请重新登录以应用用户组更改。${COLOR_NONE}"
    else
        # 如果 Docker 已安装，也要确保服务正在运行
        if ! sudo systemctl is-active --quiet docker; then
            echo "Docker 服务未运行，正在启动..."
            sudo systemctl start docker
            sudo systemctl enable docker
        fi
        echo -e "${COLOR_SUCC}Docker CE 已经安装并正在运行${COLOR_NONE}"
    fi

    # 显示 Docker 版本和服务状态
    docker --version
    sudo systemctl status docker --no-pager
}

# ## 修复替换提示 解决 apt-key 弃用警告，暂未测试
# install_docker() {
#     if ! [ -x "$(command -v docker)" ]; then
#         echo "开始安装 Docker CE"
#         curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
#         echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
#         sudo apt-get update -qq
#         sudo apt-get install -y docker-ce
#     else
#         echo "Docker CE 已经安装成功了"
#     fi
# }


check_container(){
    has_container=$(sudo docker ps --format "{{.Names}}" | grep "$1")

    # test 命令规范： 0 为 true, 1 为 false, >1 为 error
    if [ -n "$has_container" ] ;then
        return 0
    else
        return 1
    fi
}

### 安装 acme.sh 工具 ###
# install_acme_sh() {
#     echo "开始安装 acme.sh 命令行工具"
    
#     # 安装依赖
#     sudo apt-get update
#     sudo apt-get install -y socat curl ca-certificates
    
#     # 检查 DNS over HTTPS
#     if dpkg --compare-versions "$(lsb_release -rs)" "ge" "22.04"; then
#         sudo apt-get install -y systemd-resolved
#         sudo systemctl enable systemd-resolved
#         sudo systemctl start systemd-resolved
#     fi
    
#     read -r -p "请输入你要使用的email:" email
    
#     # 安装或更新 acme.sh
#     if [ -f ~/.acme.sh/acme.sh ]; then
#         ~/.acme.sh/acme.sh --upgrade
#     else
#         curl https://get.acme.sh | sh -s email="$email"
#     fi
    
#     # 配置 acme.sh
#     export PATH="$PATH:$HOME/.acme.sh"
#     ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
# }

# ### 创建 SSL 证书 ###
# create_cert() {
#     if ! [ -x "$(command -v acme.sh)" ]; then
#         install_acme_sh
#     fi

#     echo "开始生成 SSL 证书"
#     echo -e "${COLOR_ERROR}注意：生成证书前,需要将域名指向一个有效的 IP,否则无法创建证书.${COLOR_NONE}"
#     read -r -p "是否已经将域名指向了 IP？[Y/n]" has_record

#     if ! [[ "$has_record" = "Y" ]]; then
#         echo "请操作完成后再继续."
#         return
#     fi

#     read -r -p "请输入你要使用的域名:" domain

#     # 使用 standalone 模式申请证书
#     ~/.acme.sh/acme.sh --issue --standalone -d "${domain}"

#     # # 安装证书到指定路径（可根据你的服务调整）
#     # ~/.acme.sh/acme.sh --install-cert -d "${domain}" \
#     #     --key-file       /etc/ssl/private/"${domain}".key \
#     #     --fullchain-file /etc/ssl/certs/"${domain}".crt \
#     #     --reloadcmd     "systemctl reload nginx"

#     # echo "证书已安装，路径如下："
#     # echo "/etc/ssl/private/${domain}.key"
#     # echo "/etc/ssl/certs/${domain}.crt"
# }

### 安装 acme.sh 工具 ###
install_acme_sh() {
    echo "开始安装 acme.sh 命令行工具"
    
    # 安装依赖
    sudo apt-get update
    sudo apt-get install -y socat curl ca-certificates
    
    read -r -p "请输入你要使用的email:" email
    
    # 以当前用户身份安装（不使用 sudo）
    if [ "$(id -u)" = "0" ]; then
        # 如果是 root 用户，切换到 SUDO_USER
        if [ -n "$SUDO_USER" ]; then
            INSTALL_USER=$SUDO_USER
            INSTALL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
        else
            echo "错误：请使用 'sudo -i' 获取完整的 root 环境，或使用非 root 用户执行此脚本"
            return 1
        fi
    else
        INSTALL_USER=$USER
        INSTALL_HOME=$HOME
    fi
    
    # 以正确的用户身份安装
    if [ "$(id -u)" = "0" ]; then
        su - "$INSTALL_USER" -c "curl https://get.acme.sh | sh -s email=$email"
    else
        curl https://get.acme.sh | sh -s email="$email"
    fi
    
    # 设置默认 CA
    if [ "$(id -u)" = "0" ]; then
        su - "$INSTALL_USER" -c "~/.acme.sh/acme.sh --set-default-ca --server letsencrypt"
    else
        "$INSTALL_HOME/.acme.sh/acme.sh" --set-default-ca --server letsencrypt
    fi
    
    echo "acme.sh 安装完成，请使用非 root 用户执行证书申请操作"
}

### 创建 SSL 证书 ###
create_cert() {
    # 检查是否以 root 用户运行
    if [ "$(id -u)" = "0" ]; then
        if [ -n "$SUDO_USER" ]; then
            echo "检测到使用 sudo 运行，将切换到普通用户执行证书申请..."
            # 将命令传递给普通用户执行
            su - "$SUDO_USER" -c "bash $0"
            return
        else
            echo "错误：请使用非 root 用户执行此命令"
            return 1
        fi
    fi

    if ! [ -f "$HOME/.acme.sh/acme.sh" ]; then
        install_acme_sh
    fi

    echo "开始生成 SSL 证书"
    echo -e "${COLOR_ERROR}注意：生成证书前,需要将域名指向一个有效的 IP,否则无法创建证书.${COLOR_NONE}"
    read -r -p "是否已经将域名指向了 IP？[Y/n]" has_record

    if ! [[ "$has_record" = "Y" ]]; then
        echo "请操作完成后再继续."
        return
    fi

    read -r -p "请输入你要使用的域名:" domain

    # 检查 80 端口
    if sudo lsof -i :80 > /dev/null 2>&1; then
        echo "警告：80 端口被占用，尝试停止相关服务..."
        sudo fuser -k 80/tcp || true
        sleep 2
    fi

    # 使用 standalone 模式申请证书
    "$HOME/.acme.sh/acme.sh" --issue --standalone -d "${domain}"
}

install_gost() {
    if ! [ -x "$(command -v docker)" ]; then
        echo -e "${COLOR_ERROR}未发现Docker，请求安装 Docker ! ${COLOR_NONE}"
        return
    fi

    if check_container gost ; then
        echo -e "${COLOR_ERROR}Gost 容器已经在运行了，你可以手动停止容器，并删除容器，然后再执行本命令来重新安装 Gost。 ${COLOR_NONE}"
        return
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

    BIND_IP=0.0.0.0
    CERT_DIR=/etc/ssl/gost/${DOMAIN}
    CERT=${CERT_DIR}/fullchain.pem
    KEY=${CERT_DIR}/key.pem

    # 创建证书目录
    sudo mkdir -p "${CERT_DIR}"

    # 安装证书（假设已申请成功）
    ~/.acme.sh/acme.sh --install-cert -d "${DOMAIN}" \
        --key-file "${KEY}" \
        --fullchain-file "${CERT}" \
        --reloadcmd "docker restart gost"

    # 启动 Gost 容器
    # 使用 GOST V3 版本
    sudo docker run -d --name gost \
        -v ${CERT_DIR}:${CERT_DIR}:ro \
        --net=host gogost/gost \
        -L "http2://${USER}:${PASS}@${BIND_IP}:${PORT}?cert=${CERT}&key=${KEY}&probe_resist=code:400&knock=www.google.com"

    # sudo docker run -d --name gost \
    #     -v ${CERT_DIR}:${CERT_DIR}:ro \
    #     --net=host ginuerzh/gost \
    #     -L "http2://${USER}:${PASS}@${BIND_IP}:${PORT}?cert=${CERT}&key=${KEY}&probe_resist=code:400&knock=www.google.com"
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
    
    # 确保 cron 服务正在运行
    if ! systemctl is-active --quiet cron; then
        echo "Cron 服务未运行，正在启动..."
        sudo systemctl start cron
        sudo systemctl enable cron
    fi

    # 添加 acme.sh 自动续期任务
    ACMESH_TASK="0 0 1 * * $HOME/.acme.sh/acme.sh --cron --home ~/.acme.sh > /dev/null"
    if ! crontab_exists "$ACMESH_TASK"; then
        (crontab -l 2>/dev/null; echo "$ACMESH_TASK") | crontab -
        echo -e "${COLOR_SUCC}成功安装 acme.sh 证书续期定时作业！${COLOR_NONE}"
    else
        echo -e "${COLOR_SUCC}acme.sh 证书续期定时作业已经安装过！${COLOR_NONE}"
    fi

    # 添加 docker restart gost 定时任务（可选）
    GOST_TASK="5 0 1 * * /usr/bin/docker restart gost"
    if ! crontab_exists "$GOST_TASK"; then
        (crontab -l 2>/dev/null; echo "$GOST_TASK") | crontab -
        echo -e "${COLOR_SUCC}成功安装 gost 重启定时作业！${COLOR_NONE}"
    else
        echo -e "${COLOR_SUCC}gost 重启定时作业已经安装过！${COLOR_NONE}"
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
uninstall_services() {
    echo "开始卸载服务..."

    # 获取 Gost 容器的域名（适配 acme.sh 路径）
    if sudo docker ps -a --format '{{.Names}}' | grep -q gost; then
        gost_domain=$(sudo docker inspect gost | grep -oP '(?<=cert=\/etc\/ssl\/gost\/)[^/]+(?=\/fullchain.pem)')
        echo -e "${COLOR_SUCC}检测到 Gost 使用的域名: $gost_domain${COLOR_NONE}"
    else
        echo -e "${COLOR_ERROR}未检测到 Gost 容器${COLOR_NONE}"
        gost_domain=""
    fi

    # 停止并移除容器
    for container in gost ss vpn; do
        if sudo docker ps -a --format '{{.Names}}' | grep -q $container; then
            sudo docker stop $container
            sudo docker rm $container
            echo -e "${COLOR_SUCC}成功停止并移除容器 $container${COLOR_NONE}"
        else
            echo -e "${COLOR_ERROR}容器 $container 未找到${COLOR_NONE}"
        fi
    done

    # 卸载 Docker
    if [ -x "$(command -v docker)" ]; then
        sudo systemctl stop docker
        sudo apt-get purge -y docker-ce
        sudo apt-get autoremove -y --purge docker-ce
        sudo rm -rf /var/lib/docker
        sudo rm -rf /etc/docker
        sudo rm /etc/apparmor.d/docker
        sudo groupdel docker
        sudo rm -rf /var/run/docker.sock
        sudo rm -rf /usr/bin/docker
        echo -e "${COLOR_SUCC}Docker 已卸载${COLOR_NONE}"
    else
        echo -e "${COLOR_ERROR}Docker 未安装${COLOR_NONE}"
    fi

    # 卸载 acme.sh 并删除证书文件
    if [ -f ~/.acme.sh/acme.sh ]; then
        if [ -n "$gost_domain" ]; then
            domain=$gost_domain
        else
            echo "请输入要删除证书的域名:"
            read -r domain
        fi

        ~/.acme.sh/acme.sh --remove -d "$domain"
        sudo rm -rf /etc/ssl/gost/"$domain"

        # 删除 acme.sh 本体（可选）
        rm -rf ~/.acme.sh
        sed -i '/acme.sh/d' ~/.bashrc

        echo -e "${COLOR_SUCC}acme.sh 和 SSL 证书已删除${COLOR_NONE}"
    else
        echo -e "${COLOR_ERROR}acme.sh 未安装${COLOR_NONE}"
    fi

    # 卸载 Brook
    if [ -e /usr/local/brook/brook ]; then
        sudo rm /usr/local/brook/brook
        echo -e "${COLOR_SUCC}Brook 已卸载${COLOR_NONE}"
    else
        echo -e "${COLOR_ERROR}Brook 未安装${COLOR_NONE}"
    fi

    # 删除 Cron Jobs（适配 acme.sh 和 gost）
    crontab -l 2>/dev/null | grep -v "acme.sh --cron" | crontab -
    crontab -l 2>/dev/null | grep -v "/usr/bin/docker restart gost" | crontab -
    echo -e "${COLOR_SUCC}Cron Jobs 已删除${COLOR_NONE}"

    echo -e "${COLOR_SUCC}所有操作已完成，即将重启系统...${COLOR_NONE}" 
    sudo reboot
}

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
                    "卸载所有服务" \
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
                uninstall_services
                break
            elif (( REPLY == 10 )); then
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
