#!/bin/bash

# Author  https://github.com/go-gost/gost
# Ubuntu 系统环境 安装 Gost HTTP/2 的V3版本 代理服务脚本

COLOR_ERROR="\e[38;5;198m"
COLOR_NONE="\e[0m"
COLOR_SUCC="\e[92m"

# Set the desired GitHub repository,使用最新的gost正式发布版本
repo="go-gost/gost"
base_url="https://api.github.com/repos/$repo/releases/latest"

update_core(){
    echo -e "${COLOR_ERROR}当前系统内核版本太低 <$VERSION_CURR>,需要更新系统内核.${COLOR_NONE}"
    sudo apt install -y -qq --install-recommends linux-generic-hwe-18.04
    sudo apt autoremove

    echo -e "${COLOR_SUCC}内核更新完成,重新启动机器...${COLOR_NONE}"
    sudo reboot
}

check_bbr(){
    has_bbr=$(lsmod | grep bbr)

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
    if [[ $VERSION_CURR > $VERSION_MIN ]]; then
        check_bbr
    else
        update_core
    fi
}

## 使用apt安装方法来获取最新版本
install_certbot() {
    echo "开始安装 certbot 命令行工具"
    sudo apt update -qq
    sudo apt-get install -y certbot
    echo "certbot 命令行工具安装成功"
}

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

# Function to download and install gost
download_install_gost_v3_service() {
    versions=$(curl -s "$base_url" | grep -oP 'tag_name": "\K[^"]+')
    latest_version=$(echo "$versions" | head -n 1)
    echo "Downloading gost version $latest_version..."

    version=$latest_version
    # Detect the operating system
    if [[ "$(uname)" == "Linux" ]]; then
        os="linux"
    elif [[ "$(uname)" == "Darwin" ]]; then
        os="darwin"
    elif [[ "$(uname)" == "MINGW"* ]]; then
        os="windows"
    else
        echo "${COLOR_ERROR}Unsupported operating system.${COLOR_NONE}"
        exit 1
    fi

    # Detect the CPU architecture
    arch=$(uname -m)
    case $arch in
    x86_64)
        cpu_arch="amd64"
        ;;
    armv5*)
        cpu_arch="armv5"
        ;;
    armv6*)
        cpu_arch="armv6"
        ;;
    armv7*)
        cpu_arch="armv7"
        ;;
    aarch64)
        cpu_arch="arm64"
        ;;
    i686)
        cpu_arch="386"
        ;;
    mips64*)
        cpu_arch="mips64"
        ;;
    mips*)
        cpu_arch="mips"
        ;;
    mipsel*)
        cpu_arch="mipsle"
        ;;
    *)
        echo -e "${COLOR_ERROR}Unsupported CPU architecture.${COLOR_NONE}"
        exit 1
        ;;
    esac
    # get_download_url="$base_url/tags/$version"
    # download_url=$(curl -s "$get_download_url" | grep -Eo "\"browser_download_url\": \".*${os}.*${cpu_arch}.*\"" | head -n 1 | awk -F'["]' '{print $4}')

    download_url=$(curl -s "$base_url" | grep -Eo "\"browser_download_url\": \".*${os}.*${cpu_arch}.*\"" | head -n 1 | awk -F'["]' '{print $4}')

    if [[ -z "$download_url" ]]; then 
        echo -e "${COLOR_ERROR}Failed to find the download URL for gost version $version.${COLOR_NONE}"
        exit 1 
    fi

    # Download the binary
    echo "Downloading gost $version from $download_url..."
    sudo curl -fsSL -o gost.tar.gz "$download_url"

    if [[ $? -ne 0 ]]; then
        echo "Failed to download gost. Please check your network connection and the version number."
        exit 1
    fi

    echo -e "${COLOR_SUCC}Installing gost...${COLOR_NONE}"
    # Create a directory for extraction,Extract and install the binary
    sudo mkdir -p gost_file
    sudo tar -xzf gost.tar.gz -C gost_file
    sudo chmod +x gost_file/gost
    sudo mv gost_file/gost /usr/local/bin/gost

    # Clean up
    sudo rm -rf gost_file
    sudo rm -f gost.tar.gz

    echo -e "${COLOR_SUCC}Gost installation completed!${COLOR_NONE}"
}

