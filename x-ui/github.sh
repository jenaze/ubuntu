#!/bin/bash

# ==================================================
# X-UI Installer (Merged & Fixed)
# Argument Order: 1. Password | 2. Version (Optional)
# Features: Auto-Latest, BBR, OS Optimization
# ==================================================

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

xui_folder="${XUI_MAIN_FOLDER:=/usr/local/x-ui}"
xui_service="${XUI_SERVICE:=/etc/systemd/system}"

# 1. Check Root
[[ $EUID -ne 0 ]] && echo -e "${red}Fatal error: ${plain} Please run this script with root privilege \n " && exit 1

# 2. Check OS
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo "Failed to check the system OS, please contact the author!" >&2
    exit 1
fi
echo "The OS release is: $release"

# 3. Check Architecture
arch() {
    case "$(uname -m)" in
        x86_64 | x64 | amd64) echo 'amd64' ;;
        i*86 | x86) echo '386' ;;
        armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
        armv7* | armv7 | arm) echo 'armv7' ;;
        armv6* | armv6) echo 'armv6' ;;
        armv5* | armv5) echo 'armv5' ;;
        s390x) echo 's390x' ;;
        *) echo -e "${green}Unsupported CPU architecture! ${plain}" && rm -f install.sh && exit 1 ;;
    esac
}

echo "Arch: $(arch)"

# 4. Install Dependencies
install_base() {
    case "${release}" in
        ubuntu | debian | armbian)
            apt-get update && apt-get install -y -q curl tar tzdata socat ca-certificates wget
        ;;
        fedora | amzn | virtuozzo | rhel | almalinux | rocky | ol)
            dnf -y update && dnf install -y -q curl tar tzdata socat ca-certificates wget
        ;;
        centos)
            if [[ "${VERSION_ID}" =~ ^7 ]]; then
                yum -y update && yum install -y curl tar tzdata socat ca-certificates wget
            else
                dnf -y update && dnf install -y -q curl tar tzdata socat ca-certificates wget
            fi
        ;;
        arch | manjaro | parch)
            pacman -Syu && pacman -Syu --noconfirm curl tar tzdata socat ca-certificates wget
        ;;
        opensuse-tumbleweed | opensuse-leap)
            zypper refresh && zypper -q install -y curl tar timezone socat ca-certificates wget
        ;;
        alpine)
            apk update && apk add curl tar tzdata socat ca-certificates wget
        ;;
        *)
            apt-get update && apt-get install -y -q curl tar tzdata socat ca-certificates wget
        ;;
    esac
}

