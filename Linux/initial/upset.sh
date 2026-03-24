#!/bin/sh
# @d_tranman/Nigel Gerald/Nigerald
# Fast inventory script with optional tmux layout, minimal-output checks,
# Kubernetes support, realmd domain detection, OS-specific config-path checks,
# per-service empty backup directories, enum logs in /root/.cache/enum,
# and common service misconfiguration checks.

IS_RHEL=false
IS_DEBIAN=false
IS_ALPINE=false
IS_SLACK=false

ORAG=''
GREEN=''
YELLOW=''
BLUE=''
RED=''
NC=''

TMUX_SESSION_NAME="${TMUX_SESSION_NAME:-inventory_time}"
CACHE_ROOT="/root/.cache"
ENUM_ROOT="$CACHE_ROOT/enum"
BACKUP_ROOT="$CACHE_ROOT/backup"

if [ -z "$DEBUG" ]; then
    DPRINT() {
        "$@" 2>/dev/null
    }
else
    DPRINT() {
        "$@"
    }
fi

RHEL()   { IS_RHEL=true; }
DEBIAN() { IS_DEBIAN=true; }
UBUNTU() { DEBIAN; }
ALPINE() { IS_ALPINE=true; }
SLACK()  { IS_SLACK=true; }

detect_os() {
    if command -v yum >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1; then
        RHEL
    elif command -v apt-get >/dev/null 2>&1; then
        if grep -qi ubuntu /etc/os-release 2>/dev/null; then
            UBUNTU
        else
            DEBIAN
        fi
    elif command -v apk >/dev/null 2>&1; then
        ALPINE
    elif command -v slapt-get >/dev/null 2>&1 || grep -qi slackware /etc/os-release 2>/dev/null; then
        SLACK
    fi
}

setup_colors() {
    if [ -n "$COLOR" ]; then
        ORAG='\033[0;33m'
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        BLUE='\033[0;36m'
        NC='\033[0m'
    fi
}

print_section() {
    echo -e "\n${GREEN}#############$1############${NC}\n"
}

safe_mkdir() {
    [ -d "$1" ] || mkdir -p "$1" 2>/dev/null
}

init_cache_dirs() {
    safe_mkdir "$CACHE_ROOT"
    safe_mkdir "$ENUM_ROOT"
    safe_mkdir "$BACKUP_ROOT"
}

write_text_file() {
    file="$1"
    text="$2"
    printf '%s\n' "$text" > "$file" 2>/dev/null
}

append_if_exists() {
    out="$1"
    path="$2"

    if [ -e "$path" ]; then
        if [ -n "$out" ]; then
            out="${out}
$path"
        else
            out="$path"
        fi
    fi

    printf '%s' "$out"
}

get_local_users() {
    grep -vE '(false|nologin|sync)$' /etc/passwd 2>/dev/null | grep -E '/.*sh$' | cut -d: -f1
}

get_sudoers_summary() {
    DPRINT sh -c 'cat /etc/sudoers /etc/sudoers.d/*' | grep -vE '^\s*#|^\s*$|Defaults|Cmnd_Alias|\\' | head -n 30
}

get_ss_output() {
    if command -v ss >/dev/null 2>&1; then
        ss -tulpn 2>/dev/null
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tlpn 2>/dev/null
    else
        echo "ss and netstat not found"
    fi
}

create_service_backup_dirs() {
    svc="$1"
    safe_mkdir "$BACKUP_ROOT/$svc"
    safe_mkdir "$BACKUP_ROOT/$svc/config"
    safe_mkdir "$BACKUP_ROOT/$svc/others"
}

bootstrap_tmux() {
    if [ -n "$INVENTORY_TMUX_BOOTSTRAPPED" ]; then
        return 0
    fi

    if [ -n "$TMUX" ]; then
        return 0
    fi

    if ! command -v tmux >/dev/null 2>&1; then
        return 0
    fi

    init_cache_dirs

    SCRIPT_PATH="$0"
    export INVENTORY_TMUX_BOOTSTRAPPED=1

    tmux new-session -d -s "$TMUX_SESSION_NAME" -n inventory
    tmux set-option -t "$TMUX_SESSION_NAME" -g mouse on

    tmux split-window -h -t "${TMUX_SESSION_NAME}:0"
    tmux split-window -v -t "${TMUX_SESSION_NAME}:0.1"

    tmux send-keys -t "${TMUX_SESSION_NAME}:0.0" \
        "INVENTORY_TMUX_BOOTSTRAPPED=1 COLOR=1 DEBUG=$DEBUG bash \"$SCRIPT_PATH\"" C-m

    tmux send-keys -t "${TMUX_SESSION_NAME}:0.1" \
        "clear; ( ss -tulpn 2>/dev/null || netstat -tlpn 2>/dev/null || echo 'ss/netstat not found' ) | tee \"$ENUM_ROOT/ss_tulpn.txt\"; echo; exec bash || exec sh" C-m

    tmux send-keys -t "${TMUX_SESSION_NAME}:0.2" \
        "clear; ( grep -vE '(false|nologin|sync)$' /etc/passwd 2>/dev/null | grep -E '/.*sh$' | cut -d: -f1 ) | tee \"$ENUM_ROOT/local_users.txt\"; echo; exec bash || exec sh" C-m

    tmux select-pane -t "${TMUX_SESSION_NAME}:0.0"
    exec tmux attach-session -t "$TMUX_SESSION_NAME"
}

print_header() {
    echo -e "${GREEN}
##################################
#                                #
#         INVENTORY TIME         #
#                                #
##################################
${NC}"
}

get_ips() {
    if command -v ip >/dev/null 2>&1; then
        ip -brief addr 2>/dev/null | awk '$1 != "lo" {print $1 ": " $3}'
    elif command -v ifconfig >/dev/null 2>&1; then
        ifconfig 2>/dev/null | awk '
            /^[A-Za-z0-9]/ { iface=$1; sub(":", "", iface) }
            /inet / && $2 != "127.0.0.1" { print iface ": " $2 }
        '
    else
        echo "ip and ifconfig not found"
    fi
}

get_service_list() {
    if [ "$IS_ALPINE" = true ]; then
        rc-status -s 2>/dev/null | grep started | awk '{print $1}'
    elif [ "$IS_SLACK" = true ]; then
        ls -la /etc/rc.d 2>/dev/null | grep rwx | awk '{print $9}'
    else
        systemctl --type=service --state=active 2>/dev/null | awk '{print $1}'
    fi
}

checkService() {
    serviceList="$1"
    serviceToCheckExists="$2"
    serviceAlias="$3"

    if [ -n "$serviceAlias" ]; then
        echo "$serviceList" | grep -Eqi "$serviceAlias|$serviceToCheckExists" || return 1
        return 0
    fi

    echo "$serviceList" | grep -qi "$serviceToCheckExists" || return 1
    return 0
}

