#!/bin/sh
# @d_tranman/Nigel Gerald/Nigerald
sys=$(command -v service || command -v systemctl)
FILE=/etc/ssh/sshd_config
RC=/etc/rc.d/rc.sshd

if [ -f $FILE ]; then
    sed -i 's/^AllowTcpForwarding/# AllowTcpForwarding/' $FILE; echo 'AllowTcpForwarding no' >> $FILE
    sed -i 's/^X11Forwarding/# X11Forwarding/' $FILE; echo 'X11Forwarding no' >> $FILE
else
    echo "Could not find sshd config"
fi

if [[ -z $sys ]]; then
  if [ -f "/etc/rc.d/sshd" ]; then
    RC="/etc/rc.d/sshd"
  else
    RC="/etc/rc.d/rc.sshd"
  $RC restart
else
  $sys restart ssh || $sys ssh restart || $sys restart sshd || $sys sshd restart 
fi