# 5. BBR Function
enable_bbr() {
    echo -e "${green}Checking BBR Status...${plain}"
    if grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf && grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        echo -e "${green}BBR is already enabled!${plain}"
    else
        echo -e "${yellow}Enabling BBR...${plain}"
        echo "net.core.default_qdisc=fq" | tee -a /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" | tee -a /etc/sysctl.conf
        sysctl -p
        
        if [[ $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}') == "bbr" ]]; then
            echo -e "${green}BBR has been enabled successfully.${plain}"
        else
            echo -e "${red}Failed to enable BBR.${plain}"
        fi
    fi
}

# 6. Optimization Function
optimizing_system(){
    echo -e "${green}Optimizing System Parameters...${plain}"
    sed -i '/fs.file-max/d' /etc/sysctl.conf
    sed -i '/fs.inotify.max_user_instances/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_tw_reuse/d' /etc/sysctl.conf
    sed -i '/net.ipv4.ip_local_port_range/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_rmem/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_wmem/d' /etc/sysctl.conf
    sed -i '/net.core.somaxconn/d' /etc/sysctl.conf
    sed -i '/net.core.rmem_max/d' /etc/sysctl.conf
    sed -i '/net.core.wmem_max/d' /etc/sysctl.conf
    sed -i '/net.core.wmem_default/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_max_tw_buckets/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_max_syn_backlog/d' /etc/sysctl.conf
    sed -i '/net.core.netdev_max_backlog/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_slow_start_after_idle/d' /etc/sysctl.conf
    sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
    
    echo "fs.file-max = 1000000
fs.inotify.max_user_instances = 8192
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_rmem = 16384 262144 8388608
net.ipv4.tcp_wmem = 32768 524288 16777216
net.core.somaxconn = 8192
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.wmem_default = 2097152
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_max_syn_backlog = 10240
net.core.netdev_max_backlog = 10240
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.ip_forward = 1" >> /etc/sysctl.conf

    sysctl -p
    
    echo "* soft    nofile           1000000
* hard    nofile          1000000" > /etc/security/limits.conf
    
    echo "ulimit -SHn 1000000" >> /etc/profile
    echo -e "${green}System Optimization Applied.${plain}"
}

# 7. Configuration Function
config_after_install() {
    local input_password="$1"
    
    # Defaults
    local config_username="admin"
    local config_port=8080
    local config_password="${input_password:-admin}"

    echo -e "${yellow}------------------------------------------${plain}"
    echo -e "${yellow}Configuring Panel...${plain}"
    echo -e "Username: ${green}${config_username}${plain}"
    echo -e "Password: ${green}${config_password}${plain}"
    echo -e "Port:     ${green}${config_port}${plain}"
    echo -e "${yellow}------------------------------------------${plain}"

    # Apply settings using the installed binary
    ${xui_folder}/x-ui setting -username "${config_username}" -password "${config_password}" -resetTwoFactor true
    ${xui_folder}/x-ui setting -port "${config_port}"
    
    # Migrate DB
    ${xui_folder}/x-ui migrate
}

# 8. Main Installation Function
install_x-ui() {
    local password_arg="$1"
    local version_arg="$2"

    cd ${xui_folder%/x-ui}/
    
    # A. Download Logic
    if [[ -z "$version_arg" ]]; then
        # If version arg is empty, fetch LATEST
        echo -e "${yellow}No version specified, fetching latest version...${plain}"
        tag_version=$(curl -Ls "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$tag_version" ]]; then
            # Retry with IPv4
            tag_version=$(curl -4 -Ls "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
            if [[ ! -n "$tag_version" ]]; then
                echo -e "${red}Failed to fetch x-ui version.${plain}"
                exit 1
            fi
        fi
        echo -e "Got x-ui latest version: ${tag_version}"
        curl -4fLRo ${xui_folder}-linux-$(arch).tar.gz https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz
    else
        # If version arg is provided, use IT
        tag_version=$version_arg
        # Check version format
        if [[ $tag_version != v* ]]; then
             tag_version="v${tag_version}"
        fi
        url="https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz"
        echo -e "Installing x-ui version: $tag_version"
        curl -4fLRo ${xui_folder}-linux-$(arch).tar.gz ${url}
    fi
    
    if [[ $? -ne 0 ]]; then
        echo -e "${red}Downloading x-ui failed! Please check connection/version.${plain}"
        exit 1
    fi

    # B. Download Script Helper
    curl -4fLRo /usr/bin/x-ui-temp https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.sh
    if [[ $? -ne 0 ]]; then
        echo -e "${red}Failed to download x-ui.sh${plain}"
        exit 1
    fi
    
    # C. Stop existing service and clean folder
    if [[ -e ${xui_folder}/ ]]; then
        if [[ $release == "alpine" ]]; then
            rc-service x-ui stop >/dev/null 2>&1
        else
            systemctl stop x-ui >/dev/null 2>&1
        fi
        rm ${xui_folder}/ -rf
    fi
    
    # D. Extract and Permissions
    tar zxvf x-ui-linux-$(arch).tar.gz
    rm x-ui-linux-$(arch).tar.gz -f
    
    cd x-ui
    chmod +x x-ui
    chmod +x x-ui.sh
    
    # Arch fix for ARM
    if [[ $(arch) == "armv5" || $(arch) == "armv6" || $(arch) == "armv7" ]]; then
        mv bin/xray-linux-$(arch) bin/xray-linux-arm
        chmod +x bin/xray-linux-arm
    fi
    chmod +x bin/xray-linux-$(arch)
    
    # Update CLI
    mv -f /usr/bin/x-ui-temp /usr/bin/x-ui
    chmod +x /usr/bin/x-ui
    mkdir -p /var/log/x-ui
    
    # E. Configure (Passing the password)
    config_after_install "$password_arg"

    # F. Etckeeper check
    if [ -d "/etc/.git" ]; then
        if [ -f "/etc/.gitignore" ]; then
            if ! grep -q "x-ui/x-ui.db" "/etc/.gitignore"; then
                echo "" >> "/etc/.gitignore"
                echo "x-ui/x-ui.db" >> "/etc/.gitignore"
            fi
        else
            echo "x-ui/x-ui.db" > "/etc/.gitignore"
        fi
    fi
    
    # G. Service Installation
    if [[ $release == "alpine" ]]; then
        curl -4fLRo /etc/init.d/x-ui https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.rc
        chmod +x /etc/init.d/x-ui
        rc-update add x-ui
        rc-service x-ui start
    else
        # Systemd
        cp -f x-ui.service ${xui_service}/ >/dev/null 2>&1
        # If not in tar, download it
        if [[ ! -f "${xui_service}/x-ui.service" ]]; then
            case "${release}" in
                ubuntu | debian | armbian)
                    curl -4fLRo ${xui_service}/x-ui.service https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.service.debian >/dev/null 2>&1
                ;;
                arch | manjaro | parch)
                    curl -4fLRo ${xui_service}/x-ui.service https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.service.arch >/dev/null 2>&1
                ;;
                *)
                    curl -4fLRo ${xui_service}/x-ui.service https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.service.rhel >/dev/null 2>&1
                ;;
            esac
        fi
        
        systemctl daemon-reload
        systemctl enable x-ui
        systemctl start x-ui
    fi
    
    echo -e "${green}x-ui ${tag_version} installed and running.${plain}"
    echo -e "Control menu: type ${blue}x-ui${plain}"
}

