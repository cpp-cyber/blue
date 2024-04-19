#!/bin/sh

if [ -z "$1" ]; then
    echo "Missing DL IP"
    exit 1
fi

if [ -z "$2" ]; then
    echo "Missing Allowed IP"
    exit 1
fi
DL=$1

RHEL(){
    IS_RHEL=true
    ES="http://$DL/elasticsearch-8.13.2-x86_64.rpm"
    KB="http://$DL/kibana-8.13.2-x86_64.rpm"
    FB="http://$DL/filebeat-8.13.2-x86_64.rpm"
    curl -L -s -O $ES
    if [ $? -ne 0 ]; then
        echo "Failed to download elasticsearch"
        exit 1
    fi
    curl -L -s -O $KB
    if [ $? -ne 0 ]; then
        echo "Failed to download kibana"
        exit 1
    fi
    curl -L -s -O $FB
    if [ $? -ne 0 ]; then
        echo "Failed to download filebeat"
        exit 1
    fi

    rpm -i elasticsearch-8.13.2-x86_64.rpm 
    rpm -i kibana-8.13.2-x86_64.rpm 
    rpm -i filebeat-8.13.2-x86_64.rpm
    systemctl stop firewalld
}

DEBIAN(){
    # Todo: Add better checks for the files
    wget http://$DL/elasticsearch-8.13.2-amd64.deb
    if [ $? -ne 0 ]; then
        echo "Failed to download elasticsearch"
        exit 1
    fi
    wget http://$DL/kibana-8.13.2-amd64.deb
    if [ $? -ne 0 ]; then
        echo "Failed to download kibana"
        exit 1
    fi
    wget http://$DL/filebeat-8.13.2-amd64.deb
    if [ $? -ne 0 ]; then
        echo "Failed to download filebeat"
        exit 1
    fi
    dpkg -i elasticsearch-8.13.2-amd64.deb kibana-8.13.2-amd64.deb filebeat-8.13.2-amd64.deb
}

UBUNTU(){
    DEBIAN
}

if command -v yum >/dev/null ; then
    RHEL
elif command -v apt-get >/dev/null ; then
    if $(cat /etc/os-release | grep -qi Ubuntu); then
        UBUNTU
    else
        DEBIAN
    fi
fi


TMP=$(mktemp)


systemctl daemon-reload
systemctl enable elasticsearch
systemctl enable kibana

systemctl start elasticsearch

iptables -A INPUT -p tcp -s $2 --dport 5601 -j ACCEPT
iptables -A INPUT -p tcp --dport 5601 -j DROP

/usr/share/kibana/bin/kibana-encryption-keys generate | tail -4 >> /etc/kibana/kibana.yml
echo 'server.host: "0.0.0.0"' >> /etc/kibana/kibana.yml
token=$(/usr/share/elasticsearch/bin/elasticsearch-create-enrollment-token  --scope kibana)
/usr/share/kibana/bin/kibana-setup --enrollment-token=$token 

systemctl restart kibana

# Testing stuff with filebeat
CA=$(openssl x509 -fingerprint -sha256 -noout -in /etc/elasticsearch/certs/http_ca.crt | awk -F '=' '{print $2}' | sed 's/://g')
if [ -z "$IS_RHEL" ]; then
    PASS=$(yes | /usr/share/elasticsearch/bin/elasticsearch-reset-password -s -u 'elastic')
else
    PASS=$(yes | /usr/share/elasticsearch/bin/elasticsearch-reset-password -s -u 'elastic'| awk -F '[y/N]' '{print $1}')
fi
echo $PASS
sed -e 's/hosts: \["localhost:9200"\]/hosts: \["https:\/\/localhost:9200"\]/g; /hosts: \["https:\/\/localhost:9200"\]/a \ \n  username: "elastic"\n  password: "'"$PASS"'"\n  ssl:\n    enabled: true\n    ca_trusted_fingerprint: "'"$CA"'"' /etc/filebeat/filebeat.yml > $TMP
mv $TMP /etc/filebeat/filebeat.yml
filebeat setup --index-management -E output.logstash.enabled=false  -E "output.elasticsearch.ssl.enabled=true" -E "output.elasticsearch.ssl.ca_trusted_fingerprint=$CA" -E 'output.elasticsearch.hosts=["https://127.0.0.1:9200"]'

cat << EOF >> /etc/filebeat/filebeat.yml


# ----- This is an example filestream config for later. More needs testing -----
#filebeat.inputs:
#  - type: filestream
#    id: remote
#    enabled: true
#    paths:
#      - /var/log/remote/192.*/*.log
# # Change to correct subnet. Don't include 127.0.0.1


# ----- Stuff for rsyslog server -----
#module(load="imudp")
#input(type="imudp" port="514")
#
#\$AllowedSender UDP, 192.168.1.1/24 # Set this to local subnet
#
#\$template RemInputLogs, "/var/log/remote/%FROMHOST-IP%-%SOURCE%/%PROGRAMNAME%.log"
#*.* ?RemInputLogs
EOF
