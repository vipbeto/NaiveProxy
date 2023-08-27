#!/bin/bash

export LANG=en_US.UTF-8

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

red(){
    echo -e "\033[31m\033[01m$1\033[0m"
}

green(){
    echo -e "\033[32m\033[01m$1\033[0m"
}

yellow(){
    echo -e "\033[33m\033[01m$1\033[0m"
}

# Check system and define package management commands
REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora")
PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "yum -y install")
PACKAGE_REMOVE=("apt -y remove" "apt -y remove" "yum -y remove" "yum -y remove" "yum -y remove")
PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "yum -y autoremove" "yum -y autoremove")

[[ $EUID -ne 0 ]] && red "Note: Please run the script as root user" && exit 1

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
done

[[ -z $SYSTEM ]] && red "Your VPS operating system is currently not supported!  " && exit 1

if [[ -z $(type -P curl) ]]; then
    if [[ ! $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_UPDATE[int]}
    fi
    ${PACKAGE_INSTALL[int]} curl
fi

archAffix(){
    case "$(uname -m)" in
        x86_64 | amd64 ) echo 'amd64' ;;
        armv8 | arm64 | aarch64 ) echo 'arm64' ;;
        s390x ) echo 's390x' ;;
        * ) red "不支持的CPU架构!" && exit 1 ;;
    esac
}

installProxy(){
    if [[ ! $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_UPDATE[int]}
    fi
    ${PACKAGE_INSTALL[int]} curl wget sudo qrencode

    rm -f /usr/bin/caddy
    wget https://raw.githubusercontent.com/Misaka-blog/naiveproxy-script/main/files/caddy-linux-$(archAffix) -O /usr/bin/caddy
    chmod +x /usr/bin/caddy

    mkdir /etc/caddy
    
    read -rp "Enter the port  [Press Enter for random port]:  " proxyport
    [[ -z $proxyport ]] && proxyport=$(shuf -i 2000-65535 -n 1)
    until [[ -z $(ss -ntlp | awk '{print $4}' | sed 's/.*://g' | grep -w "$proxyport") ]]; do
        if [[ -n $(ss -ntlp | awk '{print $4}' | sed 's/.*://g' | grep -w "$proxyport") ]]; then
            echo -e "${RED} $proxyport ${PLAIN} The port is already occupied by another program，Please change the port and try again!"
            read -rp "Enter the port  [Press Enter for random port]:" proxyport
            [[ -z $proxyport ]] && proxyport=$(shuf -i 2000-65535 -n 1)
        fi
    done
    yellow "Port : $proxyport"

    read -rp "Enter port for Caddy listening [Press Enter for random port]:" caddyport
    [[ -z $caddyport ]] && caddyport=$(shuf -i 2000-65535 -n 1)
    until [[ -z $(ss -ntlp | awk '{print $4}' | sed 's/.*://g' | grep -w "$caddyport") ]]; do
        if [[ -n $(ss -ntlp | awk '{print $4}' | sed 's/.*://g' | grep -w "$caddyport") ]]; then
            echo -e "${RED} Port $caddyport ${PLAIN} is already in use by another program. Please try a different port!"
            read -rp "Enter the port  for Caddy listening [Press Enter for random port]:" caddyport
            [[ -z $caddyport ]] && caddyport=$(shuf -i 2000-65535 -n 1)
        fi
    done
    yellow "Port  for Caddy listening: $caddyport"
    
    read -rp "Enter your domain name :" domain
    yellow "Domain : $domain"

    read -rp "Enter the username  [Press Enter for random generation]:" proxyname
    [[ -z $proxyname ]] && proxyname=$(date +%s%N | md5sum | cut -c 1-16)
    yellow "Username : $proxyname"

    read -rp "Enter the password  [Press Enter for random generation]:" proxypwd
    [[ -z $proxypwd ]] && proxypwd=$(date +%s%N | md5sum | cut -c 1-16)
    yellow "Password : $proxypwd"

    read -rp "Enter the fake website address  (without https://) [Press Enter for maimai.sega.jp]:" proxysite
    [[ -z $proxysite ]] && proxysite="maimai.sega.jp"
    yellow "Fake website address : $proxysite"
    
    cat << EOF >/etc/caddy/Caddyfile
{
http_port $caddyport
}
:$proxyport, $domain:$proxyport
tls admin@seewo.com
route {
 forward_proxy {
   basic_auth $proxyname $proxypwd
   hide_ip
   hide_via
   probe_resistance
  }
 reverse_proxy  https://$proxysite  {
   header_up  Host  {upstream_hostport}
   header_up  X-Forwarded-Host  {host}
  }
}
EOF

    mkdir /root/naive
    cat <<EOF > /root/naive/naive-client.json
{
  "listen": "socks://127.0.0.1:4080",
  "proxy": "https://${proxyname}:${proxypwd}@${domain}:${proxyport}",
  "log": ""
}
EOF
    url="naive+https://${proxyname}:${proxypwd}@${domain}:${proxyport}?padding=true#Peyman-Naive"
    echo $url > /root/naive/naive-url.txt
    
    cat << EOF >/etc/systemd/system/caddy.service
[Unit]
Description=Caddy
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
User=root
Group=root
ExecStart=/usr/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/bin/caddy reload --config /etc/caddy/Caddyfile
TimeoutStopSec=5s
PrivateTmp=true
ProtectSystem=full

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable caddy
    systemctl start caddy

    green "NaiveProxy has been successfully installed!"
    showconf
}

