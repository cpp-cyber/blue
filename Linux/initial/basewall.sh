#!/bin/sh
# @d_tranman/Nigel Gerald/Nigerald

ipt=$(command -v iptables || command -v /sbin/iptables || command -v /usr/sbin/iptables)

ALLOW() {
    $ipt -P INPUT ACCEPT; $ipt -P OUTPUT ACCEPT ; $ipt -P FORWARD ACCEPT ; $ipt -F; $ipt -X
}
CHECKERR() {
    if [ ! $? -eq 0 ]; then
        echo "ERROR, EXITTING TO PREVENT LOCKOUT"
        ALLOW
        exit 1
    fi
}

if [ -z "$ipt" ]; then
    echo "NO IPTABLES ON THIS SYSTEM, GOOD LUCK"
    exit 1
fi

if [ -z "$DISPATCHER" ]; then
    echo "DISPATCHER not defined."
    exit 1
fi

if [ -z "$LOCALNETWORK" ]; then
    echo "LOCALNETWORK not defined."
    exit 1
fi

if [ -z "$CCSHOST" ] && [ -z "$NOTNATS" ]; then
    echo "CCSHOST not defined and WE ARE AT NATS BRO!"
    exit 1
fi

iptables-save > /opt/rules.v4
iptables-save > /root/.cache/rules.v4
ALLOW

$ipt -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
$ipt -A OUTPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

if [ -n "$CCSHOST" ]; then
    $ipt -A OUTPUT -d $CCSHOST -j ACCEPT
    CHECKERR
    $ipt -A INPUT -s $CCSHOST -j ACCEPT
    CHECKERR
fi

$ipt -A OUTPUT -d 127.0.0.1,$LOCALNETWORK -m conntrack --ctstate NEW -j ACCEPT 
CHECKERR

$ipt -A INPUT -p udp -m multiport --dports 53,514 -s 127.0.0.1,$LOCALNETWORK -j ACCEPT
CHECKERR
$ipt -A OUTPUT -p udp -m multiport --dports 53,514 -s 127.0.0.1,$LOCALNETWORK -j ACCEPT
CHECKERR

$ipt -A INPUT -s 127.0.0.1 -j ACCEPT

###
# Allow ssh from coordinate host
$ipt -A INPUT -p tcp --dport 22 -s $DISPATCHER -j ACCEPT
CHECKERR

# Block access to control plane outside of localhost. Hope theres only 1 node
$ipt -A INPUT -p tcp --dport 6443 ! -s 127.0.0.1 -j DROP 

# Ingress chain 
$ipt -N MAYBESUS

# Allow all NEW inbound from trusted network, block otherwise
$ipt -A MAYBESUS -s 127.0.0.1,$LOCALNETWORK -j ACCEPT
CHECKERR
$ipt -A MAYBESUS -j DROP

# Drop inbound to certain ports from outside of trusted network
# Some auth ports
$ipt -A INPUT -p tcp -m multiport --dports 23,139,445,9000,9090 -j MAYBESUS
$ipt -A INPUT -p tcp --dport 22 -j MAYBESUS # Risky business

# DB Ports 
$ipt -A INPUT -p tcp -m multiport --dports 1433,3306,5432 -j MAYBESUS

# Drop inbound to certain ports from outside of trusted network -- containerized stuff
$ipt -A FORWARD -p tcp -m multiport --dports 9000,9090 -j MAYBESUS
$ipt -A FORWARD -p tcp -m multiport --dports 1433,3306,5432 -j MAYBESUS

# So containers don't cry
if command -v 'kubectl' > /dev/null ; then
    systemctl restart k3s
fi

if command -v 'docker' > /dev/null ; then
    systemctl restart docker
fi

###
$ipt -P FORWARD ACCEPT; 

# Drop outbound via direct rule rather than policy
$ipt -A OUTPUT -j DROP; 

echo "Done"

iptables-save > /opt/rules.v4
iptables-save > /root/.cache/rules.v4
