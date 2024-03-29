#!/bin/sh
# @d_tranman/Nigel Gerald/Nigerald and c0ve

RHEL(){
    yum check-update -y >/dev/null
    yum install net-tools iproute sed curl wget bash -y > /dev/null
    yum install iptraf -y >/dev/null

    yum install auditd -y > /dev/null
    yum install rsyslog -y > /dev/null
}

DEBIAN(){
    apt-get -qq update >/dev/null
    apt-get -qq install net-tools iproute2 sed curl wget bash -y >/dev/null
    apt-get -qq install iptraf -y >/dev/null

    apt-get -qq install auditd rsyslog -y >/dev/null
}

UBUNTU(){
  DEBIAN
}

ALPINE(){
    echo "http://mirrors.ocf.berkeley.edu/alpine/v3.16/community" >> /etc/apk/repositories
    apk update >/dev/null
    apk add iproute2 net-tools curl wget bash iptraf-ng iptables util-linux-misc >/dev/null

    apk add audit rsyslog >/dev/null

}

SLACK(){
  echo "Slack is cringe"
}

if command -v yum >/dev/null ; then
    RHEL
elif command -v apt-get >/dev/null ; then
    if $(cat /etc/os-release | grep -qi Ubuntu); then
        UBUNTU
    else
        DEBIAN
    fi
elif command -v apk >/dev/null ; then
    ALPINE
elif command -v slapt-get >/dev/null || (cat /etc/os-release | grep -i slackware >/dev/null) ; then
    SLACK
fi


# backup /etc/passwd
mkdir /root/.cache
cp /etc/passwd /root/.cache/users

# check our ports
( netstat -tlpn 2>/dev/null || ss -plnt 2>/dev/null ) > /root/.cache/listen
( netstat -tpwn 2>/dev/null || ss -pnt | grep ESTAB 2>/dev/null ) > /root/.cache/estab

# pam
mkdir /etc/pam.d/pam/
cp -R /etc/pam.d/ /root/.cache/pam

# profiles
for f in '.profile' '.*shrc' '.*sh_login'; do
    find /home /root -name "$f" -exec rm {} \;
done

# php
grep -rl "disable_fun" /etc/ | xargs sed -ri "s/^(disable_fun.*)/\1e, exec, system, shell_exec, passthru, popen, curl_exec, curl_multi_exec, parse_ini_file, show_source, proc_open, pcntl_exec/g"

for ini in $(find /etc -name php.ini 2>/dev/null); do
    echo "expose_php = Off" >> $ini
    echo "track_errors = Off" >> $ini
    echo "html_errors = Off" >> $ini
    echo "file_uploads = Off" >> $ini
    echo "session.cookie_httponly = 1" >> $ini
    echo "disable_functions = exec, system, shell_exec, passthru, popen, curl_exec, curl_multi_exec, parse_ini_file, show_source, proc_open, pcntl_exec" >> $ini
	echo "max_execution_time = 3" >> $ini
	echo "register_globals = off" >> $ini
	echo "magic_quotes_gpc = on" >> $ini
	echo "allow_url_fopen = off" >> $ini
	echo "allow_url_include = off" >> $ini
	echo "display_errors = off" >> $ini
	echo "short_open_tag = off" >> $ini
	echo "session.cookie_httponly = 1" >> $ini
	echo "session.use_only_cookies = 1" >> $ini
	echo "session.cookie_secure = 1" >> $ini
done 