uninstallProxy(){
    systemctl stop caddy
    rm -rf /etc/caddy /root/naive
    rm -f /usr/bin/caddy
    green "NaiveProxy has been completely uninstalled!"
}

startProxy(){
    systemctl enable caddy
    systemctl start caddy
    green "NaiveProxy has been started successfully!"
}

stopProxy(){
    systemctl disable caddy
    systemctl stop caddy
    green "NaiveProxy has been stopped successfully!"
}

reloadProxy(){
    systemctl restart caddy
    green "NaiveProxy has been restarted successfully!"
}

changeport(){
    oldport=$(cat /etc/caddy/Caddyfile | sed -n 4p | awk '{print $1}' | sed "s/://g" | sed "s/,//g")
    read -rp "Please enter the port  [Enter , for random port]：" proxyport
    [[ -z $proxyport ]] && proxyport=$(shuf -i 2000-65535 -n 1)
    
    until [[ -z $(ss -ntlp | awk '{print $4}' | sed 's/.*://g' | grep -w "$proxyport") ]]; do
        if [[ -n $(ss -ntlp | awk '{print $4}' | sed 's/.*://g' | grep -w "$proxyport") ]]; then
            echo -e "${RED} $proxyport ${PLAIN} port is already occupied by other programs, please change the port and try again！"
            read -rp "Please enter the port  [Enter , for random port]：" proxyport
            [[ -z $proxyport ]] && proxyport=$(shuf -i 2000-65535 -n 1)
        fi
    done

    sed -i "s#$oldport#$proxyport#g" /etc/caddy/Caddyfile
    sed -i "s#$oldport#$proxyport#g" /root/naive/naive-client.json
    sed -i "s#$oldport#$proxyport#g" /root/naive/naive-url.txt

    reloadProxy

    green "NaiveProxy node port successfully modified to:  $port"
    yellow "Please manually update the client configuration file to use node"
    showconf
}


changedomain(){
    olddomain=$(cat /etc/caddy/Caddyfile | sed -n 4p | awk '{print $2}')
    read -rp "Please enter your domain name ：" domain

    sed -i "s#$olddomain#$domain#g" /etc/caddy/Caddyfile
    sed -i "s#$olddomain#$domain#g" /root/naive/naive-client.json
    sed -i "s#$olddomain#$domain#g" /root/naive/naive-url.txt

    reloadProxy

    green "The NaiveProxy node domain name has been successfully changed to：$domain"
    yellow "Please update the client configuration file manually to use node"
    showconf
}

changeusername(){
    oldproxyname=$(cat /etc/caddy/Caddyfile | grep "basic_auth" | awk '{print $2}')
    read -rp "Please enter the username [Enter to generate randomly]：" proxyname
    [[ -z $proxyname ]] && proxyname=$(date +%s%N | md5sum | cut -c 1-16)

    sed -i "s#$oldproxyname#$proxyname#g" /etc/caddy/Caddyfile
    sed -i "s#$oldproxyname#$proxyname#g" /root/naive/naive-client.json
    sed -i "s#$oldproxyname#$proxyname#g" /root/naive/naive-url.txt

    reloadProxy

    green "The NaiveProxy node username has been successfully modified to：$proxyname"
    yellow "Please update the client configuration file manually to use node"
    showconf
}

