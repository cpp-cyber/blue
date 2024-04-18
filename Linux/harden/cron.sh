#!/bin/sh
# UCI cron tech

sys=$(command -v service || command -v systemctl || command -v rc-service)

CHECKERR() {
    if [ ! $? -eq 0 ]; then
        echo "ERROR"
        exit 1
    else
        echo Success
    fi

}

if [ ! -z "$REVERT" ]; then
    if [ -f "/etc/rc.d/cron" ]; then
        /etc/rc.d/cron restart
        CHECKERR
    else
        $sys cron start || $sys restart cron || $sys crond start || $sys restart crond 
        CHECKERR
    fi
    echo "cron started"
else
    if [ -f "/etc/rc.d/cron" ]; then
        /etc/rc.d/cron stop
        CHECKERR
    else
        $sys cron stop || $sys stop cron || $sys crond stop || $sys stop crond
        CHECKERR
    fi
    echo "cron stopped"
fi