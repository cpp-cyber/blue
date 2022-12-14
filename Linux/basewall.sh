#!/bin/sh
# Thank you Mr. DSU Fabriel Gawk for the gawk gawk 2000 like script that may or may not work

# My poor fingers can't handle typing four more letters per line
ipt="/sbin/iptables"

#LOCALNETWORK = Subnet(s) of machines that depend on us and vice versa

# Flush the current rules
$ipt -F; $ipt -X ;$ipt -P INPUT ACCEPT ; $ipt -P OUTPUT ACCEPT ; $ipt -P FORWARD ACCEPT

# Allow our machine to respond to connections
$ipt -A OUTPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# Allow outbound connetions to dependencies we need from other machines
$ipt -A OUTPUT -d 127.0.0.1,$LOCALNETWORK -m conntrack --ctstate NEW -j ACCEPT

# Drop Output, but still allow new inbound. Allow forward for docker
$ipt -P FORWARD ACCEPT; $ipt -P OUTPUT DROP;

iptables-save > /opt/rules.v4
