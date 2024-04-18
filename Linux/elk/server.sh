#!/bin/sh

if [ -z "$1" ]; then
    echo "Missing DL IP"
    exit 1
elif [ -z "$2" ]; then
    echo "Missing Allowed IP"
    exit 1
fi

TMP=$(mktemp)
# Todo: Add better checks for the files
wget http://$1/elasticsearch-8.13.2-amd64.deb
if [ $? -ne 0 ]; then
    echo "Failed to download elasticsearch"
    exit 1
fi
wget http://$1/kibana-8.13.2-amd64.deb
if [ $? -ne 0 ]; then
    echo "Failed to download kibana"
    exit 1
fi
wget http://$1/filebeat-8.13.2-amd64.deb
if [ $? -ne 0 ]; then
    echo "Failed to download filebeat"
    exit 1
fi

sudo dpkg -i elasticsearch-8.13.2-amd64.deb kibana-8.13.2-amd64.deb filebeat-8.13.2-amd64.deb

sudo systemctl daemon-reload
sudo systemctl enable elasticsearch
sudo systemctl enable kibana

sudo systemctl start elasticsearch

iptables -A INPUT -p tcp -s $2 --dport 5601 -j ACCEPT
iptables -A INPUT -p tcp --dport 5601 -j DROP

/usr/share/kibana/bin/kibana-encryption-keys generate | tail -4 >> /etc/kibana/kibana.yml
echo 'server.host: "0.0.0.0"' >> /etc/kibana/kibana.yml
token=$(/usr/share/elasticsearch/bin/elasticsearch-create-enrollment-token  --scope kibana)
/usr/share/kibana/bin/kibana-setup --enrollment-token=$token 

systemctl restart kibana

# Testing stuff with filebeat
export CA=$(openssl x509 -fingerprint -sha256 -noout -in /etc/elasticsearch/certs/http_ca.crt | awk --field-separator="=" '{print $2}' | sed 's/://g')
PASS=$(yes | /usr/share/elasticsearch/bin/elasticsearch-reset-password -s -u 'elastic'| awk -F '[y/N]' '{print $1}')
echo $PASS
sed -e 's/hosts: \["localhost:9200"\]/hosts: \["https:\/\/localhost:9200"\]/g; /hosts: \["https:\/\/localhost:9200"\]/a \ \n  username: "elastic"\n  password: "'"$PASS"'"\n  ssl:\n    enabled: true\n    ca_trusted_fingerprint: "'"$CA"'"' /etc/filebeat/filebeat.yml > $TMP
mv $TMP /etc/filebeat/filebeat.yml

cat << EOF >> /etc/filebeat/filebeat.yml


# ----- This is an example filestream config for later. More needs testing -----
#filebeat.inputs:
#  - type: filestream
#    id: remote
#    enabled: true
#    paths:
#      - /var/log/remote/192.*/*.log
EOF