domain_inventory() {
    print_section "DOMAIN / REALMD"

    if command -v realm >/dev/null 2>&1; then
        REALM_OUT="$(realm list 2>/dev/null)"
        if [ -n "$REALM_OUT" ]; then
            echo "$REALM_OUT" | grep -Ei 'realm-name:|domain-name:|configured:|server-software:|client-software:' || true
            write_text_file "$ENUM_ROOT/domain_realmd.txt" "$REALM_OUT"
        else
            echo "No realmd domain join detected"
            write_text_file "$ENUM_ROOT/domain_realmd.txt" "No realmd domain join detected"
        fi
    else
        echo "realm command not installed"
        write_text_file "$ENUM_ROOT/domain_realmd.txt" "realm command not installed"
    fi
    echo
}

docker_inventory() {
    if ! command -v docker >/dev/null 2>&1; then
        write_text_file "$ENUM_ROOT/docker_info.txt" "docker not found"
        return 0
    fi

    print_section "DOCKER"

    DOCKER_OUT="$(
        {
            echo "[+] Running containers"
            DPRINT docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
            echo
            echo "[+] Volume usage"
            DPRINT docker ps -a --format '{{.Names}} {{.Mounts}}' | grep -vE '^\s*$'
            echo
        } 2>/dev/null
    )"

    if [ -n "$DOCKER_OUT" ]; then
        echo "$DOCKER_OUT"
        write_text_file "$ENUM_ROOT/docker_info.txt" "$DOCKER_OUT"
    else
        echo "docker present but no useful output"
        write_text_file "$ENUM_ROOT/docker_info.txt" "docker present but no useful output"
    fi
}

kubernetes_inventory() {
    print_section "KUBERNETES"

    if ! command -v kubectl >/dev/null 2>&1; then
        echo "kubectl not found"
        echo
        write_text_file "$ENUM_ROOT/kubernetes_cluster_info.txt" "kubectl not found"
        return 0
    fi

    if ! kubectl cluster-info >/dev/null 2>&1; then
        echo "kubectl found, but no accessible cluster context detected"
        echo
        write_text_file "$ENUM_ROOT/kubernetes_cluster_info.txt" "kubectl found, but no accessible cluster context detected"
        return 0
    fi

    KUBE_OUT="$(
        {
            echo "[+] Context"
            kubectl config current-context 2>/dev/null
            echo
            echo "[+] Cluster info"
            kubectl cluster-info 2>/dev/null
            echo
            echo "[+] Nodes"
            kubectl get nodes -o wide 2>/dev/null
            echo
            echo "[+] Namespaces"
            kubectl get ns 2>/dev/null
            echo
            echo "[+] Running pods"
            kubectl get pods -A --field-selector=status.phase=Running -o wide 2>/dev/null | awk 'NR==1 || /Running/'
            echo
            echo "[+] Services"
            kubectl get svc -A -o wide 2>/dev/null
            echo
            echo "[+] Workloads"
            kubectl get deploy,daemonset,statefulset -A 2>/dev/null
            echo
            echo "[+] Ingress / Jobs / CronJobs"
            kubectl get ingress,jobs,cronjobs -A 2>/dev/null
            echo
        } 2>/dev/null
    )"

    echo "$KUBE_OUT"
    write_text_file "$ENUM_ROOT/kubernetes_cluster_info.txt" "$KUBE_OUT"
}

get_apache_config_paths() {
    out=""

    if [ "$IS_DEBIAN" = true ]; then
        out="$(append_if_exists "$out" /etc/apache2/apache2.conf)"
        out="$(append_if_exists "$out" /etc/apache2/ports.conf)"
        out="$(append_if_exists "$out" /etc/apache2/envvars)"
        [ -d /etc/apache2/sites-available ] && out="$(append_if_exists "$out" /etc/apache2/sites-available)"
        [ -d /etc/apache2/sites-enabled ] && out="$(append_if_exists "$out" /etc/apache2/sites-enabled)"
        [ -d /etc/apache2/conf-available ] && out="$(append_if_exists "$out" /etc/apache2/conf-available)"
        [ -d /etc/apache2/conf-enabled ] && out="$(append_if_exists "$out" /etc/apache2/conf-enabled)"
        [ -d /etc/apache2/mods-enabled ] && out="$(append_if_exists "$out" /etc/apache2/mods-enabled)"
    elif [ "$IS_RHEL" = true ]; then
        out="$(append_if_exists "$out" /etc/httpd/conf/httpd.conf)"
        [ -d /etc/httpd/conf.d ] && out="$(append_if_exists "$out" /etc/httpd/conf.d)"
        [ -d /etc/httpd/conf.modules.d ] && out="$(append_if_exists "$out" /etc/httpd/conf.modules.d)"
    elif [ "$IS_ALPINE" = true ]; then
        out="$(append_if_exists "$out" /etc/apache2/httpd.conf)"
        [ -d /etc/apache2/conf.d ] && out="$(append_if_exists "$out" /etc/apache2/conf.d)"
    fi

    printf '%s\n' "$out" | awk 'NF' | sort -u
}

get_nginx_config_paths() {
    out=""

    out="$(append_if_exists "$out" /etc/nginx/nginx.conf)"
    [ -d /etc/nginx/conf.d ] && out="$(append_if_exists "$out" /etc/nginx/conf.d)"
    [ -d /etc/nginx/sites-available ] && out="$(append_if_exists "$out" /etc/nginx/sites-available)"
    [ -d /etc/nginx/sites-enabled ] && out="$(append_if_exists "$out" /etc/nginx/sites-enabled)"
    [ -d /usr/local/etc/nginx ] && out="$(append_if_exists "$out" /usr/local/etc/nginx)"

    printf '%s\n' "$out" | awk 'NF' | sort -u
}

get_lighttpd_config_paths() {
    out=""

    out="$(append_if_exists "$out" /etc/lighttpd/lighttpd.conf)"
    [ -d /etc/lighttpd/conf.d ] && out="$(append_if_exists "$out" /etc/lighttpd/conf.d)"

    printf '%s\n' "$out" | awk 'NF' | sort -u
}

get_caddy_config_paths() {
    out=""

    out="$(append_if_exists "$out" /etc/caddy/Caddyfile)"
    out="$(append_if_exists "$out" /usr/local/etc/caddy/Caddyfile)"

    printf '%s\n' "$out" | awk 'NF' | sort -u
}

