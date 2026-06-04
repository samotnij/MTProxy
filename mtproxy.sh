#!/bin/bash
###
 # @Author: Vincent Young
 # @Date: 2022-07-01 15:29:23
 # @LastEditors: Vincent Young
 # @LastEditTime: 2022-07-30 19:26:45
 # @FilePath: /MTProxy/mtproxy.sh
 # @Telegram: https://t.me/missuo
 # 
 # Copyright © 2022 by Vincent, All Rights Reserved. 
### 

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

# Define Color
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# Make sure run with root
[[ $EUID -ne 0 ]] && echo -e "[${red}Error${plain}]Please run this script with ROOT!" && exit 1

check_system(){
    if [[ ! -f /etc/os-release ]]; then
        echo -e "[${red}Error${plain}] Cannot detect OS."
        exit 1
    fi

    . /etc/os-release
    if [[ "${ID_LIKE}" != *"rhel"* && "${ID}" != "rhel" && "${ID}" != "rocky" && "${ID}" != "almalinux" && "${ID}" != "centos" && "${ID}" != "ol" ]]; then
        echo -e "[${red}Error${plain}] This script supports modern RHEL-family distributions."
        exit 1
    fi

    if ! command -v dnf >/dev/null 2>&1; then
        echo -e "[${red}Error${plain}] dnf is required but not found."
        exit 1
    fi

    if ! command -v systemctl >/dev/null 2>&1; then
        echo -e "[${red}Error${plain}] systemd is required but not found."
        exit 1
    fi
}

install_dependencies(){
    echo "Installing required packages..."
    dnf -y install curl wget tar sed
    if systemctl is-active --quiet firewalld; then
        echo "firewalld status: active, firewall rules will be used."
    else
        echo "firewalld status: inactive, firewall rules will be skipped."
    fi
}

restorecon_if_needed(){
    target_path="$1"
    if command -v selinuxenabled >/dev/null 2>&1 && selinuxenabled; then
        restorecon -v "${target_path}" >/dev/null 2>&1
    fi
}

