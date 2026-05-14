#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

function LOGD() {
    echo -e "${yellow}[debug] $* ${plain}"
}

function LOGE() {
    echo -e "${red}[error] $* ${plain}"
}

function LOGI() {
    echo -e "${green}[info] $* ${plain}"
}

[[ $EUID -ne 0 ]] && LOGE "This script must be run as root.\n" && exit 1

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

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -p "$1 [default $2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -p "$1 [y/N]: " temp
    fi
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

confirm_restart() {
    confirm "Restart ${1} service" "y"
    if [[ $? == 0 ]]; then
        restart
    else
        show_menu
    fi
}

before_show_menu() {
    echo && echo -n -e "${yellow}Press Enter to return to the menu...${plain}" && read temp
    show_menu
}

install() {
    bash <(curl -Ls https://raw.githubusercontent.com/callmeAsghar/s-ui-plus/main/install.sh)
    if [[ $? == 0 ]]; then
        if [[ $# == 0 ]]; then
            start
        else
            start 0
        fi
    fi
}

update() {
    confirm "This will reinstall the latest release in place (data is kept). Continue?" "n"
    if [[ $? != 0 ]]; then
        LOGE "Cancelled"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 0
    fi
    bash <(curl -Ls https://raw.githubusercontent.com/callmeAsghar/s-ui-plus/main/install.sh)
    if [[ $? == 0 ]]; then
        LOGI "Update finished; the panel was restarted."
        exit 0
    fi
}

custom_version() {
    echo "Enter release tag (for example v1.4.1):"
    read panel_version

    if [ -z "$panel_version" ]; then
        echo "Version is required. Exiting."
    exit 1
    fi

    [[ "${panel_version}" != v* ]] && panel_version="v${panel_version}"

    download_link="https://raw.githubusercontent.com/callmeAsghar/s-ui-plus/main/install.sh"

    install_command="bash <(curl -Ls $download_link) $panel_version"

    echo "Downloading and installing ${panel_version}..."
    eval $install_command
}

uninstall() {
    confirm "Uninstall the panel? This cannot be undone." "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    systemctl stop s-ui
    systemctl disable s-ui
    rm /etc/systemd/system/s-ui.service -f
    systemctl daemon-reload
    systemctl reset-failed
    rm /etc/s-ui/ -rf
    rm /usr/local/s-ui/ -rf

    echo ""
    echo -e "Uninstall complete. To remove this menu script: ${green}rm -f /usr/bin/s-ui${plain}"
    echo ""

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

reset_admin() {
    echo "Resetting admin to defaults is insecure on production systems."
    confirm "Reset admin username and password to defaults?" "n"
    if [[ $? == 0 ]]; then
        /usr/local/s-ui/sui admin -reset
    fi
    before_show_menu
}

set_admin() {
    echo "Avoid extremely long passwords that are hard to type in recovery scenarios."
    read -p "Admin username: " config_account
    read -p "Admin password: " config_password
    /usr/local/s-ui/sui admin -username ${config_account} -password ${config_password}
    before_show_menu
}

view_admin() {
    /usr/local/s-ui/sui admin -show
    before_show_menu
}

reset_setting() {
    confirm "Reset panel settings to defaults?" "n"
    if [[ $? == 0 ]]; then
        /usr/local/s-ui/sui setting -reset
    fi
    before_show_menu
}

set_setting() {
    echo -e "Panel port ${yellow}(empty = keep current/default)${plain}:"
    read config_port
    echo -e "Web base path ${yellow}(empty = keep current/default)${plain}:"
    read config_path

    echo -e "Subscription port ${yellow}(empty = keep current/default)${plain}:"
    read config_subPort
    echo -e "Subscription path ${yellow}(empty = keep current/default)${plain}:"
    read config_subPath

    echo -e "${yellow}Applying settings...${plain}"
    params=""
    [ -z "$config_port" ] || params="$params -port $config_port"
    [ -z "$config_path" ] || params="$params -path $config_path"
    [ -z "$config_subPort" ] || params="$params -subPort $config_subPort"
    [ -z "$config_subPath" ] || params="$params -subPath $config_subPath"
    /usr/local/s-ui/sui setting ${params}
    before_show_menu
}

view_setting() {
    /usr/local/s-ui/sui setting -show
    view_uri
    before_show_menu
}

view_uri() {
    info=$(/usr/local/s-ui/sui uri)
    if [[ $? != 0 ]]; then
        LOGE "Failed to read panel URI"
        before_show_menu
    fi
    LOGI "Open the panel at:"
    echo -e "${green}${info}${plain}"
}

start() {
    check_status $1
    if [[ $? == 0 ]]; then
        echo ""
        LOGI -e "${1} is already running. Choose restart if you need a fresh start."
    else
        systemctl start $1
        sleep 2
        check_status $1
        if [[ $? == 0 ]]; then
            LOGI "${1} started"
        else
            LOGE "${1} failed to start within 2 seconds; check logs with journalctl"
        fi
    fi

    if [[ $# == 1 ]]; then
        before_show_menu
    fi
}

stop() {
    check_status $1
    if [[ $? == 1 ]]; then
        echo ""
        LOGI "${1} is already stopped."
    else
        systemctl stop $1
        sleep 2
        check_status
        if [[ $? == 1 ]]; then
            LOGI "${1} stopped"
        else
            LOGE "${1} failed to stop within 2 seconds; check logs"
        fi
    fi

    if [[ $# == 1 ]]; then
        before_show_menu
    fi
}

restart() {
    systemctl restart $1
    sleep 2
    check_status $1
    if [[ $? == 0 ]]; then
        LOGI "${1} restarted"
    else
        LOGE "${1} restart may have failed; check logs"
    fi
    if [[ $# == 1 ]]; then
        before_show_menu
    fi
}

status() {
    systemctl status s-ui -l
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

enable() {
    systemctl enable $1
    if [[ $? == 0 ]]; then
        LOGI "${1} enabled on boot"
    else
        LOGE "Failed to enable ${1}"
    fi

    if [[ $# == 1 ]]; then
        before_show_menu
    fi
}

disable() {
    systemctl disable $1
    if [[ $? == 0 ]]; then
        LOGI "${1} disabled on boot"
    else
        LOGE "Failed to disable ${1}"
    fi

    if [[ $# == 1 ]]; then
        before_show_menu
    fi
}

show_log() {
    journalctl -u $1.service -e --no-pager -f
    if [[ $# == 1 ]]; then
        before_show_menu
    fi
}

update_shell() {
    wget -O /usr/bin/s-ui -N --no-check-certificate https://raw.githubusercontent.com/callmeAsghar/s-ui-plus/main/s-ui.sh
    if [[ $? != 0 ]]; then
        echo ""
        LOGE "Failed to download script; check GitHub connectivity"
        before_show_menu
    else
        chmod +x /usr/bin/s-ui
        LOGI "Menu script updated; run s-ui again" && exit 0
    fi
}

check_status() {
    if [[ ! -f "/etc/systemd/system/$1.service" ]]; then
        return 2
    fi
    temp=$(systemctl status "$1" | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ x"${temp}" == x"running" ]]; then
        return 0
    else
        return 1
    fi
}

check_enabled() {
    temp=$(systemctl is-enabled $1)
    if [[ x"${temp}" == x"enabled" ]]; then
        return 0
    else
        return 1
    fi
}

check_uninstall() {
    check_status s-ui
    if [[ $? != 2 ]]; then
        echo ""
        LOGE "Panel is already installed"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

check_install() {
    check_status s-ui
    if [[ $? == 2 ]]; then
        echo ""
        LOGE "Install the panel first"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

show_status() {
    check_status $1
    case $? in
    0)
        echo -e "${1} status: ${green}running${plain}"
        show_enable_status $1
        ;;
    1)
        echo -e "${1} status: ${yellow}stopped${plain}"
        show_enable_status $1
        ;;
    2)
        echo -e "${1} status: ${red}not installed${plain}"
        ;;
    esac
}

show_enable_status() {
    check_enabled $1
    if [[ $? == 0 ]]; then
        echo -e "${1} on boot: ${green}enabled${plain}"
    else
        echo -e "${1} on boot: ${red}disabled${plain}"
    fi
}

check_s-ui_status() {
    count=$(ps -ef | grep "sui" | grep -v "grep" | wc -l)
    if [[ count -ne 0 ]]; then
        return 0
    else
        return 1
    fi
}

show_s-ui_status() {
    check_s-ui_status
    if [[ $? == 0 ]]; then
        echo -e "s-ui process: ${green}running${plain}"
    else
        echo -e "s-ui process: ${red}not running${plain}"
    fi
}

bbr_menu() {
    echo -e "${green}\t1.${plain} Enable BBR"
    echo -e "${green}\t2.${plain} Disable BBR"
    echo -e "${green}\t0.${plain} Back"
    read -p "Choose an option: " choice
    case "$choice" in
    0)
        show_menu
        ;;
    1)
        enable_bbr
        ;;
    2)
        disable_bbr
        ;;
    *) echo "Invalid choice" ;;
    esac
}

disable_bbr() {
    if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf || ! grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        echo -e "${yellow}BBR is not enabled.${plain}"
        exit 0
    fi
    sed -i 's/net.core.default_qdisc=fq/net.core.default_qdisc=pfifo_fast/' /etc/sysctl.conf
    sed -i 's/net.ipv4.tcp_congestion_control=bbr/net.ipv4.tcp_congestion_control=cubic/' /etc/sysctl.conf
    sysctl -p
    if [[ $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}') == "cubic" ]]; then
        echo -e "${green}Switched congestion control to CUBIC.${plain}"
    else
        echo -e "${red}Failed to switch to CUBIC. Check sysctl configuration.${plain}"
    fi
}

enable_bbr() {
    if grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf && grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        echo -e "${green}BBR is already enabled.${plain}"
        exit 0
    fi
    case "${release}" in
    ubuntu | debian | armbian)
        apt-get update && apt-get install -yqq --no-install-recommends ca-certificates
        ;;
    centos | almalinux | rocky | oracle)
        yum -y update && yum -y install ca-certificates
        ;;
    fedora)
        dnf -y update && dnf -y install ca-certificates
        ;;
    arch | manjaro | parch)
        pacman -Sy --noconfirm ca-certificates
        ;;
    *)
        echo -e "${red}Unsupported OS for automatic package install.${plain}\n"
        exit 1
        ;;
    esac
    echo "net.core.default_qdisc=fq" | tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" | tee -a /etc/sysctl.conf
    sysctl -p
    if [[ $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}') == "bbr" ]]; then
        echo -e "${green}BBR enabled.${plain}"
    else
        echo -e "${red}Failed to enable BBR. Check sysctl configuration.${plain}"
    fi
}

install_acme() {
    cd ~
    LOGI "Installing acme.sh..."
    curl https://get.acme.sh | sh
    if [ $? -ne 0 ]; then
        LOGE "acme.sh install failed"
        return 1
    else
        LOGI "acme.sh installed"
    fi
    return 0
}

ssl_cert_issue_main() {
    echo -e "${green}\t1.${plain} Issue certificate"
    echo -e "${green}\t2.${plain} Revoke certificate"
    echo -e "${green}\t3.${plain} Force renew"
    echo -e "${green}\t4.${plain} Self-signed certificate"
    read -p "Choose an option: " choice
    case "$choice" in
        1) ssl_cert_issue ;;
        2)
            local domain=""
            read -p "Domain to revoke: " domain
            ~/.acme.sh/acme.sh --revoke -d ${domain}
            LOGI "Revocation requested"
            ;;
        3)
            local domain=""
            read -p "Domain to force-renew: " domain
            ~/.acme.sh/acme.sh --renew -d ${domain} --force ;;
        4)
            generate_self_signed_cert
            ;;
        *) echo "Invalid choice" ;;
    esac
}

ssl_cert_issue() {
    if ! command -v ~/.acme.sh/acme.sh &>/dev/null; then
        echo "acme.sh not found; installing..."
        install_acme
        if [ $? -ne 0 ]; then
            LOGE "acme.sh install failed; check logs"
            exit 1
        fi
    fi
    case "${release}" in
    ubuntu | debian | armbian)
        apt update && apt install socat -y
        ;;
    centos | almalinux | rocky | oracle)
        yum -y update && yum -y install socat
        ;;
    fedora)
        dnf -y update && dnf -y install socat
        ;;
    arch | manjaro | parch)
        pacman -Sy --noconfirm socat
        ;;
    *)
        echo -e "${red}Unsupported OS for automatic socat install.${plain}\n"
        exit 1
        ;;
    esac
    if [ $? -ne 0 ]; then
        LOGE "socat install failed"
        exit 1
    else
        LOGI "socat installed"
    fi

    local domain=""
    read -p "Domain name: " domain
    LOGD "Using domain ${domain}..."
    local currentCert=$(~/.acme.sh/acme.sh --list | tail -1 | awk '{print $1}')

    if [ ${currentCert} == ${domain} ]; then
        local certInfo=$(~/.acme.sh/acme.sh --list)
        LOGE "Certificate already exists for this domain:"
        LOGI "$certInfo"
        exit 1
    else
        LOGI "Domain looks ready for issuance..."
    fi

    certPath="/root/cert/${domain}"
    if [ ! -d "$certPath" ]; then
        mkdir -p "$certPath"
    else
        rm -rf "$certPath"
        mkdir -p "$certPath"
    fi

    local WebPort=80
    read -p "HTTP challenge port (default 80): " WebPort
    if [[ ${WebPort} -gt 65535 || ${WebPort} -lt 1 ]]; then
        LOGE "Invalid port ${WebPort}; using 80"
        WebPort=80
    fi
    LOGI "Using port ${WebPort} for HTTP-01; ensure it is reachable from the internet."
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    ~/.acme.sh/acme.sh --issue -d ${domain} --standalone --httpport ${WebPort}
    if [ $? -ne 0 ]; then
        LOGE "Certificate issuance failed"
        rm -rf ~/.acme.sh/${domain}
        exit 1
    else
        LOGI "Certificate issued; installing files..."
    fi
    ~/.acme.sh/acme.sh --installcert -d ${domain} \
        --key-file /root/cert/${domain}/privkey.pem \
        --fullchain-file /root/cert/${domain}/fullchain.pem

    if [ $? -ne 0 ]; then
        LOGE "Certificate install failed"
        rm -rf ~/.acme.sh/${domain}
        exit 1
    else
        LOGI "Certificate installed; enabling auto-upgrade..."
    fi

    ~/.acme.sh/acme.sh --upgrade --auto-upgrade
    if [ $? -ne 0 ]; then
        LOGE "Auto-upgrade failed"
        ls -lah cert/*
        chmod 755 $certPath/*
        exit 1
    else
        LOGI "Auto-renewal enabled"
        ls -lah cert/*
        chmod 755 $certPath/*
    fi
}

ssl_cert_issue_CF() {
    echo -E ""
    LOGD "****** Cloudflare DNS-01 ******"
    echo "1) New certificate via Cloudflare"
    echo "2) Force renew existing"
    echo "3) Back"
    read -p "Choice [1-3]: " choice

    certPath="/root/cert-CF"

    case $choice in
        1|2)
            force_flag=""
            if [ "$choice" -eq 2 ]; then
                force_flag="--force"
                echo "Force renewing certificate..."
            else
                echo "Issuing certificate..."
            fi

            LOGD "****** Requirements ******"
            LOGI "This flow needs:"
            LOGI "1) Cloudflare account email"
            LOGI "2) Cloudflare global API key"
            LOGI "3) DNS hosted on Cloudflare pointing to this server"
            LOGI "4) Certificates install under /root/cert by default"
            confirm "Continue? [y/N]" "y"
            if [ $? -eq 0 ]; then
                if ! command -v ~/.acme.sh/acme.sh &>/dev/null; then
                    echo "acme.sh not found; installing..."
                    install_acme
                    if [ $? -ne 0 ]; then
                        LOGE "acme.sh install failed"
                        exit 1
                    fi
                fi

                CF_Domain=""
                if [ ! -d "$certPath" ]; then
                    mkdir -p $certPath
                else
                    rm -rf $certPath
                    mkdir -p $certPath
                fi

                LOGD "Domain:"
                read -p "Domain: " CF_Domain
                LOGD "Domain set to ${CF_Domain}"

                CF_GlobalKey=""
                CF_AccountEmail=""
                LOGD "Global API key:"
                read -p "API key: " CF_GlobalKey

                LOGD "Account email:"
                read -p "Email: " CF_AccountEmail

                ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
                if [ $? -ne 0 ]; then
                    LOGE "Failed to set default CA"
                    exit 1
                fi

                export CF_Key="${CF_GlobalKey}"
                export CF_Email="${CF_AccountEmail}"

                ~/.acme.sh/acme.sh --issue --dns dns_cf -d ${CF_Domain} -d *.${CF_Domain} $force_flag --log
                if [ $? -ne 0 ]; then
                    LOGE "Issuance failed"
                    exit 1
                else
                    LOGI "Issued; installing..."
                fi

                mkdir -p ${certPath}/${CF_Domain}
                if [ $? -ne 0 ]; then
                    LOGE "Failed to mkdir ${certPath}/${CF_Domain}"
                    exit 1
                fi

                ~/.acme.sh/acme.sh --installcert -d ${CF_Domain} -d *.${CF_Domain} \
                    --fullchain-file ${certPath}/${CF_Domain}/fullchain.pem \
                    --key-file ${certPath}/${CF_Domain}/privkey.pem

                if [ $? -ne 0 ]; then
                    LOGE "Install failed"
                    exit 1
                else
                    LOGI "Installed; enabling auto-upgrade..."
                fi

                ~/.acme.sh/acme.sh --upgrade --auto-upgrade
                if [ $? -ne 0 ]; then
                    LOGE "Auto-upgrade failed"
                    exit 1
                else
                    LOGI "Certificate installed with auto-renewal."
                    ls -lah ${certPath}/${CF_Domain}
                    chmod 755 ${certPath}/${CF_Domain}
                fi
            fi
            show_menu
            ;;
        3)
            echo "Returning..."
            show_menu
            ;;
        *)
            echo "Invalid choice."
            show_menu
            ;;
    esac
}

generate_self_signed_cert() {
    cert_dir="/etc/sing-box"
    mkdir -p "$cert_dir"
    LOGI "Certificate type:"
    echo -e "${green}\t1.${plain} Ed25519 (recommended)"
    echo -e "${green}\t2.${plain} RSA 2048"
    echo -e "${green}\t3.${plain} RSA 4096"
    echo -e "${green}\t4.${plain} ECDSA prime256v1"
    echo -e "${green}\t5.${plain} ECDSA secp384r1"
    read -p "Choice [1-5, default 1]: " cert_type
    cert_type=${cert_type:-1}

    case "$cert_type" in
        1)
            algo="ed25519"
            key_opt="-newkey ed25519"
            ;;
        2)
            algo="rsa"
            key_opt="-newkey rsa:2048"
            ;;
        3)
            algo="rsa"
            key_opt="-newkey rsa:4096"
            ;;
        4)
            algo="ecdsa"
            key_opt="-newkey ec -pkeyopt ec_paramgen_curve:prime256v1"
            ;;
        5)
            algo="ecdsa"
            key_opt="-newkey ec -pkeyopt ec_paramgen_curve:secp384r1"
            ;;
        *)
            algo="ed25519"
            key_opt="-newkey ed25519"
            ;;
    esac

    LOGI "Generating self-signed certificate (${algo})..."
    sudo openssl req -x509 -nodes -days 3650 $key_opt \
        -keyout "${cert_dir}/self.key" \
        -out "${cert_dir}/self.crt" \
        -subj "/CN=myserver"
    if [[ $? -eq 0 ]]; then
        sudo chmod 600 "${cert_dir}/self."*
        LOGI "Self-signed certificate created."
        LOGI "Cert: ${cert_dir}/self.crt"
        LOGI "Key:  ${cert_dir}/self.key"
    else
        LOGE "Self-signed certificate generation failed."
    fi
    before_show_menu
}

show_usage() {
    echo -e "S-UI management script"
    echo -e "------------------------------------------"
    echo -e "Subcommands:"
    echo -e "s-ui              - interactive menu"
    echo -e "s-ui start        - start s-ui"
    echo -e "s-ui stop         - stop s-ui"
    echo -e "s-ui restart      - restart s-ui"
    echo -e "s-ui status       - systemd status"
    echo -e "s-ui enable       - enable on boot"
    echo -e "s-ui disable      - disable on boot"
    echo -e "s-ui log          - follow logs"
    echo -e "s-ui update       - upgrade in place"
    echo -e "s-ui install      - install"
    echo -e "s-ui uninstall    - uninstall"
    echo -e "s-ui help         - this help"
    echo -e "------------------------------------------"
}

show_menu() {
  echo -e "
  ${green}S-UI management${plain}
---------------------------------------------------------------
  ${green}0.${plain} Exit
---------------------------------------------------------------
  ${green}1.${plain} Install
  ${green}2.${plain} Update
  ${green}3.${plain} Custom version
  ${green}4.${plain} Uninstall
---------------------------------------------------------------
  ${green}5.${plain} Reset admin to defaults
  ${green}6.${plain} Set admin username/password
  ${green}7.${plain} Show admin credentials
---------------------------------------------------------------
  ${green}8.${plain} Reset panel settings
  ${green}9.${plain} Configure panel settings
  ${green}10.${plain} Show panel settings
---------------------------------------------------------------
  ${green}11.${plain} Start s-ui
  ${green}12.${plain} Stop s-ui
  ${green}13.${plain} Restart s-ui
  ${green}14.${plain} Status
  ${green}15.${plain} Logs
  ${green}16.${plain} Enable on boot
  ${green}17.${plain} Disable on boot
---------------------------------------------------------------
  ${green}18.${plain} BBR toggle
  ${green}19.${plain} SSL (standalone)
  ${green}20.${plain} SSL (Cloudflare DNS)
---------------------------------------------------------------
 "
    show_status s-ui
    echo && read -p "Choose [0-20]: " num

    case "${num}" in
    0)
        exit 0
        ;;
    1)
        check_uninstall && install
        ;;
    2)
        check_install && update
        ;;
    3)
        check_install && custom_version
        ;;
    4)
        check_install && uninstall
        ;;
    5)
        check_install && reset_admin
        ;;
    6)
        check_install && set_admin
        ;;
    7)
        check_install && view_admin
        ;;
    8)
        check_install && reset_setting
        ;;
    9)
        check_install && set_setting
        ;;
    10)
        check_install && view_setting
        ;;
    11)
        check_install && start s-ui
        ;;
    12)
        check_install && stop s-ui
        ;;
    13)
        check_install && restart s-ui
        ;;
    14)
        check_install && status s-ui
        ;;
    15)
        check_install && show_log s-ui
        ;;
    16)
        check_install && enable s-ui
        ;;
    17)
        check_install && disable s-ui
        ;;
    18)
        bbr_menu
        ;;
    19)
        ssl_cert_issue_main
        ;;
    20)
        ssl_cert_issue_CF
        ;;
    *)
        LOGE "Enter a number between 0 and 20"
        ;;
    esac
}

if [[ $# > 0 ]]; then
    case $1 in
    "start")
        check_install 0 && start s-ui 0
        ;;
    "stop")
        check_install 0 && stop s-ui 0
        ;;
    "restart")
        check_install 0 && restart s-ui 0
        ;;
    "status")
        check_install 0 && status 0
        ;;
    "enable")
        check_install 0 && enable s-ui 0
        ;;
    "disable")
        check_install 0 && disable s-ui 0
        ;;
    "log")
        check_install 0 && show_log s-ui 0
        ;;
    "update")
        check_install 0 && update 0
        ;;
    "install")
        check_uninstall 0 && install 0
        ;;
    "uninstall")
        check_install 0 && uninstall 0
        ;;
    *) show_usage ;;
    esac
else
    show_menu
fi
