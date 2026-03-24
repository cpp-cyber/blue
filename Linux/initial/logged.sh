#!/bin/sh

# make log panes hopefully - adam

SESSION_NAME="$1"
WINDOW_NAME_PREFIX="${2:-service-logs}"
SERVICES_FILE="/root/.cache/enum/services.txt"
MAX_PANES=4

if ! command -v tmux >/dev/null 2>&1; then
    echo "[!] tmux is not installed."
    exit 1
fi

if [ -z "$SESSION_NAME" ]; then
    echo "Usage: $0 <tmux_session_name> [window_name_prefix]"
    exit 1
fi

if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo "[!] tmux session '$SESSION_NAME' does not exist."
    exit 1
fi

if [ ! -f "$SERVICES_FILE" ]; then
    echo "[!] Services file not found: $SERVICES_FILE"
    exit 1
fi

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

has_systemd() {
    has_cmd journalctl && [ -d /run/systemd/system ]
}

service_exists() {
    svc="$1"

    if has_cmd systemctl; then
        systemctl list-unit-files --type=service 2>/dev/null | grep -q "^$svc\.service"
        return $?
    fi

    return 1
}

pick_file() {
    for f in "$@"; do
        if [ -f "$f" ]; then
            echo "$f"
            return 0
        fi
    done
    return 1
}

join_files() {
    out=""
    for f in "$@"; do
        if [ -f "$f" ]; then
            if [ -z "$out" ]; then
                out="'$f'"
            else
                out="$out '$f'"
            fi
        fi
    done
    echo "$out"
}

normalize_service() {
    case "$1" in
        ssh|sshd)
            echo "ssh"
            ;;
        apache|apache2|httpd)
            echo "apache"
            ;;
        nginx)
            echo "nginx"
            ;;
        mariadb|mysql|mysqld)
            echo "mariadb"
            ;;
        vsftpd)
            echo "vsftpd"
            ;;
        tftpd|tftp|tftpd-hpa|in.tftpd|atftpd)
            echo "tftpd"
            ;;
        samba|smb|smbd)
            echo "samba"
            ;;
        bind|bind9|named)
            echo "bind"
            ;;
        docker)
            echo "docker"
            ;;
        *)
            echo "$1"
            ;;
    esac
}

journal_cmd() {
    for unit in "$@"; do
        if service_exists "$unit"; then
            echo "exec journalctl -fu $unit.service"
            return 0
        fi
    done

    if [ -n "$1" ]; then
        echo "exec journalctl -fu $1.service"
        return 0
    fi

    return 1
}