get_mysql_config_paths() {
    out=""

    if [ "$IS_DEBIAN" = true ]; then
        out="$(append_if_exists "$out" /etc/mysql/my.cnf)"
        [ -d /etc/mysql/mysql.conf.d ] && out="$(append_if_exists "$out" /etc/mysql/mysql.conf.d)"
        [ -d /etc/mysql/conf.d ] && out="$(append_if_exists "$out" /etc/mysql/conf.d)"
        [ -d /etc/mysql/mariadb.conf.d ] && out="$(append_if_exists "$out" /etc/mysql/mariadb.conf.d)"
    elif [ "$IS_RHEL" = true ]; then
        out="$(append_if_exists "$out" /etc/my.cnf)"
        [ -d /etc/my.cnf.d ] && out="$(append_if_exists "$out" /etc/my.cnf.d)"
    elif [ "$IS_ALPINE" = true ]; then
        out="$(append_if_exists "$out" /etc/my.cnf)"
        [ -d /etc/my.cnf.d ] && out="$(append_if_exists "$out" /etc/my.cnf.d)"
    fi

    printf '%s\n' "$out" | awk 'NF' | sort -u
}

get_postgres_config_paths() {
    out=""

    if [ "$IS_DEBIAN" = true ]; then
        [ -d /etc/postgresql ] && out="$(append_if_exists "$out" /etc/postgresql)"
    elif [ "$IS_RHEL" = true ]; then
        [ -d /var/lib/pgsql/data ] && out="$(append_if_exists "$out" /var/lib/pgsql/data)"
        [ -d /var/lib/pgsql ] && out="$(append_if_exists "$out" /var/lib/pgsql)"
    elif [ "$IS_ALPINE" = true ]; then
        [ -d /var/lib/postgresql ] && out="$(append_if_exists "$out" /var/lib/postgresql)"
        [ -d /etc/postgresql ] && out="$(append_if_exists "$out" /etc/postgresql)"
    fi

    printf '%s\n' "$out" | awk 'NF' | sort -u
}

get_php_config_paths() {
    out=""

    out="$(append_if_exists "$out" /etc/php.ini)"
    [ -d /etc/php ] && out="$(append_if_exists "$out" /etc/php)"
    [ -d /etc/php.d ] && out="$(append_if_exists "$out" /etc/php.d)"
    [ -d /etc/php5 ] && out="$(append_if_exists "$out" /etc/php5)"
    [ -d /etc/php7 ] && out="$(append_if_exists "$out" /etc/php7)"
    [ -d /etc/php8 ] && out="$(append_if_exists "$out" /etc/php8)"

    printf '%s\n' "$out" | awk 'NF' | sort -u
}

get_smb_config_paths() {
    out=""
    out="$(append_if_exists "$out" /etc/samba/smb.conf)"
    [ -d /etc/samba ] && out="$(append_if_exists "$out" /etc/samba)"
    printf '%s\n' "$out" | awk 'NF' | sort -u
}

get_snmp_config_paths() {
    out=""
    out="$(append_if_exists "$out" /etc/snmp/snmpd.conf)"
    [ -d /etc/snmp ] && out="$(append_if_exists "$out" /etc/snmp)"
    printf '%s\n' "$out" | awk 'NF' | sort -u
}

get_squid_config_paths() {
    out=""
    out="$(append_if_exists "$out" /etc/squid/squid.conf)"
    out="$(append_if_exists "$out" /etc/squid3/squid.conf)"
    [ -d /etc/squid/conf.d ] && out="$(append_if_exists "$out" /etc/squid/conf.d)"
    [ -d /etc/squid3/conf.d ] && out="$(append_if_exists "$out" /etc/squid3/conf.d)"
    printf '%s\n' "$out" | awk 'NF' | sort -u
}

get_cockpit_config_paths() {
    out=""
    [ -d /etc/cockpit ] && out="$(append_if_exists "$out" /etc/cockpit)"
    [ -d /usr/lib/systemd/system ] && out="$(append_if_exists "$out" /usr/lib/systemd/system/cockpit.socket)"
    [ -d /etc/systemd/system ] && out="$(append_if_exists "$out" /etc/systemd/system/cockpit.socket.d)"
    printf '%s\n' "$out" | awk 'NF' | sort -u
}

get_web_root_candidates() {
    out=""

    if [ "$IS_DEBIAN" = true ]; then
        out="$(append_if_exists "$out" /var/www/html)"
        out="$(append_if_exists "$out" /var/www)"
        out="$(append_if_exists "$out" /usr/share/nginx/html)"
    elif [ "$IS_RHEL" = true ]; then
        out="$(append_if_exists "$out" /var/www/html)"
        out="$(append_if_exists "$out" /usr/share/nginx/html)"
        out="$(append_if_exists "$out" /usr/share/httpd/noindex)"
    elif [ "$IS_ALPINE" = true ]; then
        out="$(append_if_exists "$out" /var/www/localhost/htdocs)"
        out="$(append_if_exists "$out" /usr/share/nginx/html)"
        out="$(append_if_exists "$out" /var/www/html)"
    else
        out="$(append_if_exists "$out" /var/www/html)"
        out="$(append_if_exists "$out" /var/www)"
        out="$(append_if_exists "$out" /usr/share/nginx/html)"
    fi

    printf '%s\n' "$out" | awk 'NF' | sort -u
}

get_service_config_paths() {
    svc="$1"

    case "$svc" in
        apache|apache2|httpd) get_apache_config_paths ;;
        nginx) get_nginx_config_paths ;;
        lighttpd) get_lighttpd_config_paths ;;
        caddy) get_caddy_config_paths ;;
        mysql|mariadb) get_mysql_config_paths ;;
        postgres|postgresql) get_postgres_config_paths ;;
        php) get_php_config_paths ;;
        smbd|nmbd) get_smb_config_paths ;;
        snmpd) get_snmp_config_paths ;;
        squid) get_squid_config_paths ;;
        cockpit) get_cockpit_config_paths ;;
        *) return 0 ;;
    esac
}

print_service_config_locations() {
    svc="$1"
    echo "[+] $svc config locations"
    get_service_config_paths "$svc"
    echo
}

