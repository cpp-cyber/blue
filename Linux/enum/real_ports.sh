#!/bin/sh

if command -v netstat >/dev/null ; then
    LIST_CMD="netstat -tulpn"
    ESTB_CMD="netstat -tupwn"
elif command -v ss >/dev/null ; then
    LIST_CMD="ss -blunt -p"
    ESTB_CMD="ss -buntp"
fi

if [ -z "$LIST_CMD" ]; then
    echo "No netstat or ss found, exitting"
fi

echo "[+] Listening"
$LIST_CMD

echo "[+] Established"
$ESTB_CMD