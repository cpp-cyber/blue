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
# Thanks UCI

sys=$(command -v service || command -v systemctl || command -v rc-service)

for file in $(find / -name 'php.ini' 2>/dev/null); do
	echo "disable_functions = 1e, exec, system, shell_exec, passthru, popen, curl_exec, curl_multi_exec, parse_file_file, show_source, proc_open, pcntl_exec/" >> $file
	echo "track_errors = off" >> $file
	echo "html_errors = off" >> $file
	echo "max_execution_time = 3" >> $file
	echo "display_errors = off" >> $file
	echo "short_open_tag = off" >> $file
	echo "session.cookie_httponly = 1" >> $file
	echo "session.use_only_cookies = 1" >> $file
	echo "session.cookie_secure = 1" >> $file
	echo "expose_php = off" >> $file
	echo "magic_quotes_gpc = off " >> $file
	echo "allow_url_fopen = off" >> $file
	echo "allow_url_include = off" >> $file
	echo "register_globals = off" >> $file
	echo "file_uploads = off" >> $file

	echo $file changed

done;

if [ -d /etc/nginx ]; then
	$sys nginx restart || $sys restart nginx
	echo nginx restarted
fi

if [ -d /etc/apache2 ]; then
	$sys apache2 restart || $sys restart apache2
	echo apache2 restarted
fi

if [ -d /etc/httpd ]; then
	$sys httpd restart || $sys restart httpd
	echo httpd restarted
fi

if [ -d /etc/lighttpd ]; then
	$sys lighttpd restart || $sys restart lighttpd
	echo lighttpd restarted
fi

file=$(find /etc -maxdepth 2 -type f -name 'php-fpm*' -print -quit)

if [ -d /etc/php/*/fpm ] || [ -n "$file" ]; then
        $sys *php* restart || $sys restart *php*
        echo php-fpm restarted
fi