install_gost() {
    # 经过测试，该命令行需要切换到root权限下才能执行，需要继续调整测试。
    # sudo bash <(curl -fsSL https://github.com/go-gost/gost/raw/master/install.sh) --install
    # 替换成如下的安装执行脚本，需要和https://github.com/go-gost/gost/raw/master/install.sh这个路径进行比较，
    # 万一后续上游被修改了，可能需要根据最新的修改，调整download_install_gost_v3_service这个函数
    echo "开始安装 Gost"
    download_install_gost_v3_service #--install

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
    CERT_DIR=/etc/letsencrypt
    CERT=${CERT_DIR}/live/${DOMAIN}/fullchain.pem
    KEY=${CERT_DIR}/live/${DOMAIN}/privkey.pem

    configure_gost_service "${USER}" "${PASS}" "${BIND_IP}" "${PORT}" "${CERT}" "${KEY}"
    echo "${COLOR_SUCC}gost服务已经成功安装！${COLOR_NONE}"
}

# 为了确保 Gost 服务在崩溃后能够自动重启，可以使用 systemd 来管理 Gost 服务，创建一个守护进程
configure_gost_service() {
    USER=$1
    PASS=$2
    BIND_IP=$3
    PORT=$4
    CERT=$5
    KEY=$6

    sudo tee /etc/systemd/system/gost.service > /dev/null <<EOL
[Unit]
Description=Gost Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/gost -L=http2://${USER}:${PASS}@${BIND_IP}:${PORT}?cert=${CERT}&key=${KEY}&probe_resist=code:400&knock=www.google.com
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOL

    sudo systemctl daemon-reload
    sudo systemctl start gost
    sudo systemctl enable gost
}

crontab_exists() {
    sudo crontab -l 2>/dev/null | grep "$1" >/dev/null 2>/dev/null
}

create_cron_job(){
    # 写入前先检查，避免重复任务。
    if ! crontab_exists "certbot renew --force-renewal"; then
        (sudo crontab -l 2>/dev/null; echo "0 0 1 * * /usr/bin/certbot renew --force-renewal") | sudo crontab -
        echo "${COLOR_SUCC}成功安装证书renew定时作业！${COLOR_NONE}"
    else
        echo "${COLOR_SUCC}证书renew定时作业已经安装过！${COLOR_NONE}"
    fi

    # Cron Job 将每周一凌晨1点定时重启 Gost 系统服务
    if ! crontab_exists "systemctl restart gost"; then
        (sudo crontab -l 2>/dev/null; echo "0 1 * * 1 /usr/bin/systemctl restart gost") | sudo crontab -
        echo "${COLOR_SUCC}成功安装gost更新证书定时作业！${COLOR_NONE}"
    else
        echo "${COLOR_SUCC}gost更新证书定时作业已经成功安装过！${COLOR_NONE}"
    fi
}

