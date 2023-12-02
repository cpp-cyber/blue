#!/bin/sh
# @d_tranman/Nigel Gerald/Nigerald
# This returns a hostname and the primary subnet(s?) of a machine. Useful for mass fingerprinting. Also kinda forgot is regex is working cause I wrote it a year ago

# DEBUG        - [ OPT ] If given a value, more stderr will be present.

if [ -z "$DEBUG" ]; then
    DPRINT() { 
        "$@" 2>/dev/null 
    }
else
    DPRINT() { 
        "$@" 
    }
fi

if command -v hostname >/dev/null ; then
    hostname
else
    cat /etc/hostname
fi
( DPRINT ip a 2>/dev/null | grep -oE '([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}/[[:digit:]]{1,2}' | grep -v '127.0.0.1' ) || ( DPRINT ifconfig | grep -oE 'inet.+([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}' | grep -v '127.0.0.1' )
cat /etc/*-release | grep -o 'PRETTY_NAME.*' | sed 's/\(PRETTY_NAME=\|"\)//g'