grep_service_files() {
    pattern="$1"
    shift

    for p in "$@"; do
        [ -e "$p" ] || continue

        if [ -f "$p" ]; then
            grep -HinE "$pattern" "$p" 2>/dev/null
        elif [ -d "$p" ]; then
            for f in "$p"/*; do
                [ -f "$f" ] || continue
                grep -HinE "$pattern" "$f" 2>/dev/null
            done
        fi
    done
}

service_config_paths() {
    svc="$1"

    case "$svc" in
        ssh|sshd)
            echo /etc/ssh/sshd_config
            [ -d /etc/ssh/sshd_config.d ] && echo /etc/ssh/sshd_config.d
            ;;
        vsftpd)
            echo /etc/vsftpd.conf
            [ -d /etc/vsftpd ] && echo /etc/vsftpd
            ;;
        pure-ftpd)
            echo /etc/pure-ftpd
            [ -d /etc/pure-ftpd/conf ] && echo /etc/pure-ftpd/conf
            ;;
        proftpd)
            echo /etc/proftpd/proftpd.conf
            [ -d /etc/proftpd/conf.d ] && echo /etc/proftpd/conf.d
            ;;
        tftpd|atftpd)
            echo /etc/default/tftpd-hpa
            echo /etc/xinetd.d/tftp
            echo /etc/inetd.conf
            ;;
        apache|apache2|httpd)
            get_apache_config_paths
            ;;
        nginx)
            get_nginx_config_paths
            ;;
        mysql|mariadb)
            get_mysql_config_paths
            ;;
        postgres|postgresql)
            get_postgres_config_paths
            ;;
        php)
            get_php_config_paths
            ;;
        smbd|nmbd)
            get_smb_config_paths
            ;;
        snmpd)
            get_snmp_config_paths
            ;;
        squid)
            get_squid_config_paths
            ;;
        cockpit)
            get_cockpit_config_paths
            ;;
    esac
}

check_web_config_path() {
    p="$1"
    label="$2"

    if [ -f "$p" ]; then
        grep -qiE 'autoindex\s+on|Options\s+Indexes' "$p" 2>/dev/null && echo "  [!] $label: directory listing reference present"
        grep -qiE 'dav_methods|WebDAV|Dav\s' "$p" 2>/dev/null && echo "  [!] $label: WebDAV-related directive present"
        grep -qiE 'php_admin_flag|php_value|php_flag|SetHandler.*php|location.*\.php|FilesMatch.*php' "$p" 2>/dev/null && echo "  [+] $label: PHP handling reference present"
        grep -qiE 'client_max_body_size\s+[0-9]{2,}[mMgG]|LimitRequestBody\s+[1-9][0-9]{7,}' "$p" 2>/dev/null && echo "  [!] $label: large upload/body limit reference present"
        grep -qiE 'proxy_pass|ProxyPass|fastcgi_pass|uwsgi_pass|scgi_pass|grpc_pass' "$p" 2>/dev/null && echo "  [+] $label: reverse proxy/upstream reference present"
    elif [ -d "$p" ]; then
        found=0
        for f in "$p"/*; do
            [ -e "$f" ] || continue
            [ -f "$f" ] || continue
            check_web_config_path "$f" "$f"
            found=1
        done
        [ "$found" -eq 0 ] && echo "  [+] $label: no regular files directly inside"
    fi
}

check_service_config_findings() {
    svc="$1"

    echo "[+] $svc config findings"
    paths="$(get_service_config_paths "$svc")"

    if [ -z "$paths" ]; then
        echo "  No default config locations found"
        echo
        return 0
    fi

    echo "$paths" | while read -r p; do
        [ -n "$p" ] || continue
        echo "--- $p"
        check_web_config_path "$p" "$p"
    done

    echo
}

ssh_vuln_check() {
    paths="$(service_config_paths ssh)"
    out="$(
        {
            echo "[+] SSH findings"

            grep_service_files '^[[:space:]]*PermitRootLogin[[:space:]]+yes([[:space:]]|$)' $paths | head -n 5 \
                && echo "  [!] PermitRootLogin yes present"

            grep_service_files '^[[:space:]]*PasswordAuthentication[[:space:]]+yes([[:space:]]|$)' $paths | head -n 5 \
                && echo "  [!] PasswordAuthentication yes present"

            grep_service_files '^[[:space:]]*PubkeyAuthentication[[:space:]]+no([[:space:]]|$)' $paths | head -n 5 \
                && echo "  [!] PubkeyAuthentication no present"

            grep_service_files '^[[:space:]]*PermitEmptyPasswords[[:space:]]+yes([[:space:]]|$)' $paths | head -n 5 \
                && echo "  [!] PermitEmptyPasswords yes present"

            grep_service_files '^[[:space:]]*MaxAuthTries[[:space:]]+[6-9]|^[[:space:]]*MaxAuthTries[[:space:]]+[1-9][0-9]+' $paths | head -n 5 \
                && echo "  [!] High MaxAuthTries value present"

            grep_service_files '^[[:space:]]*AllowUsers[[:space:]]+' $paths | head -n 5 \
                && echo "  [+] AllowUsers restriction present"

            grep_service_files '^[[:space:]]*AllowGroups[[:space:]]+' $paths | head -n 5 \
                && echo "  [+] AllowGroups restriction present"
        } 2>/dev/null
    )"

    [ -n "$out" ] && echo "$out"
}

vsftpd_vuln_check() {
    paths="$(service_config_paths vsftpd)"
    out="$(
        {
            echo "[+] vsftpd findings"

            grep_service_files '^[[:space:]]*anonymous_enable[[:space:]]*=[[:space:]]*YES([[:space:]]|$)' $paths | head -n 5 \
                && echo "  [!] anonymous_enable=YES present"

            grep_service_files '^[[:space:]]*write_enable[[:space:]]*=[[:space:]]*YES([[:space:]]|$)' $paths | head -n 5 \
                && echo "  [!] write_enable=YES present"

            grep_service_files '^[[:space:]]*anon_upload_enable[[:space:]]*=[[:space:]]*YES([[:space:]]|$)' $paths | head -n 5 \
                && echo "  [!] anon_upload_enable=YES present"

            grep_service_files '^[[:space:]]*anon_mkdir_write_enable[[:space:]]*=[[:space:]]*YES([[:space:]]|$)' $paths | head -n 5 \
                && echo "  [!] anon_mkdir_write_enable=YES present"

            grep_service_files '^[[:space:]]*no_anon_password[[:space:]]*=[[:space:]]*YES([[:space:]]|$)' $paths | head -n 5 \
                && echo "  [!] no_anon_password=YES present"

            grep_service_files '^[[:space:]]*chroot_local_user[[:space:]]*=[[:space:]]*NO([[:space:]]|$)' $paths | head -n 5 \
                && echo "  [!] chroot_local_user=NO present"
        } 2>/dev/null
    )"

    [ -n "$out" ] && echo "$out"
}

proftpd_vuln_check() {
    paths="$(service_config_paths proftpd)"
    out="$(
        {
            echo "[+] ProFTPD findings"

            grep_service_files '^[[:space:]]*<Anonymous[[:space:]]' $paths | head -n 5 \
                && echo "  [!] Anonymous block present"

            grep_service_files '^[[:space:]]*RequireValidShell[[:space:]]+off([[:space:]]|$)' $paths | head -n 5 \
                && echo "  [!] RequireValidShell off present"

            grep_service_files '^[[:space:]]*RootLogin[[:space:]]+on([[:space:]]|$)' $paths | head -n 5 \
                && echo "  [!] RootLogin on present"
        } 2>/dev/null
    )"

    [ -n "$out" ] && echo "$out"
}

pureftpd_vuln_check() {
    out="$(
        {
            echo "[+] Pure-FTPd findings"

            grep_service_files '^[[:space:]]*yes([[:space:]]|$)' /etc/pure-ftpd/conf/AnonymousOnly 2>/dev/null | head -n 5 \
                && echo "  [!] AnonymousOnly enabled"

            grep_service_files '^[[:space:]]*yes([[:space:]]|$)' /etc/pure-ftpd/conf/AnonymousCanCreateDirs 2>/dev/null | head -n 5 \
                && echo "  [!] AnonymousCanCreateDirs enabled"

            grep_service_files '^[[:space:]]*yes([[:space:]]|$)' /etc/pure-ftpd/conf/NoAnonymous 2>/dev/null | head -n 5 \
                && echo "  [+] NoAnonymous enabled"
        } 2>/dev/null
    )"

    [ -n "$out" ] && echo "$out"
}

tftp_vuln_check() {
    paths="$(service_config_paths tftpd)"
    out="$(
        {
            echo "[+] TFTP findings"

            grep_service_files '(^|[[:space:]])--create([[:space:]]|$)|(^|[[:space:]])-c([[:space:]]|$)' $paths | head -n 5 \
                && echo "  [!] TFTP create/upload option present"

            grep_service_files '^[[:space:]]*disable[[:space:]]*=[[:space:]]*no([[:space:]]|$)' $paths | head -n 5 \
                && echo "  [+] xinetd tftp service enabled"

            grep_service_files '(^|[[:space:]])-s([[:space:]]|$)|(^|[[:space:]])--secure([[:space:]]|$)' $paths | head -n 5 \
                && echo "  [+] TFTP secure root option present"
        } 2>/dev/null
    )"

    [ -n "$out" ] && echo "$out"
}

apache_vuln_check() {
    paths="$(service_config_paths apache)"
    out="$(
        {
            echo "[+] Apache findings"

            grep_service_files 'Options[[:space:]]+.*Indexes' $paths | head -n 5 \
                && echo "  [!] Directory indexing enabled"

            grep_service_files '^[[:space:]]*ServerTokens[[:space:]]+Full([[:space:]]|$)' $paths | head -n 5 \
                && echo "  [!] ServerTokens Full present"

            grep_service_files '^[[:space:]]*ServerSignature[[:space:]]+On([[:space:]]|$)' $paths | head -n 5 \
                && echo "  [!] ServerSignature On present"

            grep_service_files '^[[:space:]]*<Directory[[:space:]]+/?>' $paths | head -n 5 \
                && echo "  [!] Broad root directory block present"

            grep_service_files 'php_admin_flag|php_value|php_flag|SetHandler.*php|FilesMatch.*php' $paths | head -n 5 \
                && echo "  [+] PHP handling reference present"
        } 2>/dev/null
    )"

    [ -n "$out" ] && echo "$out"
}

nginx_vuln_check() {
    paths="$(service_config_paths nginx)"
    out="$(
        {
            echo "[+] Nginx findings"

            grep_service_files '^[[:space:]]*autoindex[[:space:]]+on;?' $paths | head -n 5 \
                && echo "  [!] autoindex on present"

            grep_service_files '^[[:space:]]*dav_methods[[:space:]]' $paths | head -n 5 \
                && echo "  [!] WebDAV methods enabled"

            grep_service_files 'location[[:space:]]+~[[:space:]].*\.php|fastcgi_pass' $paths | head -n 5 \
                && echo "  [+] PHP/FastCGI handling present"

            grep_service_files '^[[:space:]]*client_max_body_size[[:space:]]+[0-9]{2,}[mMgG];?' $paths | head -n 5 \
                && echo "  [!] Large upload size configured"
        } 2>/dev/null
    )"

    [ -n "$out" ] && echo "$out"
}

mysql_vuln_check() {
    paths="$(service_config_paths mysql)"
    out="$(
        {
            echo "[+] MySQL/MariaDB findings"

            grep_service_files '^[[:space:]]*skip-networking[[:space:]]*=?[[:space:]]*0?([[:space:]]|$)' $paths | head -n 5 >/dev/null

            grep_service_files '^[[:space:]]*bind-address[[:space:]]*=[[:space:]]*0\.0\.0\.0([[:space:]]|$)' $paths | head -n 5 \
                && echo "  [!] bind-address=0.0.0.0 present"

            grep_service_files '^[[:space:]]*skip-grant-tables([[:space:]]|$)|^[[:space:]]*skip-grant-tables[[:space:]]*=[[:space:]]*1([[:space:]]|$)' $paths | head -n 5 \
                && echo "  [!] skip-grant-tables present"

            grep_service_files '^[[:space:]]*local-infile[[:space:]]*=[[:space:]]*1([[:space:]]|$)|^[[:space:]]*local_infile[[:space:]]*=[[:space:]]*1([[:space:]]|$)' $paths | head -n 5 \
                && echo "  [!] local-infile enabled"

            grep_service_files '^[[:space:]]*skip-name-resolve([[:space:]]|$)|^[[:space:]]*skip_name_resolve([[:space:]]|$)' $paths | head -n 5 \
                && echo "  [+] skip-name-resolve present"
        } 2>/dev/null
    )"

    [ -n "$out" ] && echo "$out"
}

postgres_vuln_check() {
    paths="$(service_config_paths postgres)"
    out="$(
        {
            echo "[+] PostgreSQL findings"

            for p in $paths; do
                if [ -f "$p/pg_hba.conf" ]; then
                    grep -HinE '^[[:space:]]*host[[:space:]]+all[[:space:]]+all[[:space:]]+0\.0\.0\.0/0[[:space:]]+(trust|md5|password)' "$p/pg_hba.conf" 2>/dev/null | head -n 5 \
                        && echo "  [!] Broad 0.0.0.0/0 host rule present"
                    grep -HinE '^[[:space:]]*local[[:space:]]+all[[:space:]]+all[[:space:]]+trust([[:space:]]|$)' "$p/pg_hba.conf" 2>/dev/null | head -n 5 \
                        && echo "  [!] local trust authentication present"
                fi
                if [ -f "$p/postgresql.conf" ]; then
                    grep -HinE '^[[:space:]]*listen_addresses[[:space:]]*=[[:space:]]*'\''\*'\''' "$p/postgresql.conf" 2>/dev/null | head -n 5 \
                        && echo "  [!] listen_addresses='*' present"
                fi
            done
        } 2>/dev/null
    )"

    [ -n "$out" ] && echo "$out"
}

php_vuln_check() {
    paths="$(service_config_paths php)"
    out="$(
        {
            echo "[+] PHP findings"

            grep_service_files '^[[:space:]]*display_errors[[:space:]]*=[[:space:]]*On([[:space:]]|$)' $paths | head -n 5 \
                && echo "  [!] display_errors=On present"

            grep_service_files '^[[:space:]]*allow_url_include[[:space:]]*=[[:space:]]*On([[:space:]]|$)' $paths | head -n 5 \
                && echo "  [!] allow_url_include=On present"

            grep_service_files '^[[:space:]]*allow_url_fopen[[:space:]]*=[[:space:]]*On([[:space:]]|$)' $paths | head -n 5 \
                && echo "  [+] allow_url_fopen=On present"

            grep_service_files '^[[:space:]]*expose_php[[:space:]]*=[[:space:]]*On([[:space:]]|$)' $paths | head -n 5 \
                && echo "  [!] expose_php=On present"

            grep_service_files '^[[:space:]]*disable_functions[[:space:]]*=' $paths | head -n 5 \
                && echo "  [+] disable_functions configured"
        } 2>/dev/null
    )"

    [ -n "$out" ] && echo "$out"
}

smb_vuln_check() {
    paths="$(service_config_paths smbd)"
    out="$(
        {
            echo "[+] Samba findings"

            grep_service_files '^[[:space:]]*map[[:space:]]+to[[:space:]]+guest[[:space:]]*=[[:space:]]*Bad User' $paths | head -n 5 \
                && echo "  [!] map to guest = Bad User present"

            grep_service_files '^[[:space:]]*guest[[:space:]]+ok[[:space:]]*=[[:space:]]*yes' $paths | head -n 5 \
                && echo "  [!] guest ok = yes present"

            grep_service_files '^[[:space:]]*guest[[:space:]]+only[[:space:]]*=[[:space:]]*yes' $paths | head -n 5 \
                && echo "  [!] guest only = yes present"

            grep_service_files '^[[:space:]]*writable[[:space:]]*=[[:space:]]*yes|^[[:space:]]*write[[:space:]]+ok[[:space:]]*=[[:space:]]*yes' $paths | head -n 5 \
                && echo "  [!] Writable share setting present"

            grep_service_files '^[[:space:]]*browseable[[:space:]]*=[[:space:]]*yes' $paths | head -n 5 \
                && echo "  [+] browseable shares present"
        } 2>/dev/null
    )"

    [ -n "$out" ] && echo "$out"
}

snmp_vuln_check() {
    paths="$(service_config_paths snmpd)"
    out="$(
        {
            echo "[+] SNMP findings"

            grep_service_files '^[[:space:]]*rocommunity[[:space:]]+public([[:space:]]|$)' $paths | head -n 5 \
                && echo "  [!] rocommunity public present"

            grep_service_files '^[[:space:]]*rwcommunity[[:space:]]+' $paths | head -n 5 \
                && echo "  [!] rwcommunity present"

            grep_service_files '^[[:space:]]*rocommunity6[[:space:]]+public([[:space:]]|$)' $paths | head -n 5 \
                && echo "  [!] rocommunity6 public present"

            grep_service_files '^[[:space:]]*agentAddress[[:space:]].*0\.0\.0\.0' $paths | head -n 5 \
                && echo "  [!] agentAddress bound broadly"
        } 2>/dev/null
    )"

    [ -n "$out" ] && echo "$out"
}

squid_vuln_check() {
    paths="$(service_config_paths squid)"
    out="$(
        {
            echo "[+] Squid findings"

            grep_service_files '^[[:space:]]*http_access[[:space:]]+allow[[:space:]]+all([[:space:]]|$)' $paths | head -n 5 \
                && echo "  [!] http_access allow all present"

            grep_service_files '^[[:space:]]*acl[[:space:]]+localnet[[:space:]]+src[[:space:]]+0\.0\.0\.0/0' $paths | head -n 5 \
                && echo "  [!] localnet defined as 0.0.0.0/0"

            grep_service_files '^[[:space:]]*http_port[[:space:]]+[0-9]+' $paths | head -n 5 \
                && echo "  [+] Squid http_port configured"
        } 2>/dev/null
    )"

    [ -n "$out" ] && echo "$out"
}

telnet_vuln_check() {
    out="$(
        {
            echo "[+] Telnet findings"
            echo "  [!] Telnet service detected"
        } 2>/dev/null
    )"
    [ -n "$out" ] && echo "$out"
}

cockpit_vuln_check() {
    paths="$(service_config_paths cockpit)"
    out="$(
        {
            echo "[+] Cockpit findings"
            echo "  [!] Cockpit service detected"

            grep_service_files '^[[:space:]]*AllowUnencrypted[[:space:]]*=[[:space:]]*true' $paths | head -n 5 \
                && echo "  [!] AllowUnencrypted=true present"
        } 2>/dev/null
    )"
    [ -n "$out" ] && echo "$out"
}

xinetd_vuln_check() {
    out="$(
        {
            echo "[+] xinetd findings"
            [ -d /etc/xinetd.d ] && echo "  [+] /etc/xinetd.d present"

            grep_service_files '^[[:space:]]*disable[[:space:]]*=[[:space:]]*no([[:space:]]|$)' /etc/xinetd.d 2>/dev/null | head -n 10 \
                && echo "  [!] Enabled xinetd service entries present"
        } 2>/dev/null
    )"
    [ -n "$out" ] && echo "$out"
}

service_vuln_inventory() {
    SERVICES="$1"

    print_section "SERVICE MISCONFIG FINDINGS"

    VULN_OUT="$(
        {
            checkService "$SERVICES" "ssh" "" >/dev/null 2>&1 && ssh_vuln_check
            checkService "$SERVICES" "vsftpd" "" >/dev/null 2>&1 && vsftpd_vuln_check
            checkService "$SERVICES" "proftpd" "" >/dev/null 2>&1 && proftpd_vuln_check
            checkService "$SERVICES" "pure-ftpd" "" >/dev/null 2>&1 && pureftpd_vuln_check
            { checkService "$SERVICES" "tftpd" "" >/dev/null 2>&1 || checkService "$SERVICES" "atftpd" "" >/dev/null 2>&1; } && tftp_vuln_check
            { checkService "$SERVICES" "apache2" "" >/dev/null 2>&1 || checkService "$SERVICES" "httpd" "" >/dev/null 2>&1; } && apache_vuln_check
            checkService "$SERVICES" "nginx" "" >/dev/null 2>&1 && nginx_vuln_check
            { checkService "$SERVICES" "mysql" "" >/dev/null 2>&1 || checkService "$SERVICES" "mariadb" "" >/dev/null 2>&1; } && mysql_vuln_check
            checkService "$SERVICES" "postgres" "" >/dev/null 2>&1 && postgres_vuln_check
            checkService "$SERVICES" "php" "" >/dev/null 2>&1 && php_vuln_check
            { checkService "$SERVICES" "smbd" "" >/dev/null 2>&1 || checkService "$SERVICES" "nmbd" "" >/dev/null 2>&1; } && smb_vuln_check
            checkService "$SERVICES" "snmpd" "" >/dev/null 2>&1 && snmp_vuln_check
            checkService "$SERVICES" "squid" "" >/dev/null 2>&1 && squid_vuln_check
            checkService "$SERVICES" "telnet" "" >/dev/null 2>&1 && telnet_vuln_check
            checkService "$SERVICES" "cockpit" "" >/dev/null 2>&1 && cockpit_vuln_check
            { checkService "$SERVICES" "xinetd" "" >/dev/null 2>&1 || checkService "$SERVICES" "inetd" "" >/dev/null 2>&1; } && xinetd_vuln_check
        } 2>/dev/null
    )"

    if [ -n "$VULN_OUT" ]; then
        echo "$VULN_OUT"
        write_text_file "$ENUM_ROOT/service_misconfigs.txt" "$VULN_OUT"
    else
        echo "No common service misconfig findings from enabled checks"
        write_text_file "$ENUM_ROOT/service_misconfigs.txt" "No common service misconfig findings from enabled checks"
    fi
}

mysql_inventory() {
    SERVICES="$1"

    if checkService "$SERVICES" "mysql" "" >/dev/null 2>&1 || checkService "$SERVICES" "mariadb" "" >/dev/null 2>&1; then
        print_section "MYSQL / MARIADB"

        MYSQL_OUT="$(
            {
                echo "[+] MySQL/MariaDB config locations"
                get_mysql_config_paths
                echo
                echo "[+] MySQL/MariaDB key config lines"
                get_mysql_config_paths | while read -r p; do
                    [ -n "$p" ] || continue
                    echo "--- $p"
                    if [ -f "$p" ]; then
                        grep -HiE '^\s*(bind-address|port|socket|user|skip-networking|skip-name-resolve|skip-grant-tables|local-infile|local_infile)' "$p" 2>/dev/null | head -n 20
                    elif [ -d "$p" ]; then
                        for f in "$p"/*; do
                            [ -f "$f" ] || continue
                            grep -HiE '^\s*(bind-address|port|socket|user|skip-networking|skip-name-resolve|skip-grant-tables|local-infile|local_infile)' "$f" 2>/dev/null | head -n 10
                        done
                    fi
                done
                echo
            } 2>/dev/null
        )"

        echo "$MYSQL_OUT"
        write_text_file "$ENUM_ROOT/mysql_mariadb.txt" "$MYSQL_OUT"
    else
        write_text_file "$ENUM_ROOT/mysql_mariadb.txt" "mysql/mariadb not detected"
    fi
}

postgres_inventory() {
    SERVICES="$1"

    if checkService "$SERVICES" "postgres" "" >/dev/null 2>&1; then
        print_section "POSTGRESQL"

        POSTGRES_OUT="$(
            {
                echo "[+] PostgreSQL config locations"
                get_postgres_config_paths
                echo
                echo "[+] PostgreSQL auth/config findings"
                get_postgres_config_paths | while read -r p; do
                    [ -n "$p" ] || continue
                    echo "--- $p"

                    if [ -f "$p/pg_hba.conf" ]; then
                        grep -Ev '^\s*#|^\s*$' "$p/pg_hba.conf" 2>/dev/null | grep -E 'local|host' | head -n 20
                    elif [ -f "$p" ] && [ "$(basename "$p")" = "pg_hba.conf" ]; then
                        grep -Ev '^\s*#|^\s*$' "$p" 2>/dev/null | grep -E 'local|host' | head -n 20
                    else
                        ls -1 "$p" 2>/dev/null | grep -E 'pg_hba\.conf|postgresql\.conf' | sed "s#^#  [+] #"
                    fi
                done
                echo
            } 2>/dev/null
        )"

        echo "$POSTGRES_OUT"
        write_text_file "$ENUM_ROOT/postgresql.txt" "$POSTGRES_OUT"
    else
        write_text_file "$ENUM_ROOT/postgresql.txt" "postgres not detected"
    fi
}

check_web_permissions_fast() {
    echo "[+] Web root permission findings"

    get_web_root_candidates | while read -r rootdir; do
        [ -d "$rootdir" ] || continue
        echo "--- $rootdir"

        WWF_COUNT="$(ls -ld "$rootdir" "$rootdir"/* 2>/dev/null | awk '$1 ~ /.......w./ && $1 !~ /^d/ {c++} END {print c+0}')"
        WWD_COUNT="$(ls -ld "$rootdir" "$rootdir"/* 2>/dev/null | awk '$1 ~ /^d/ && $1 ~ /.......w./ {c++} END {print c+0}')"
        EXEC_SCRIPT_COUNT="$(ls -l "$rootdir"/* 2>/dev/null | awk '/\.(php|phtml|jsp|jspx|asp|aspx|cgi|pl|py|sh)$/ && $1 ~ /x/ {c++} END {print c+0}')"

        echo "  [+] world-writable files (shallow): $WWF_COUNT"
        echo "  [+] world-writable directories (shallow): $WWD_COUNT"
        echo "  [+] executable dynamic/script files (shallow): $EXEC_SCRIPT_COUNT"

        [ "$WWF_COUNT" -gt 0 ] && echo "  [!] World-writable files exist"
        [ "$WWD_COUNT" -gt 0 ] && echo "  [!] World-writable directories exist"
        [ "$EXEC_SCRIPT_COUNT" -gt 0 ] && echo "  [+] Executable server-side script files exist"
    done

    echo
}

check_webshell_indicators_fast() {
    echo "[+] Webshell indicator findings"
    echo "[!] Heuristic only"

    get_web_root_candidates | while read -r rootdir; do
        [ -d "$rootdir" ] || continue
        echo "--- $rootdir"

        SUSP_NAME_COUNT="$(ls -1A "$rootdir" "$rootdir"/* 2>/dev/null | grep -Ei '(cmd|shell|wshell|wso|c99|r57|b374k|mini_shell|priv8|upload|uploader|mailer|backdoor)\.(php|phtml|php[0-9]?|jsp|jspx|asp|aspx|cgi|pl|py|sh)$' | wc -l | tr -d ' ')"
        HIDDEN_COUNT="$(ls -1A "$rootdir" 2>/dev/null | grep '^\.' | wc -l | tr -d ' ')"
        SUSP_CODE_COUNT="$(grep -RniE '(base64_decode\s*\(|eval\s*\(|assert\s*\(|shell_exec\s*\(|system\s*\(|passthru\s*\(|exec\s*\(|popen\s*\(|proc_open\s*\(|cmd\.exe|/bin/sh|powershell|gzinflate\s*\(|str_rot13\s*\(|preg_replace\s*\(.*\/e|create_function\s*\()' "$rootdir" 2>/dev/null | head -n 20 | wc -l | tr -d ' ')"

        echo "  [+] suspicious filenames: $SUSP_NAME_COUNT"
        echo "  [+] suspicious code-string hits: $SUSP_CODE_COUNT"
        echo "  [+] hidden files/directories in root: $HIDDEN_COUNT"

        [ "$SUSP_NAME_COUNT" -gt 0 ] && echo "  [!] Suspicious webshell-like filenames exist"
        [ "$SUSP_CODE_COUNT" -gt 0 ] && echo "  [!] Suspicious code patterns exist"
        [ "$HIDDEN_COUNT" -gt 0 ] && echo "  [!] Hidden files/directories exist"
    done

    echo
}

web_server_inventory() {
    SERVICES="$1"
    found_web=false

    if checkService "$SERVICES" "apache2" "" >/dev/null 2>&1 || \
       checkService "$SERVICES" "httpd" "" >/dev/null 2>&1 || \
       checkService "$SERVICES" "nginx" "" >/dev/null 2>&1 || \
       checkService "$SERVICES" "lighttpd" "" >/dev/null 2>&1 || \
       checkService "$SERVICES" "caddy" "" >/dev/null 2>&1; then
        found_web=true
    fi

    if [ "$found_web" != true ]; then
        write_text_file "$ENUM_ROOT/web_review.txt" "No supported web server detected"
        return 0
    fi

    print_section "WEB SERVER REVIEW"

    WEB_OUT="$(
        {
            if checkService "$SERVICES" "apache2" "" >/dev/null 2>&1 || checkService "$SERVICES" "httpd" "" >/dev/null 2>&1; then
                print_service_config_locations apache
                check_service_config_findings apache
            fi

            if checkService "$SERVICES" "nginx" "" >/dev/null 2>&1; then
                print_service_config_locations nginx
                check_service_config_findings nginx
            fi

            if checkService "$SERVICES" "lighttpd" "" >/dev/null 2>&1; then
                print_service_config_locations lighttpd
                check_service_config_findings lighttpd
            fi

            if checkService "$SERVICES" "caddy" "" >/dev/null 2>&1; then
                print_service_config_locations caddy
                check_service_config_findings caddy
            fi

            check_web_permissions_fast
            check_webshell_indicators_fast
        } 2>/dev/null
    )"

    echo "$WEB_OUT"
    write_text_file "$ENUM_ROOT/web_review.txt" "$WEB_OUT"
}

main_inventory() {
    setup_colors
    init_cache_dirs

    print_header
    print_section "HOST INFORMATION"

    HOST="$(DPRINT hostname || DPRINT cat /etc/hostname)"
    OS="$(grep PRETTY_NAME /etc/*-release 2>/dev/null | head -n 1 | sed 's/PRETTY_NAME=//' | sed 's/"//g')"
    IPS="$(get_ips)"

    if [ "$IS_RHEL" = true ] || [ "$IS_ALPINE" = true ]; then
        SUDOGROUP="$(grep '^wheel:' /etc/group 2>/dev/null | cut -d: -f1,4)"
    else
        SUDOGROUP="$(grep '^sudo:' /etc/group 2>/dev/null | cut -d: -f1,4)"
    fi

    SUDOERS="$(get_sudoers_summary)"
    SUIDS="$(find /bin /sbin /usr/bin /usr/sbin -perm -4000 -type f 2>/dev/null | grep -E '/(bash|sh|find|vim|nmap|docker|kubectl|ssh|sudo|pkexec|python|perl|tar|cp|mv|rsync|openssl|less|more|wget|curl|tmux)$' | head -n 30)"
    WORLDWRITEABLES="$(find /usr /bin /sbin /var/www /lib -perm -o=w -type f 2>/dev/null | grep -E '(authorized_keys|shadow|passwd|sudoers|cron|ssh|nginx|apache|httpd|kube|docker|service|conf|\.sh$)' | head -n 30)"

    HOST_INFO_OUT="$(
        {
            echo "[+] Hostname: $HOST"
            echo "[+] OS: $OS"
            echo "[+] IPs:"
            echo "$IPS"
            echo
            echo "[+] Sudo group:"
            echo "$SUDOGROUP"
            echo
            echo "[+] Sudoers summary:"
            echo "$SUDOERS"
            echo
            echo "[+] Interesting SUID files:"
            echo "$SUIDS"
            echo
            echo "[+] Interesting world-writeable files:"
            echo "$WORLDWRITEABLES"
            echo
        } 2>/dev/null
    )"

    echo "$HOST_INFO_OUT"
    write_text_file "$ENUM_ROOT/host_info.txt" "$HOST_INFO_OUT"
    write_text_file "$ENUM_ROOT/sudoers.txt" "$SUDOERS"

    USERS_OUT="$(get_local_users)"
    write_text_file "$ENUM_ROOT/local_users.txt" "$USERS_OUT"

    SS_OUT="$(get_ss_output)"
    write_text_file "$ENUM_ROOT/ss_tulpn.txt" "$SS_OUT"

    domain_inventory

    print_section "SERVICE INFORMATION"
    SERVICES="$(get_service_list)"

    : > "$ENUM_ROOT/services.txt" 2>/dev/null

    for svc in ssh docker cockpit apache2 httpd nginx lighttpd caddy mysql mariadb postgres mssql-server php python vsftpd pure-ftpd proftpd xinetd inetd tftpd atftpd smbd nmbd snmpd ypbind rshd rexecd rlogin telnet squid; do
        if checkService "$SERVICES" "$svc" "" >/dev/null 2>&1; then
            echo "[+] $svc"
            echo "$svc" >> "$ENUM_ROOT/services.txt" 2>/dev/null
            create_service_backup_dirs "$svc"
        fi
    done
    echo

    service_vuln_inventory "$SERVICES"
    docker_inventory
    mysql_inventory "$SERVICES"
    postgres_inventory "$SERVICES"
    kubernetes_inventory
    web_server_inventory "$SERVICES"

    echo "[+] Backup directory root"
    echo "$BACKUP_ROOT"
    ls -1 "$BACKUP_ROOT" 2>/dev/null
    echo

    {
        echo "[+] enum directory"
        echo "$ENUM_ROOT"
        ls -1 "$ENUM_ROOT" 2>/dev/null
        echo
        echo "[+] backup directory"
        echo "$BACKUP_ROOT"
        ls -1 "$BACKUP_ROOT" 2>/dev/null
    } > "$ENUM_ROOT/cache_paths.txt" 2>/dev/null

    echo -e "\n${GREEN}##########################End of Output#########################${NC}"
}

detect_os
bootstrap_tmux
main_inventory