# ================= Execution =================
echo -e "${green}Starting Personalized Installation...${plain}"

# Capture Arguments (SWAPPED)
# $1 = Password
# $2 = Version (Optional - if empty, defaults to latest)
ARG_PASSWORD=$1
ARG_VERSION=$2

# Step 1: Install Dependencies
install_base

# Step 2: Install X-UI (Pass args down)
install_x-ui "$ARG_PASSWORD" "$ARG_VERSION"

# Step 4: Optimization Question (اضافه شده)
echo -e "${yellow}------------------------------------------${plain}"
read -rp "Do you want to Enable BBr? [y/n] " confirm_bbr
if [[ "$confirm_bbr" == "y" || "$confirm_bbr" == "Y" ]]; then
    enable_bbr
else
    echo -e "${blue}System bbr skipped.${plain}"
fi

# Step 4: Optimization Question (اضافه شده)
echo -e "${yellow}------------------------------------------${plain}"
read -rp "Do you want to apply System Optimizations (TCP, ulimit, etc.)? [y/n] " confirm_opt
if [[ "$confirm_opt" == "y" || "$confirm_opt" == "Y" ]]; then
    optimizing_system
else
    echo -e "${blue}System Optimization skipped.${plain}"
fi

# Step 5: Final Prompt
echo -e ""
echo -e "${green}Installation Completed!${plain}"
echo -e "${yellow}Please Reboot your VPS to apply all system changes.${plain}"
read -rp "Reboot now? [y/n] " confirm_reboot
if [[ "$confirm_reboot" == "y" || "$confirm_reboot" == "Y" ]]; then
    reboot
fi
