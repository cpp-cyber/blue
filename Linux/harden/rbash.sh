#!/bin/sh
# @d_tranman/Nigel Gerald/Nigerald

if [ ! -z "$REVERT" ]; then
    cp /etc/passwd.bak /etc/passwd
else
    cp /etc/passwd /etc/passwd.bak
    chmod 644 /etc/passwd.bak

    if ! which rbash 1> /dev/null 2>& 1 ; then
        ln -sf /bin/bash /bin/rbash
    fi

    if command -v bash 1> /dev/null 2>& 1 ; then
        head -1 /etc/passwd > /etc/pw
        sed -n '1!p' /etc/passwd | sed 's/\/bin\/.*sh$/\/bin\/rbash/g' >> /etc/pw
        mv /etc/pw /etc/passwd
        chmod 644 /etc/passwd
    fi

    for file in $(find /etc /home -name *.*shrc -exec ls {} \;); do
        echo 'PATH=""' >> $file
        echo 'export PATH' >> $file
        if command -v apk >/dev/null; then
            echo 'export PATH' >> $file
        fi
    done
fi
