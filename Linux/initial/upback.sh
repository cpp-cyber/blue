#!/bin/sh

# backup services quickly - adam
# can specify specific service if you only wanna backup one

SERVICES_FILE="/root/.cache/enum/services.txt"
BACKUP_ROOT="/root/.cache/backup"

log() {
    printf '%s\n' "$*"
}

warn() {
    printf 'WARNING: %s\n' "$*" >&2
}

ensure_dir() {
    if [ ! -d "$1" ]; then
        mkdir -p "$1" || {
            warn "Failed to create directory: $1"
            return 1
        }
    fi
    return 0
}

reset_service_backup_dir() {
    service="$1"
    service_dir="$BACKUP_ROOT/$service"

    rm -rf "$service_dir" || {
        warn "Failed to remove old backup directory: $service_dir"
        return 1
    }

    ensure_dir "$service_dir/config" || return 1
    ensure_dir "$service_dir/others" || return 1
    return 0
}

copy_to_subdir() {
    service="$1"
    subdir="$2"
    src="$3"

    [ -e "$src" ] || return 0

    base="$(basename "$src")"
    dest="$BACKUP_ROOT/$service/$subdir/$base"

    cp -a "$src" "$dest" || {
        warn "Failed to copy $src to $dest"
        return 1
    }

    log "  copied to $subdir: $src"
    return 0
}

copy_config() {
    copy_to_subdir "$1" "config" "$2"
}

copy_other() {
    copy_to_subdir "$1" "others" "$2"
}

backup_mysql_dump() {
    service="$1"
    outdir="$BACKUP_ROOT/$service/others"
    outfile="$outdir/mysql_all_databases.sql"

    if command -v mysqldump >/dev/null 2>&1; then
        if mysqldump --all-databases > "$outfile" 2>/dev/null; then
            log "  dumped all MySQL/MariaDB databases to $outfile"
            return 0
        fi
        warn "mysqldump failed for service $service"
        rm -f "$outfile"
        return 1
    fi

    warn "mysqldump not found; skipping full database dump for $service"
    return 1
}

backup_postgresql_dump() {
    service="$1"
    outdir="$BACKUP_ROOT/$service/others"
    outfile="$outdir/postgresql_all_databases.sql"

    if command -v pg_dumpall >/dev/null 2>&1; then
        if command -v su >/dev/null 2>&1; then
            if su postgres -s /bin/sh -c "pg_dumpall" > "$outfile" 2>/dev/null; then
                log "  dumped all PostgreSQL databases to $outfile"
                return 0
            fi
        elif command -v runuser >/dev/null 2>&1; then
            if runuser -u postgres -- pg_dumpall > "$outfile" 2>/dev/null; then
                log "  dumped all PostgreSQL databases to $outfile"
                return 0
            fi
        fi

        warn "pg_dumpall failed for service $service"
        rm -f "$outfile"
        return 1
    fi

    warn "pg_dumpall not found; skipping full database dump for $service"
    return 1
}

backup_ssh() {
    service="ssh"
    log "[*] Backing up $service"
    reset_service_backup_dir "$service" || return 1

    copy_config "$service" "/etc/ssh/sshd_config"
    copy_config "$service" "/etc/ssh/sshd_config.d"
    copy_config "$service" "/etc/default/ssh"
}

backup_vsftpd() {
    service="vsftpd"
    log "[*] Backing up $service"
    reset_service_backup_dir "$service" || return 1

    copy_config "$service" "/etc/vsftpd.conf"
    copy_config "$service" "/etc/vsftpd"
    copy_other "$service" "/srv/ftp"
    copy_other "$service" "/var/ftp"
    copy_other "$service" "/var/www/html"
}

backup_apache2() {
    service="apache2"
    log "[*] Backing up $service"
    reset_service_backup_dir "$service" || return 1

    copy_config "$service" "/etc/apache2"
    copy_other "$service" "/var/www/html"
}

backup_httpd() {
    service="httpd"
    log "[*] Backing up $service"
    reset_service_backup_dir "$service" || return 1

    copy_config "$service" "/etc/httpd"
    copy_other "$service" "/var/www/html"
}

backup_nginx() {
    service="nginx"
    log "[*] Backing up $service"
    reset_service_backup_dir "$service" || return 1

    copy_config "$service" "/etc/nginx"
    copy_other "$service" "/usr/share/nginx/html"
    copy_other "$service" "/var/www/html"
}

backup_tftpd() {
    service="tftpd"
    log "[*] Backing up $service"
    reset_service_backup_dir "$service" || return 1

    copy_config "$service" "/etc/default/tftpd-hpa"
    copy_config "$service" "/etc/xinetd.d/tftp"
    copy_config "$service" "/etc/systemd/system/tftp.service"
    copy_config "$service" "/etc/systemd/system/tftp.socket"
    copy_other "$service" "/var/lib/tftpboot"
    copy_other "$service" "/srv/tftp"
}

backup_named() {
    service="named"
    log "[*] Backing up $service"
    reset_service_backup_dir "$service" || return 1

    copy_config "$service" "/etc/named.conf"
    copy_config "$service" "/etc/named"
    copy_other "$service" "/var/named"
}

backup_bind9() {
    service="bind9"
    log "[*] Backing up $service"
    reset_service_backup_dir "$service" || return 1

    copy_config "$service" "/etc/bind"
    copy_config "$service" "/etc/default/named"
    copy_other "$service" "/var/cache/bind"
}

