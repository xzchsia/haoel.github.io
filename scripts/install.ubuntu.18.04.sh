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
    sudo apt install -y -qq --install-recommends linux-generic-hwe-18.04
    sudo apt autoremove

    echo -e "${COLOR_SUCC}内核更新完成,重新启动机器...${COLOR_NONE}"
    sudo reboot
}

check_bbr(){
    has_bbr=$(lsmod | grep bbr)

    # 如果已经发现 bbr 进程
    if [ -n "$has_bbr" ] ;then
        echo -e "${COLOR_SUCC}TCP BBR 拥塞控制算法已经启动${COLOR_NONE}"
    else
        start_bbr
    fi
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

# install_docker() {
#     if ! [ -x "$(command -v docker)" ]; then
#         echo "开始安装 Docker CE"
#         curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
#         sudo add-apt-repository \
#             "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
#             $(lsb_release -cs) \
#             stable"
#         sudo apt-get update -qq
#         sudo apt-get install -y docker-ce
#     else
#         echo -e "${COLOR_SUCC}Docker CE 已经安装成功了${COLOR_NONE}"
#     fi
# }

install_docker() {
    # 检查 Docker 是否已安装
    if ! command -v docker &> /dev/null; then
        echo "开始安装 Docker CE"

        # # 安装必要的依赖包
        # sudo apt-get update -qq
        # sudo apt-get install -y \
        #     apt-transport-https \
        #     ca-certificates \
        #     curl \
        #     software-properties-common

        # 添加 Docker 官方 GPG 密钥
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

        # 设置 Docker 源（仅支持 Ubuntu 20.04 及以上）
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

        # 安装 Docker CE
        sudo apt-get update -qq
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io
        # sudo apt-get install -y docker-ce

        # 将当前用户添加到 docker 用户组
        sudo usermod -aG docker $USER
        echo -e "${COLOR_SUCC}Docker CE 安装成功，请重新登录以应用用户组更改。${COLOR_NONE}"
    else
        echo -e "${COLOR_SUCC}Docker CE 已经安装成功了${COLOR_NONE}"
    fi
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
install_acme_sh() {
    echo "开始安装 acme.sh 命令行工具"
    # 安装 socat（用于 standalone 模式）
    sudo apt-get install -y socat
    
    read -r -p "请输入你要使用的email:" email
    curl https://get.acme.sh | sh -s email="$email"

    # 立即加载 acme.sh 命令别名
    source ~/.bashrc

    # 设置默认 CA 为 Let's Encrypt（默认是 ZeroSSL）
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
}

### 创建 SSL 证书 ###
create_cert() {
    if ! [ -x "$(command -v acme.sh)" ]; then
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

    # 使用 standalone 模式申请证书
    ~/.acme.sh/acme.sh --issue --standalone -d "${domain}"

    # # 安装证书到指定路径（可根据你的服务调整）
    # ~/.acme.sh/acme.sh --install-cert -d "${domain}" \
    #     --key-file       /etc/ssl/private/"${domain}".key \
    #     --fullchain-file /etc/ssl/certs/"${domain}".crt \
    #     --reloadcmd     "systemctl reload nginx"

    # echo "证书已安装，路径如下："
    # echo "/etc/ssl/private/${domain}.key"
    # echo "/etc/ssl/certs/${domain}.crt"
}

# # 由于 Certbot 的 PPA 已被弃用，我们可以使用apt安装方法来获取最新版本
# install_certbot() {
#     echo "开始安装 certbot 命令行工具"
#     sudo apt update -qq
#     # sudo apt-get install -y software-properties-common
#     sudo apt-get install -y certbot
# }

# ## 系统推荐的新的安装certbot的脚本，但是没有测试，是否会丢弃其他依赖，所有暂时还使用上面的完全版本
# install_certbot() {
#     echo "开始安装 certbot 命令行工具"
#     sudo apt update -qq
#     sudo apt install -y snapd
#     sudo snap install --classic certbot
#     sudo ln -s /snap/bin/certbot /usr/bin/certbot
# }

# create_cert() {
#     if ! [ -x "$(command -v certbot)" ]; then
#         install_certbot
#     fi

#     echo "开始生成 SSL 证书"
#     echo -e "${COLOR_ERROR}注意：生成证书前,需要将域名指向一个有效的 IP,否则无法创建证书.${COLOR_NONE}"
#     read -r -p "是否已经将域名指向了 IP？[Y/n]" has_record

#     if ! [[ "$has_record" = "Y" ]] ;then
#         echo "请操作完成后再继续."
#         return
#     fi

#     read -r -p "请输入你要使用的域名:" domain

#     sudo certbot certonly --standalone -d "${domain}"
# }

# install_gost() {
#     if ! [ -x "$(command -v docker)" ]; then
#         echo -e "${COLOR_ERROR}未发现Docker，请求安装 Docker ! ${COLOR_NONE}"
#         return
#     fi

#     if check_container gost ; then
#         echo -e "${COLOR_ERROR}Gost 容器已经在运行了，你可以手动停止容器，并删除容器，然后再执行本命令来重新安装 Gost。 ${COLOR_NONE}"
#         return
#     fi

#     echo "准备启动 Gost 代理程序,为了安全,需要使用用户名与密码进行认证."
#     read -r -p "请输入你要使用的域名：" DOMAIN
#     read -r -p "请输入你要使用的用户名:" USER
#     read -r -p "请输入你要使用的密码:" PASS
#     read -r -p "请输入HTTP/2需要侦听的端口号(443)：" PORT

#     if [[ -z "${PORT// }" ]] || ! [[ "${PORT}" =~ ^[0-9]+$ ]] || ! { [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ]; }; then
#         echo -e "${COLOR_ERROR}非法端口,使用默认端口 443 !${COLOR_NONE}"
#         PORT=443
#     fi

#     BIND_IP=0.0.0.0
#     CERT_DIR=/etc/letsencrypt
#     CERT=${CERT_DIR}/live/${DOMAIN}/fullchain.pem
#     KEY=${CERT_DIR}/live/${DOMAIN}/privkey.pem

#     ## 此处的--name gost是自定义的容器实例名称
#     ## ginuerzh/gost是V2版本的容器
#     ## gogost/gost是V3版本的容器
#     sudo docker run -d --name gost \
#         -v ${CERT_DIR}:${CERT_DIR}:ro \
#         --net=host ginuerzh/gost \
#         -L "http2://${USER}:${PASS}@${BIND_IP}:${PORT}?cert=${CERT}&key=${KEY}&probe_resist=code:400&knock=www.google.com"
# }

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
    sudo docker run -d --name gost \
        -v ${CERT_DIR}:${CERT_DIR}:ro \
        --net=host ginuerzh/gost \
        -L "http2://${USER}:${PASS}@${BIND_IP}:${PORT}?cert=${CERT}&key=${KEY}&probe_resist=code:400&knock=www.google.com"
}


crontab_exists() {
    crontab -l 2>/dev/null | grep "$1" >/dev/null 2>/dev/null
}

# create_cron_job(){
#     # 写入前先检查，避免重复任务。
#     if ! crontab_exists "certbot renew --force-renewal"; then
#         echo "0 0 1 * * /usr/bin/certbot renew --force-renewal" >> /var/spool/cron/crontabs/root
#         echo "${COLOR_SUCC}成功安装证书renew定时作业！${COLOR_NONE}"
#     else
#         echo "${COLOR_SUCC}证书renew定时作业已经安装过！${COLOR_NONE}"
#     fi

#     if ! crontab_exists "docker restart gost"; then
#         echo "5 0 1 * * /usr/bin/docker restart gost" >> /var/spool/cron/crontabs/root
#         echo "${COLOR_SUCC}成功安装gost更新证书定时作业！${COLOR_NONE}"
#     else
#         echo "${COLOR_SUCC}gost更新证书定时作业已经成功安装过！${COLOR_NONE}"
#     fi
# }

# create_cron_job() {
#     # 检查定时任务是否已经存在
#     crontab_exists() {
#         local task="$1"
#         crontab -l 2>/dev/null | grep -Fxq "$task"
#     }

#     # 添加 certbot 定时任务
#     CERTBOT_TASK="0 0 1 * * /usr/bin/certbot renew --force-renewal"
#     if ! crontab_exists "$CERTBOT_TASK"; then
#         (crontab -l 2>/dev/null; echo "$CERTBOT_TASK") | crontab -
#         echo -e "${COLOR_SUCC}成功安装证书renew定时作业！${COLOR_NONE}"
#     else
#         echo -e "${COLOR_SUCC}证书renew定时作业已经安装过！${COLOR_NONE}"
#     fi

#     # 添加 docker restart gost 定时任务
#     GOST_TASK="5 0 1 * * /usr/bin/docker restart gost"
#     if ! crontab_exists "$GOST_TASK"; then
#         (crontab -l 2>/dev/null; echo "$GOST_TASK") | crontab -
#         echo -e "${COLOR_SUCC}成功安装gost更新证书定时作业！${COLOR_NONE}"
#     else
#         echo -e "${COLOR_SUCC}gost更新证书定时作业已经安装过！${COLOR_NONE}"
#     fi
# }

create_cron_job() {
    # 检查定时任务是否已经存在
    crontab_exists() {
        local task="$1"
        crontab -l 2>/dev/null | grep -Fxq "$task"
    }

    # 添加 acme.sh 自动续期任务
    ACMESH_TASK="0 0 1 * * ~/.acme.sh/acme.sh --cron --home ~/.acme.sh > /dev/null"
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

# uninstall_services() {
#     echo "开始卸载服务..."

#     # 获取 Gost 容器的域名
#     if sudo docker ps -a --format '{{.Names}}' | grep -q gost; then
#         gost_domain=$(sudo docker inspect gost | grep -oP '(?<=cert=\/etc\/letsencrypt\/live\/)[^/]+')
#         echo -e "${COLOR_SUCC}检测到 Gost 使用的域名: $gost_domain${COLOR_NONE}"
#     else
#         echo -e "${COLOR_ERROR}未检测到 Gost 容器${COLOR_NONE}"
#         gost_domain=""
#     fi

#     # 停止并移除容器
#     for container in gost ss vpn; do
#         if sudo docker ps -a --format '{{.Names}}' | grep -q $container; then
#             sudo docker stop $container
#             sudo docker rm $container
#             echo -e "${COLOR_SUCC}成功停止并移除容器 $container${COLOR_NONE}"
#         else
#             echo -e "${COLOR_ERROR}容器 $container 未找到${COLOR_NONE}"
#         fi
#     done


#     # 卸载 Docker
#     if [ -x "$(command -v docker)" ]; then
#         sudo systemctl stop docker
#         sudo apt-get purge -y docker-ce
#         sudo apt-get autoremove -y --purge docker-ce
#         sudo rm -rf /var/lib/docker
#         sudo rm -rf /etc/docker
#         sudo rm /etc/apparmor.d/docker
#         sudo groupdel docker
#         sudo rm -rf /var/run/docker.sock
#         sudo rm -rf /usr/bin/docker
#         echo -e "${COLOR_SUCC}Docker 已卸载${COLOR_NONE}"
#     else
#         echo -e "${COLOR_ERROR}Docker 未安装${COLOR_NONE}"
#     fi

#     # 卸载 Certbot 并删除证书文件
#     if [ -x "$(command -v certbot)" ]; then
#         if [ -n "$gost_domain" ]; then
#             domain=$gost_domain
#         else
#             echo "请输入要删除证书的域名:"
#             read -r domain
#         fi
        
#         sudo apt-get purge -y certbot
#         sudo apt-get autoremove -y --purge certbot

#         sudo rm -rf /etc/letsencrypt/live/$domain
#         sudo rm -rf /etc/letsencrypt/archive/$domain
#         sudo rm -rf /etc/letsencrypt/renewal/$domain.conf
        
#         crontab -l 2>/dev/null | grep -v "/usr/bin/certbot renew --force-renewal" | crontab -

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
