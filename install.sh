#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

[[ $EUID -ne 0 ]] && echo -e "${red}Fatal:${plain} This script must be run as root.\n " && exit 1

if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo "Unable to detect OS. Please report this issue." >&2
    exit 1
fi
echo "Detected distribution: $release"

arch() {
    case "$(uname -m)" in
    x86_64 | x64 | amd64) echo 'amd64' ;;
    i*86 | x86) echo '386' ;;
    armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
    armv7* | armv7 | arm) echo 'armv7' ;;
    armv6* | armv6) echo 'armv6' ;;
    armv5* | armv5) echo 'armv5' ;;
    s390x) echo 's390x' ;;
    *) echo -e "${green}Unsupported CPU architecture.${plain}" && rm -f install.sh && exit 1 ;;
    esac
}

echo "Architecture: $(arch)"

install_base() {
    case "${release}" in
    centos | almalinux | rocky | oracle)
        yum -y update && yum install -y -q wget curl tar tzdata
        ;;
    fedora)
        dnf -y update && dnf install -y -q wget curl tar tzdata
        ;;
    arch | manjaro | parch)
        pacman -Syu && pacman -Syu --noconfirm wget curl tar tzdata
        ;;
    opensuse-tumbleweed)
        zypper refresh && zypper -q install -y wget curl tar timezone
        ;;
    *)
        apt-get update && apt-get install -y -q wget curl tar tzdata
        ;;
    esac
}

config_after_install() {
    echo -e "${yellow}Running database migrations...${plain}"
    /usr/local/s-ui/sui migrate

    echo -e "${yellow}Installation / upgrade finished. For security, review panel settings.${plain}"
    read -p "Configure settings now? [y/N]: " config_confirm
    if [[ "${config_confirm}" == "y" || "${config_confirm}" == "Y" ]]; then
        echo -e "Panel port ${yellow}(leave empty to keep current/default)${plain}:"
        read config_port
        echo -e "Web base path ${yellow}(leave empty to keep current/default)${plain}:"
        read config_path

        echo -e "Subscription port ${yellow}(leave empty to keep current/default)${plain}:"
        read config_subPort
        echo -e "Subscription path ${yellow}(leave empty to keep current/default)${plain}:"
        read config_subPath

        echo -e "${yellow}Applying settings...${plain}"
        params=""
        [ -z "$config_port" ] || params="$params -port $config_port"
        [ -z "$config_path" ] || params="$params -path $config_path"
        [ -z "$config_subPort" ] || params="$params -subPort $config_subPort"
        [ -z "$config_subPath" ] || params="$params -subPath $config_subPath"
        /usr/local/s-ui/sui setting ${params}

        read -p "Change admin username and password now? [y/N]: " admin_confirm
        if [[ "${admin_confirm}" == "y" || "${admin_confirm}" == "Y" ]]; then
            read -p "Admin username: " config_account
            read -p "Admin password: " config_password

            echo -e "${yellow}Applying admin credentials...${plain}"
            /usr/local/s-ui/sui admin -username ${config_account} -password ${config_password}
        else
            echo -e "${yellow}Current admin credentials:${plain}"
            /usr/local/s-ui/sui admin -show
        fi
    else
        echo -e "${red}Skipped interactive configuration.${plain}"
        if [[ ! -f "/usr/local/s-ui/db/s-ui.db" ]]; then
            local usernameTemp=$(head -c 6 /dev/urandom | base64)
            local passwordTemp=$(head -c 6 /dev/urandom | base64)
            echo -e "Fresh install: random admin credentials were generated:"
            echo -e "###############################################"
            echo -e "${green}Username:${plain} ${usernameTemp}"
            echo -e "${green}Password:${plain} ${passwordTemp}"
            echo -e "###############################################"
            echo -e "${red}If you lose these, run ${green}s-ui${red} from the shell for the management menu.${plain}"
            /usr/local/s-ui/sui admin -username ${usernameTemp} -password ${passwordTemp}
        else
            echo -e "${red}Upgrade install: existing settings kept. Use ${green}s-ui${red} if you need to reset credentials.${plain}"
        fi
    fi
}

prepare_services() {
    if [[ -f "/etc/systemd/system/sing-box.service" ]]; then
        echo -e "${yellow}Stopping sing-box...${plain}"
        systemctl stop sing-box
        rm -f /usr/local/s-ui/bin/sing-box /usr/local/s-ui/bin/runSingbox.sh /usr/local/s-ui/bin/signal
    fi
    if [[ -e "/usr/local/s-ui/bin" ]]; then
        echo -e "###############################################################"
        echo -e "${green}/usr/local/s-ui/bin${red} already exists."
        echo -e "Review its contents and remove obsolete binaries after migration if needed.${plain}"
        echo -e "###############################################################"
    fi
    systemctl daemon-reload
}

install_s-ui() {
    cd /tmp/

    if [ $# == 0 ]; then
        last_version=$(curl -Ls "https://api.github.com/repos/callmeAsghar/s-ui-plus/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}Failed to resolve latest release (GitHub API rate limit or network). Retry later.${plain}"
            exit 1
        fi
        echo -e "Latest release: ${last_version}. Downloading..."
        wget -N --no-check-certificate -O /tmp/s-ui-linux-$(arch).tar.gz "https://github.com/callmeAsghar/s-ui-plus/releases/download/${last_version}/s-ui-linux-$(arch).tar.gz"
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Download failed. Check connectivity to GitHub.${plain}"
            exit 1
        fi
    else
        last_version=$1
        [[ "${last_version}" != v* ]] && last_version="v${last_version}"
        url="https://github.com/callmeAsghar/s-ui-plus/releases/download/${last_version}/s-ui-linux-$(arch).tar.gz"
        echo -e "Installing s-ui-plus ${last_version}"
        wget -N --no-check-certificate -O /tmp/s-ui-linux-$(arch).tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Download failed for ${last_version}. Verify the tag exists.${plain}"
            exit 1
        fi
    fi

    if [[ -e /usr/local/s-ui/ ]]; then
        systemctl stop s-ui
    fi

    tar zxvf s-ui-linux-$(arch).tar.gz
    rm -f s-ui-linux-$(arch).tar.gz

    chmod +x s-ui/sui s-ui/s-ui.sh
    cp s-ui/s-ui.sh /usr/bin/s-ui
    cp -rf s-ui /usr/local/
    cp -f s-ui/*.service /etc/systemd/system/
    rm -rf s-ui

    config_after_install
    prepare_services

    systemctl enable s-ui --now

    echo -e "${green}s-ui-plus ${last_version}${plain} installed and started."
    echo -e "Panel URL:${green}"
    /usr/local/s-ui/sui uri
    echo -e "${plain}"
    echo ""
    s-ui help
}

echo -e "${green}Starting installation...${plain}"
install_base
install_s-ui $1
