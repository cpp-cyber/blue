#!/bin/sh
# Thank you Mr. DSU Fabriel Gawk for the gawk gawk 2000 like script that may or may not work

# To use coordinate we gotta use envvars
#PORTS = The scored ports
#LOCALPORTS = The ports we host that other machines depend on
#LOCALNETWORK = Subnet(s) of machines that depend on us and vice versa
#OUTBOUNDPORTS = The ports that our services depend on from other machines

# My poor fingers can't handle typing four more letters per line
ipt="/sbin/iptables"

# Flush the current rules
$ipt -F; $ipt -X ;$ipt -P INPUT ACCEPT ; $ipt -P OUTPUT ACCEPT ; $ipt -P FORWARD ACCEPT

# Allow our machine to respond to connections
$ipt -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
$ipt -A OUTPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# Allow scored services in
$ipt -A INPUT -p tcp -m multiport --dport 22,$PORTS -m conntrack --ctstate NEW -j ACCEPT

# Allow incoming connections to dependencies we host for other machines
$ipt -A INPUT -p tcp -m multiport --dports $LOCALPORTS -s 127.0.0.1,$LOCALNETWORK -m conntrack --ctstate NEW -j ACCEPT

# Allow outbound connetions to dependencies we need from other machines
$ipt -A OUTPUT -p tcp -m multiport --dports $OUTBOUNDPORTS -d 127.0.0.1,$LOCALNETWORK -m conntrack --ctstate NEW -j ACCEPT

# You'll also need these (and DNS) to be able to update via dnf/yum or apt.
$ipt -A INPUT -p udp --dport 53 -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
$ipt -A OUTPUT -p udp --dport 53 -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT

# Finally, the danger line: drop any traffic that doesn't match.
$ipt -P FORWARD DROP; $ipt -P OUTPUT DROP; $ipt -P INPUT DROP

iptables-save > /opt/rules.v4