build_command() {
    svc="$1"

    case "$svc" in
        ssh)
            if has_systemd; then
                if service_exists ssh; then
                    echo "ssh|echo '[ssh] Following journald entries for ssh.service'; exec journalctl -fu ssh.service -n 50"
                    return 0
                fi

                if service_exists sshd; then
                    echo "ssh|echo '[ssh] Following journald entries for sshd.service'; exec journalctl -fu sshd.service -n 50"
                    return 0
                fi
            fi

            LOG="$(pick_file \
                /var/log/auth.log \
                /var/log/secure \
                /var/log/messages \
                /var/log/syslog)"
            if [ -n "$LOG" ]; then
                echo "ssh|echo '[ssh] Following $LOG'; exec tail -n 50 -F '$LOG'"
                return 0
            fi
            return 1
            ;;

        apache)
            LOGS="$(join_files \
                /var/log/apache2/access.log \
                /var/log/apache2/error.log \
                /var/log/httpd/access_log \
                /var/log/httpd/error_log \
                /usr/local/apache/logs/access_log \
                /usr/local/apache/logs/error_log)"
            if [ -n "$LOGS" ]; then
                echo "apache|echo '[apache] Following Apache logs'; exec tail -n 50 -F $LOGS"
                return 0
            fi

            if has_systemd; then
                echo "apache|echo '[apache] Following journald'; $(journal_cmd apache2 httpd)"
                return 0
            fi
            return 1
            ;;

        nginx)
            LOGS="$(join_files \
                /var/log/nginx/access.log \
                /var/log/nginx/error.log \
                /usr/local/nginx/logs/access.log \
                /usr/local/nginx/logs/error.log)"
            if [ -n "$LOGS" ]; then
                echo "nginx|echo '[nginx] Following Nginx logs'; exec tail -n 50 -F $LOGS"
                return 0
            fi

            if has_systemd; then
                echo "nginx|echo '[nginx] Following journald'; $(journal_cmd nginx)"
                return 0
            fi
            return 1
            ;;

        mariadb)
            LOGS="$(join_files \
                /var/log/mysql/error.log \
                /var/log/mysql/mysql.log \
                /var/log/mysql/mysqld.log \
                /var/log/mariadb/mariadb.log \
                /var/log/mariadb/mariadb.err \
                /var/log/mysqld.log \
                /var/log/messages \
                /var/log/syslog)"
            if [ -n "$LOGS" ]; then
                echo "mariadb|echo '[mariadb] Following DB logs'; exec tail -n 50 -F $LOGS"
                return 0
            fi

            if has_systemd; then
                echo "mariadb|echo '[mariadb] Following journald'; $(journal_cmd mariadb mysql mysqld)"
                return 0
            fi
            return 1
            ;;

        vsftpd)
            if has_systemd && service_exists vsftpd; then
                echo "vsftpd|echo '[vsftpd] Following journald entries for vsftpd.service'; exec journalctl -fu vsftpd.service -n 50"
                return 0
            fi

            LOGS="$(join_files \
                /var/log/vsftpd.log \
                /var/log/xferlog \
                /var/log/messages \
                /var/log/syslog)"
            if [ -n "$LOGS" ]; then
                echo "vsftpd|echo '[vsftpd] Following FTP logs'; exec tail -n 50 -F $LOGS"
                return 0
            fi

            return 1
            ;;

        tftpd)
            LOGS="$(join_files \
                /var/log/messages \
                /var/log/syslog \
                /var/log/daemon.log)"
            if [ -n "$LOGS" ]; then
                echo "tftpd|echo '[tftpd] Following TFTP logs'; exec tail -n 50 -F $LOGS"
                return 0
            fi

            if has_systemd; then
                echo "tftpd|echo '[tftpd] Following journald'; $(journal_cmd tftpd-hpa tftpd atftpd)"
                return 0
            fi
            return 1
            ;;

        samba)
            LOGS="$(join_files \
                /var/log/samba/log.smbd \
                /var/log/samba/log.nmbd \
                /var/log/messages \
                /var/log/syslog)"
            if [ -n "$LOGS" ]; then
                echo "samba|echo '[samba] Following Samba logs'; exec tail -n 50 -F $LOGS"
                return 0
            fi

            if has_systemd; then
                echo "samba|echo '[samba] Following journald'; $(journal_cmd smbd smb)"
                return 0
            fi
            return 1
            ;;

        bind)
            LOGS="$(join_files \
                /var/log/named/named.log \
                /var/log/named.log \
                /var/log/messages \
                /var/log/syslog)"
            if [ -n "$LOGS" ]; then
                echo "bind|echo '[bind] Following DNS logs'; exec tail -n 50 -F $LOGS"
                return 0
            fi

            if has_systemd; then
                echo "bind|echo '[bind] Following journald'; $(journal_cmd named bind9)"
                return 0
            fi
            return 1
            ;;

        docker)
            LOGS="$(join_files \
                /var/log/docker.log \
                /var/log/messages \
                /var/log/syslog)"
            if [ -n "$LOGS" ]; then
                echo "docker|echo '[docker] Following Docker logs'; exec tail -n 50 -F $LOGS"
                return 0
            fi

            if has_systemd; then
                echo "docker|echo '[docker] Following journald'; $(journal_cmd docker)"
                return 0
            fi
            return 1
            ;;
    esac

    return 1
}

next_window_name() {
    base="$1"
    n=1
    candidate="$base"

    while tmux list-windows -t "$SESSION_NAME" -F '#W' | grep -qx "$candidate"; do
        n=$((n + 1))
        candidate="${base}-${n}"
    done

    echo "$candidate"
}

create_window_from_commands() {
    window_name="$1"
    commands_file="$2"

    tmux new-window -t "$SESSION_NAME" -n "$window_name"

    index=0
    while IFS= read -r CMD || [ -n "$CMD" ]; do
        [ -z "$CMD" ] && continue

        if [ "$index" -eq 0 ]; then
            tmux send-keys -t "$SESSION_NAME:$window_name.0" "sh -c \"$CMD\"" C-m
        else
            tmux split-window -t "$SESSION_NAME:$window_name" -v
            tmux select-layout -t "$SESSION_NAME:$window_name" tiled
            tmux send-keys -t "$SESSION_NAME:$window_name.$index" "sh -c \"$CMD\"" C-m
        fi

        index=$((index + 1))
    done < "$commands_file"

    tmux select-layout -t "$SESSION_NAME:$window_name" tiled
}