backup_dnsmasq() {
    service="dnsmasq"
    log "[*] Backing up $service"
    reset_service_backup_dir "$service" || return 1

    copy_config "$service" "/etc/dnsmasq.conf"
    copy_config "$service" "/etc/dnsmasq.d"
    copy_config "$service" "/etc/default/dnsmasq"
}

backup_smb() {
    service="smb"
    log "[*] Backing up $service"
    reset_service_backup_dir "$service" || return 1

    copy_config "$service" "/etc/samba/smb.conf"
    copy_config "$service" "/etc/samba"
}

backup_smbd() {
    service="smbd"
    log "[*] Backing up $service"
    reset_service_backup_dir "$service" || return 1

    copy_config "$service" "/etc/samba/smb.conf"
    copy_config "$service" "/etc/samba"
}

backup_nfs() {
    service="nfs"
    log "[*] Backing up $service"
    reset_service_backup_dir "$service" || return 1

    copy_config "$service" "/etc/exports"
    copy_config "$service" "/etc/nfs.conf"
    copy_config "$service" "/etc/default/nfs-kernel-server"
}

backup_rpcbind() {
    service="rpcbind"
    log "[*] Backing up $service"
    reset_service_backup_dir "$service" || return 1

    copy_config "$service" "/etc/hosts.allow"
    copy_config "$service" "/etc/hosts.deny"
}

backup_mysql() {
    service="mysql"
    log "[*] Backing up $service"
    reset_service_backup_dir "$service" || return 1

    copy_config "$service" "/etc/mysql"
    copy_config "$service" "/etc/my.cnf"
    copy_config "$service" "/etc/my.cnf.d"
    copy_other "$service" "/var/lib/mysql"
    backup_mysql_dump "$service"
}

backup_mariadb() {
    service="mariadb"
    log "[*] Backing up $service"
    reset_service_backup_dir "$service" || return 1

    copy_config "$service" "/etc/my.cnf"
    copy_config "$service" "/etc/my.cnf.d"
    copy_config "$service" "/etc/mysql"
    copy_other "$service" "/var/lib/mysql"
    backup_mysql_dump "$service"
}

backup_postgresql() {
    service="postgresql"
    log "[*] Backing up $service"
    reset_service_backup_dir "$service" || return 1

    copy_config "$service" "/etc/postgresql"
    copy_config "$service" "/var/lib/pgsql/data/postgresql.conf"
    copy_config "$service" "/var/lib/pgsql/data/pg_hba.conf"
    copy_other "$service" "/var/lib/postgresql"
    copy_other "$service" "/var/lib/pgsql"
    backup_postgresql_dump "$service"
}

backup_proftpd() {
    service="proftpd"
    log "[*] Backing up $service"
    reset_service_backup_dir "$service" || return 1

    copy_config "$service" "/etc/proftpd"
    copy_other "$service" "/srv/ftp"
    copy_other "$service" "/var/ftp"
}

backup_pureftpd() {
    service="pure-ftpd"
    log "[*] Backing up $service"
    reset_service_backup_dir "$service" || return 1

    copy_config "$service" "/etc/pure-ftpd"
    copy_other "$service" "/srv/ftp"
    copy_other "$service" "/var/ftp"
}

backup_haproxy() {
    service="haproxy"
    log "[*] Backing up $service"
    reset_service_backup_dir "$service" || return 1

    copy_config "$service" "/etc/haproxy"
}

backup_dovecot() {
    service="dovecot"
    log "[*] Backing up $service"
    reset_service_backup_dir "$service" || return 1

    copy_config "$service" "/etc/dovecot"
    copy_other "$service" "/var/mail"
}

backup_postfix() {
    service="postfix"
    log "[*] Backing up $service"
    reset_service_backup_dir "$service" || return 1

    copy_config "$service" "/etc/postfix"
    copy_other "$service" "/var/spool/postfix"
}

backup_service() {
    svc="$1"

    case "$svc" in
        ssh) backup_ssh ;;
        vsftpd) backup_vsftpd ;;
        apache2) backup_apache2 ;;
        httpd) backup_httpd ;;
        nginx) backup_nginx ;;
        tftpd|tftp|tftpd-hpa) backup_tftpd ;;
        named) backup_named ;;
        bind9) backup_bind9 ;;
        dnsmasq) backup_dnsmasq ;;
        smb) backup_smb ;;
        smbd) backup_smbd ;;
        nfs|nfs-server|nfs-kernel-server) backup_nfs ;;
        rpcbind) backup_rpcbind ;;
        mysql) backup_mysql ;;
        mariadb) backup_mariadb ;;
        postgresql|postgres) backup_postgresql ;;
        proftpd) backup_proftpd ;;
        pure-ftpd|pureftpd) backup_pureftpd ;;
        haproxy) backup_haproxy ;;
        dovecot) backup_dovecot ;;
        postfix) backup_postfix ;;
        "")
            ;;
        *)
            warn "No backup mapping defined for service: $svc"
            ;;
    esac
}

backup_all_from_file() {
    if [ ! -f "$SERVICES_FILE" ]; then
        warn "Services file not found: $SERVICES_FILE"
        return 1
    fi

    while IFS= read -r svc || [ -n "$svc" ]; do
        [ -z "$svc" ] && continue
        backup_service "$svc"
    done < "$SERVICES_FILE"
}

main() {
    ensure_dir "$BACKUP_ROOT" || exit 1

    if [ $# -ge 1 ]; then
        backup_service "$1"
    else
        backup_all_from_file
    fi
}

main "$@"