download_file(){
	echo "Checking System..."

	bit=`uname -m`
	if [[ ${bit} = "x86_64" ]]; then
		bit="amd64"
    elif [[ ${bit} = "aarch64" ]]; then
        bit="arm64"
    else
	    bit="386"
    fi

    last_version=$(curl -Ls "https://api.github.com/repos/9seconds/mtg/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [[ ! -n "$last_version" ]]; then
        echo -e "${red}Failure to detect mtg version may be due to exceeding Github API limitations, please try again later."
        exit 1
    fi
    echo -e "Latest version of mtg detected: ${last_version}, start installing..."
    version=$(echo ${last_version} | sed 's/v//g')
    wget -N --no-check-certificate -O mtg-${version}-linux-${bit}.tar.gz https://github.com/9seconds/mtg/releases/download/${last_version}/mtg-${version}-linux-${bit}.tar.gz
    if [[ ! -f "mtg-${version}-linux-${bit}.tar.gz" ]]; then
        echo -e "${red}Download mtg-${version}-linux-${bit}.tar.gz failed, please try again."
        exit 1
    fi
    tar -xzf mtg-${version}-linux-${bit}.tar.gz
    mv mtg-${version}-linux-${bit}/mtg /usr/bin/mtg
    rm -f mtg-${version}-linux-${bit}.tar.gz
    rm -rf mtg-${version}-linux-${bit}
    chmod +x /usr/bin/mtg
    restorecon_if_needed /usr/bin/mtg
    echo -e "mtg-${version}-linux-${bit}.tar.gz installed successfully, start to configure..."
}

configure_mtg(){
    echo -e "Configuring mtg..."
    wget -N --no-check-certificate -O /etc/mtg.toml https://raw.githubusercontent.com/samotnij/MTProxy/main/mtg.toml
    
    echo ""
    read -p "Please enter a spoofed domain (default itunes.apple.com): " domain
	[ -z "${domain}" ] && domain="itunes.apple.com"

	echo ""
    read -p "Enter the port to be listened to (default 8443):" port
	[ -z "${port}" ] && port="8443"

    secret=$(mtg generate-secret --hex $domain)
    
    echo "Waiting configuration..."

    sed -i "s/secret.*/secret = \"${secret}\"/g" /etc/mtg.toml
    sed -i "s/bind-to.*/bind-to = \"0.0.0.0:${port}\"/g" /etc/mtg.toml

    echo "mtg configured successfully, start to configure systemctl..."
}

configure_systemctl(){
    echo -e "Configuring systemctl..."
    wget -N --no-check-certificate -O /etc/systemd/system/mtg.service https://raw.githubusercontent.com/samotnij/MTProxy/main/mtg.service
    systemctl daemon-reload
    systemctl enable mtg
    systemctl start mtg
    echo "mtg configured successfully, start to configure Rocky Linux firewall..."
    if systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-port="${port}"/tcp >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
        echo "firewalld: rule for port ${port}/tcp applied successfully."
    else
        echo "firewalld: inactive, firewall configuration not used."
    fi
    echo "mtg start successfully, enjoy it!"
    echo ""
    # echo "mtg configuration:"
    # mtg_config=$(mtg access /etc/mtg.toml)
    public_ip=$(curl -s ipv4.ip.sb)
    subscription_config="tg://proxy?server=${public_ip}&port=${port}&secret=${secret}"
    subscription_link="https://t.me/proxy?server=${public_ip}&port=${port}&secret=${secret}"
    echo -e "${subscription_config}"
    echo -e "${subscription_link}"
}

change_port(){
    old_port=$(sed -n 's/^bind-to *= *"0\.0\.0\.0:\([0-9]\+\)".*/\1/p' /etc/mtg.toml)
    read -p "Enter the port you want to modify(default 8443):" port
	[ -z "${port}" ] && port="8443"
    sed -i "s/bind-to.*/bind-to = \"0.0.0.0:${port}\"/g" /etc/mtg.toml
    if systemctl is-active --quiet firewalld; then
        if [[ -n "${old_port}" && "${old_port}" != "${port}" ]]; then
            firewall-cmd --permanent --remove-port="${old_port}"/tcp >/dev/null 2>&1
        fi
        firewall-cmd --permanent --add-port="${port}"/tcp >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
        echo "firewalld: port rule updated successfully (${old_port:-none} -> ${port})."
    else
        echo "firewalld: inactive, port rule update skipped."
    fi
    echo "Restarting MTProxy..."
    systemctl restart mtg
    echo "MTProxy restarted successfully!"
}

change_secret(){
    echo -e "Please note that unauthorized modification of Secret may cause MTProxy to not function properly."
    read -p "Enter the secret you want to modify:" secret
	[ -z "${secret}" ] && secret="$(mtg generate-secret --hex itunes.apple.com)"
    sed -i "s/secret.*/secret = \"${secret}\"/g" /etc/mtg.toml
    echo "Secret changed successfully!"
    echo "Restarting MTProxy..."
    systemctl restart mtg
    echo "MTProxy restarted successfully!"
}

update_mtg(){
    echo -e "Updating mtg..."
    download_file
    echo "mtg updated successfully, start to restart MTProxy..."
    systemctl restart mtg
    echo "MTProxy restarted successfully!"
}

get_mtg_port(){
    sed -n 's/^bind-to *= *"[^"]*:\([0-9]\+\)".*/\1/p' /etc/mtg.toml 2>/dev/null | head -1
}

get_prometheus_metrics(){
    local prom_enabled bind_to http_path prefix metrics_url

    [[ -f /etc/mtg.toml ]] || return 1

    prom_enabled=$(awk '/^\[stats\.prometheus\]/{f=1; next} /^\[/{f=0} f && /^enabled *=/{gsub(/.*= */, ""); gsub(/"/, ""); print; exit}' /etc/mtg.toml)
    [[ "${prom_enabled}" == "true" ]] || return 1

    bind_to=$(awk '/^\[stats\.prometheus\]/{f=1; next} /^\[/{f=0} f && /^bind-to *=/{gsub(/.*= *"|"/, ""); print; exit}' /etc/mtg.toml)
    http_path=$(awk '/^\[stats\.prometheus\]/{f=1; next} /^\[/{f=0} f && /^http-path *=/{gsub(/.*= *"|"/, ""); print; exit}' /etc/mtg.toml)
    prefix=$(awk '/^\[stats\.prometheus\]/{f=1; next} /^\[/{f=0} f && /^metric-prefix *=/{gsub(/.*= *"|"/, ""); print; exit}' /etc/mtg.toml)

    [[ -z "${bind_to}" ]] && bind_to="127.0.0.1:3129"
    [[ -z "${http_path}" ]] && http_path="/"
    [[ -z "${prefix}" ]] && prefix="mtg"
    [[ "${http_path}" != /* ]] && http_path="/${http_path}"

    metrics_url="http://${bind_to}${http_path}"
    curl -sf --max-time 2 "${metrics_url}" 2>/dev/null
}

sum_prometheus_gauge(){
    local metric="$1"
    local metrics="$2"
    echo "${metrics}" | awk -v m="${metric}" '
        $1 ~ "^" m "($|\\{)" {
            if ($2 ~ /^[0-9]+(\.[0-9]+)?$/) sum += $2
        }
        END { printf "%.0f", sum + 0 }
    '
}

count_connections_fallback(){
    local port="$1"
    if command -v ss >/dev/null 2>&1; then
        ss -Htan state established "( sport = :${port} )" 2>/dev/null | wc -l | tr -d ' '
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tn 2>/dev/null | awk -v p=":${port}" '$4 ~ p && $6 == "ESTABLISHED" { c++ } END { print c + 0 }'
    else
        echo "?"
    fi
}

show_status(){
    local mtg_version active_state sub_state main_pid since memory port secret secret_masked
    local access_json public_ip tg_url metrics prom_prefix client_conn tg_conn fronting_conn fallback_conn
    local crit_logs err_logs replay blocklisted concurrency_limited

    echo -e "========== ${green}MTProxy Status${plain} =========="
    echo ""

    if [[ ! -f /etc/mtg.toml ]]; then
        echo -e "[${red}Error${plain}] MTProxy is not installed (/etc/mtg.toml not found)."
        return 1
    fi

    if [[ ! -x /usr/bin/mtg ]]; then
        echo -e "[${red}Error${plain}] mtg binary not found."
        return 1
    fi

    mtg_version=$(/usr/bin/mtg --version 2>/dev/null | head -1)
    [[ -n "${mtg_version}" ]] && echo "Version: ${mtg_version}"

    if systemctl is-active --quiet mtg 2>/dev/null; then
        echo -e "Service: ${green}running${plain}"
    else
        echo -e "Service: ${red}stopped${plain}"
    fi

    active_state=$(systemctl show mtg -p ActiveState --value 2>/dev/null)
    sub_state=$(systemctl show mtg -p SubState --value 2>/dev/null)
    [[ -n "${active_state}" ]] && echo "State: ${active_state} (${sub_state})"

    main_pid=$(systemctl show mtg -p MainPID --value 2>/dev/null)
    [[ -n "${main_pid}" && "${main_pid}" != "0" ]] && echo "PID: ${main_pid}"

    since=$(systemctl show mtg -p ActiveEnterTimestamp --value 2>/dev/null)
    [[ -n "${since}" && "${since}" != "n/a" ]] && echo "Started: ${since}"

    memory=$(systemctl show mtg -p MemoryCurrent --value 2>/dev/null)
    if [[ -n "${memory}" && "${memory}" != "[not set]" && "${memory}" != "infinity" ]]; then
        echo "Memory: ~$(( memory / 1024 / 1024 )) MiB"
    fi

    echo ""
    echo "--- Configuration ---"
    port=$(get_mtg_port)
    [[ -n "${port}" ]] && echo "Listen port: ${port}"

    secret=$(sed -n 's/^secret *= *"\([^"]*\)".*/\1/p' /etc/mtg.toml | head -1)
    if [[ -n "${secret}" ]]; then
        secret_masked="${secret:0:8}...${secret: -8}"
        echo "Secret: ${secret_masked}"
    fi

    access_json=$(/usr/bin/mtg access /etc/mtg.toml 2>/dev/null)
    if [[ -n "${access_json}" ]]; then
        public_ip=$(echo "${access_json}" | grep -o '"ip"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
        tg_url=$(echo "${access_json}" | grep -o '"tg_url"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
        [[ -n "${public_ip}" ]] && echo "Public IP: ${public_ip}"
        [[ -n "${tg_url}" ]] && echo "Proxy link: ${tg_url}"
    fi

    echo ""
    echo "--- Connections ---"
    prom_prefix=$(awk '/^\[stats\.prometheus\]/{f=1; next} /^\[/{f=0} f && /^metric-prefix *=/{gsub(/.*= *"|"/, ""); print; exit}' /etc/mtg.toml)
    [[ -z "${prom_prefix}" ]] && prom_prefix="mtg"
    metrics=$(get_prometheus_metrics)
    if [[ -n "${metrics}" ]]; then
        client_conn=$(sum_prometheus_gauge "${prom_prefix}_client_connections" "${metrics}")
        tg_conn=$(sum_prometheus_gauge "${prom_prefix}_telegram_connections" "${metrics}")
        fronting_conn=$(sum_prometheus_gauge "${prom_prefix}_domain_fronting_connections" "${metrics}")
        echo "Active client connections: ${client_conn}"
        echo "Telegram upstream connections: ${tg_conn}"
        [[ "${fronting_conn}" != "0" ]] && echo "Domain fronting connections: ${fronting_conn}"

        replay=$(echo "${metrics}" | awk '/^[^#]/ && /_replay_attacks / { print $2; exit }')
        blocklisted=$(echo "${metrics}" | awk '/^[^#]/ && /_ip_blocklisted / { sum += $2 } END { print sum + 0 }')
        concurrency_limited=$(echo "${metrics}" | awk '/^[^#]/ && /_concurrency_limited / { print $2; exit }')
        [[ "${replay}" != "0" && -n "${replay}" ]] && echo -e "${yellow}Replay attacks detected: ${replay}${plain}"
        [[ "${blocklisted}" != "0" ]] && echo -e "${yellow}Blocklisted connection attempts: ${blocklisted}${plain}"
        [[ "${concurrency_limited}" != "0" && -n "${concurrency_limited}" ]] && echo -e "${yellow}Rejected by concurrency limit: ${concurrency_limited}${plain}"
    elif [[ -n "${port}" ]] && systemctl is-active --quiet mtg 2>/dev/null; then
        fallback_conn=$(count_connections_fallback "${port}")
        echo "Active connections (port ${port}): ${fallback_conn}"
        echo -e "${yellow}Tip: enable [stats.prometheus] in /etc/mtg.toml for detailed metrics.${plain}"
    else
        echo "Connections: n/a (service not running or metrics unavailable)"
    fi

    echo ""
    echo "--- Recent critical issues ---"
    if command -v journalctl >/dev/null 2>&1; then
        crit_logs=$(journalctl -u mtg -p emerg..crit --no-pager -n 5 -o short-iso 2>/dev/null)
        err_logs=$(journalctl -u mtg -p err..err --no-pager -n 5 -o short-iso 2>/dev/null)

        if [[ -n "${crit_logs}" ]]; then
            echo -e "${red}Critical / alert / emergency:${plain}"
            echo "${crit_logs}"
        fi

        if [[ -n "${err_logs}" ]]; then
            echo -e "${yellow}Recent errors:${plain}"
            echo "${err_logs}"
        fi

        if [[ -z "${crit_logs}" && -z "${err_logs}" ]]; then
            echo -e "${green}No critical or error log entries found.${plain}"
        fi
    else
        echo "journalctl not available."
    fi

    echo ""
    echo "========================================"
}

start_menu() {
    clear
    echo -e "  MTProxy v2 One-Click Installation
---- by Vincent | github.com/samotnij/MTProxy ----
 ${green} 1.${plain} Install MTProxy
 ${green} 2.${plain} Uninstall MTProxy
————————————
 ${green} 3.${plain} Start MTProxy
 ${green} 4.${plain} Stop MTProxy
 ${green} 5.${plain} Restart MTProxy
 ${green} 6.${plain} Change Listen Port
 ${green} 7.${plain} Change Secret
 ${green} 8.${plain} Update MTProxy
 ${green} 9.${plain} Show Status
————————————
 ${green} 0.${plain} Exit
————————————" && echo

	read -e -p " Please enter the number [0-9]: " num
	case "$num" in
    1)
        check_system
        install_dependencies
		download_file
        configure_mtg
        configure_systemctl
		;;
    2)
        echo "Uninstall MTProxy..."
        systemctl stop mtg
        systemctl disable mtg
        rm -rf /usr/bin/mtg
        rm -rf /etc/mtg.toml
        rm -rf /etc/systemd/system/mtg.service
        echo "Uninstall MTProxy successfully!"
        ;;
    3) 
        echo "Starting MTProxy..."
        systemctl start mtg
        systemctl enable mtg
        echo "MTProxy started successfully!"
        ;;
    4) 
        echo "Stopping MTProxy..."
        systemctl stop mtg
        systemctl disable mtg
        echo "MTProxy stopped successfully!"
        ;;
    5)  
        echo "Restarting MTProxy..."
        systemctl restart mtg
        echo "MTProxy restarted successfully!"
        ;;
    6) 
        change_port
        ;;
    7)
        change_secret
        ;;
    8)
        update_mtg
        ;;
    9)
        show_status
        ;;
    0) exit 0
        ;;
    *) echo -e "${Error} Please enter a number [0-9]: "
        ;;
    esac
}

if [[ "$1" == "status" ]]; then
    show_status
    exit $?
fi

start_menu