uninstall_services() {
    echo "开始卸载服务..."

    # 检测并获取 Gost 服务的域名
    if pgrep gost > /dev/null; then
        gost_command=$(pgrep -a gost | grep -oP '(?<=cert=/etc/letsencrypt/live/)[^ ]+')
        if [ -n "$gost_command" ]; then
            gost_domain=$(echo "$gost_command" | awk -F'/' '{print $1}')
            echo -e "${COLOR_SUCC}检测到 Gost 使用的域名: $gost_domain${COLOR_NONE}"
        else
            echo -e "${COLOR_ERROR}未检测到 Gost 服务的域名${COLOR_NONE}"
            gost_domain=""
        fi
    else
        echo -e "${COLOR_ERROR}未检测到 Gost 服务${COLOR_NONE}"
        gost_domain=""
    fi

    # 停止并卸载 Gost 服务
    sudo systemctl stop gost
    sudo systemctl disable gost
    sudo rm -f /etc/systemd/system/gost.service
    sudo systemctl daemon-reload
    sudo systemctl reset-failed

    # 卸载 Gost
    sudo rm -rf /usr/local/bin/gost
    echo -e "${COLOR_SUCC}Gost 已卸载${COLOR_NONE}"

    # 卸载 Certbot 并删除证书文件
    if [ -x "$(command -v certbot)" ]; then
        if [ -n "$gost_domain" ]; then
            domain=$gost_domain
        else
            echo "请输入要删除证书的域名:"
            read -r domain
        fi

        sudo apt-get purge -y certbot
        sudo apt-get autoremove -y --purge certbot

        sudo rm -rf /etc/letsencrypt/live/$domain
        sudo rm -rf /etc/letsencrypt/archive/$domain
        sudo rm -rf /etc/letsencrypt/renewal/$domain.conf

        sudo crontab -l 2>/dev/null | grep -v "/usr/bin/certbot renew --force-renewal" | sudo crontab -

        echo -e "${COLOR_SUCC}Certbot 和 SSL 证书已删除${COLOR_NONE}"
    else
        echo -e "${COLOR_ERROR}Certbot 未安装${COLOR_NONE}"
    fi

    # 删除 Cron Jobs
    sudo crontab -l 2>/dev/null | grep -v "/usr/bin/certbot renew --force-renewal" | sudo crontab -
    sudo crontab -l 2>/dev/null | grep -v "/usr/bin/systemctl restart gost" | sudo crontab -
    echo -e "${COLOR_SUCC}Cron Jobs 已删除${COLOR_NONE}"

    echo -e "${COLOR_SUCC}所有操作已完成，即将重启系统...${COLOR_NONE}" 
    sudo reboot
}

# 函数：检查并启用UFW防火墙，放行指定端口并防止端口被占用
setup_ports_allows() {
    local ports=(80 22 443 8443)

    # 检查是否安装ufw，如果没有安装，则安装
    if ! command -v ufw &> /dev/null; then
        echo -e "${COLOR_ERROR}检测到未安装 ufw，开始安装...${COLOR_NONE}"
        sudo apt update
        sudo apt install -y ufw
    fi

    echo -e "${COLOR_SUCC}检查并启用 UFW 防火墙${COLOR_NONE}"
    sudo ufw status || sudo ufw enable

    echo -e "${COLOR_SUCC}放行以下端口: ${ports[@]}${COLOR_NONE}"

    for port in "${ports[@]}"; do
        sudo ufw allow ${port}/tcp
    done

    echo -e "${COLOR_SUCC}重新加载 UFW 规则${COLOR_NONE}"
    sudo ufw reload

    echo -e "${COLOR_SUCC}查看现有 UFW 规则${COLOR_NONE}"
    sudo ufw status verbose

    echo -e "${COLOR_SUCC}检查端口是否被占用${COLOR_NONE}"
    for port in "${ports[@]}"; do
        if sudo lsof -i TCP:${port}; then
            echo -e "${COLOR_ERROR}注意：端口 ${port} 已被占用!${COLOR_NONE}"
        else
            echo -e "${COLOR_SUCC}端口 ${port} 可用${COLOR_NONE}"
        fi
    done
}

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
                    "配置安装必须的端口放行(443等)" \
                    "创建 SSL 证书" \
                    "安装 Gost HTTP/2 代理服务" \
                    "创建证书更新 CronJob" \
                    "卸载所有服务" \
                    "退出" ; do

            if ! [[ $REPLY =~ $re ]] ; then
                echo -e "${COLOR_ERROR}Invalid option. Please input a number between 0 and 6.${COLOR_NONE}"
                break;
            elif (( REPLY == 1 )) ; then
                install_bbr
                break
            elif (( REPLY == 2 )) ; then
                setup_ports_allows
                break
            elif (( REPLY == 3 )) ; then
                create_cert
                break
            elif (( REPLY == 4 )); then
                install_gost
                break
            elif (( REPLY == 5 )); then
                create_cron_job
                break
            elif (( REPLY == 6 )); then
                uninstall_services
                break
            elif (( REPLY == 0 )); then
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