SERVICES_TMP="/tmp/service_log_tmux_services.$$"
COMMANDS_TMP="/tmp/service_log_tmux_commands.$$"
SEEN_TMP="/tmp/service_log_tmux_seen.$$"

: > "$SERVICES_TMP"
: > "$COMMANDS_TMP"
: > "$SEEN_TMP"

COUNT=0

while IFS= read -r raw_service || [ -n "$raw_service" ]; do
    svc="$(echo "$raw_service" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

    [ -z "$svc" ] && continue

    case "$svc" in
        \#*)
            continue
            ;;
    esac

    normalized="$(normalize_service "$svc")"

    if grep -qx "$normalized" "$SEEN_TMP" 2>/dev/null; then
        continue
    fi

    result="$(build_command "$normalized")" || continue

    display_name=$(echo "$result" | awk -F'|' '{print $1}')
    command_text=$(echo "$result" | cut -d'|' -f2-)

    echo "$normalized" >> "$SEEN_TMP"
    echo "$display_name" >> "$SERVICES_TMP"
    echo "$command_text" >> "$COMMANDS_TMP"

    COUNT=$((COUNT + 1))
done < "$SERVICES_FILE"

if [ "$COUNT" -eq 0 ]; then
    rm -f "$SERVICES_TMP" "$COMMANDS_TMP" "$SEEN_TMP"
    echo "[!] No usable logs found for services listed in $SERVICES_FILE"
    exit 1
fi

WINDOWS_CREATED_TMP="/tmp/service_log_tmux_windows.$$"
: > "$WINDOWS_CREATED_TMP"

WINDOW_COUNT=0
BATCH_CMDS_TMP=""
BATCH_COUNT=0

while IFS= read -r CMD || [ -n "$CMD" ]; do
    [ -z "$CMD" ] && continue

    if [ -z "$BATCH_CMDS_TMP" ]; then
        BATCH_CMDS_TMP="/tmp/service_log_tmux_batch_${$}_${WINDOW_COUNT}.tmp"
        : > "$BATCH_CMDS_TMP"
        BATCH_COUNT=0
    fi

    echo "$CMD" >> "$BATCH_CMDS_TMP"
    BATCH_COUNT=$((BATCH_COUNT + 1))

    if [ "$BATCH_COUNT" -ge "$MAX_PANES" ]; then
        window_name="$(next_window_name "$WINDOW_NAME_PREFIX")"
        create_window_from_commands "$window_name" "$BATCH_CMDS_TMP"
        echo "$window_name" >> "$WINDOWS_CREATED_TMP"
        rm -f "$BATCH_CMDS_TMP"
        BATCH_CMDS_TMP=""
        BATCH_COUNT=0
        WINDOW_COUNT=$((WINDOW_COUNT + 1))
    fi
done < "$COMMANDS_TMP"

if [ -n "$BATCH_CMDS_TMP" ] && [ -f "$BATCH_CMDS_TMP" ]; then
    if [ -s "$BATCH_CMDS_TMP" ]; then
        window_name="$(next_window_name "$WINDOW_NAME_PREFIX")"
        create_window_from_commands "$window_name" "$BATCH_CMDS_TMP"
        echo "$window_name" >> "$WINDOWS_CREATED_TMP"
        WINDOW_COUNT=$((WINDOW_COUNT + 1))
    fi
    rm -f "$BATCH_CMDS_TMP"
fi

echo "[+] Created $WINDOW_COUNT log window(s) in session '$SESSION_NAME'"
echo "[+] Using services from: $SERVICES_FILE"
echo "[+] Windows created:"
sed 's/^/    - /' "$WINDOWS_CREATED_TMP"
echo "[+] Services monitored:"
sed 's/^/    - /' "$SERVICES_TMP"

rm -f "$SERVICES_TMP" "$COMMANDS_TMP" "$SEEN_TMP" "$WINDOWS_CREATED_TMP"