changepassword(){
    oldproxypwd=$(cat /etc/caddy/Caddyfile | grep "basic_auth" | awk '{print $3}')
    read -rp "Please enter the password [Enter to generate randomly]：" proxypwd
    [[ -z $proxypwd ]] && proxypwd=$(date +%s%N | md5sum | cut -c 1-16)

    sed -i "s#$oldproxypwd#$proxypwd#g" /etc/caddy/Caddyfile
    sed -i "s#$oldproxypwd#$proxypwd#g" /root/naive/naive-client.json
    sed -i "s#$oldproxypwd#$proxypwd#g" /root/naive/naive-url.txt

    reloadProxy

    green "NaiveProxy node password successfully changed to：$proxypwd"
    yellow "Please manually update the client configuration file to use node"
    showconf
}

changeproxysite(){
    oldproxysite=$(cat /etc/caddy/Caddyfile | grep "reverse_proxy" | awk '{print $2}' | sed "s/https:\/\///g")
    read -rp "Please enter disguised website address  remove https://  [Enter Sega maimai Japan website]：" proxysite
    [[ -z $proxysite ]] && proxysite="maimai.sega.jp"

    sed -i "s#$oldproxysite#$proxysite#g" /etc/caddy/Caddyfile

    reloadProxy

    green "NaiveProxy 节点伪装网站已成功修改为：$proxysite"
}

modifyConfig(){
    green "The NaiveProxy configuration change options are as follows:"
    echo -e " ${GREEN}1.${PLAIN} Change port"
    echo -e " ${GREEN}2.${PLAIN} Change domain"
    echo -e " ${GREEN}3.${PLAIN} Change username"
    echo -e " ${GREEN}4.${PLAIN} change Password"
    echo -e " ${GREEN}5.${PLAIN} Change disguised station address"
    echo ""
    read -p " Please select an action [1-5]：" confAnswer
    case $confAnswer in
        1 ) changeport ;;
        2 ) changedomain ;;
        3 ) changeusername ;;
        4 ) changepassword ;;
        5 ) changeproxysite ;;
        * ) exit 1 ;;
    esac
}

showconf(){
    echo "----------------t.me/P_tech2024---------------------------------------------------"
    yellow "The client configuration file saved to /root/naive/naive-client.json"
    yellow "Qv2ray / SagerNet / Matsuri Share link saved to /root/naive/naive-url.txt"
    yellow "SagerNet / Matsuri shared the QR code: "
    qrencode -o - -t ANSIUTF8 "$(cat /root/naive/naive-url.txt)"
    echo -e "Your config  :\n  $(yellow $(cat /root/naive/naive-url.txt))"
    echo "------------------------------------------------------------------------------------------------"
}

menu(){
    clear
    echo "###########################################################"
    echo -e "#       ${RED}NaiveProxy 一one-click installation script${PLAIN}      #"
    echo -e "# ${GREEN}Gihub ${PLAIN}: https://gitlab.com/Ptechgithub               #"
    echo -e "# ${GREEN}Telegram ${PLAIN}: https://t.me/P_tech2024                       #"
    echo -e "# ${GREEN}YouTube ${PLAIN}: https://www.youtube.com/@IR_TECH              #"
    echo "###########################################################"
    echo ""
    echo -e  " ${GREEN}1.${PLAIN} Install NaiveProxy"
    echo -e " ${GREEN}2.${PLAIN} ${RED}Uninstall NaiveProxy${PLAIN}"
    echo "-------------"
    echo -e " ${GREEN}3.${PLAIN} start NaiveProxy"
    echo -e " ${GREEN}4.${PLAIN} stop NaiveProxy"
    echo -e " ${GREEN}5.${PLAIN} overload NaiveProxy"
    echo "-------------"
    echo -e " ${GREEN}6.${PLAIN} modify NaiveProxy configuration"
    echo -e " ${GREEN}7.${PLAIN} view NaiveProxy configuration"
    echo "-------------"
    echo -e " ${GREEN}0.${PLAIN} exit"
    echo ""
    read -rp "Please enter options [0-6]:  " answer
    case $answer in
        1) installProxy;;
        2) uninstallProxy;;
        3) startProxy;;
        4) stopProxy;;
        5) reloadProxy;;
        6) modifyConfig;;
        *) red "Please enter the correct option [0-6]!  " && exit 1 ;;
    esac
}

menu
