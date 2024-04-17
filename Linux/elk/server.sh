#!/bin/sh

if [ -z "$1" ]; then
    echo "Missing DL IP"
    exit 1
fi

wget http://$1/elasticsearch-8.13.2-amd64.deb
wget http://$1/kibana-8.13.2-amd64.deb

sudo dpkg -i elasticsearch-8.13.2-amd64.deb kibana-8.13.2-amd64.deb

sudo systemctl daemon-reload
sudo systemctl enable elasticsearch
sudo systemctl enable kibana

sudo systemctl start elasticsearch
/usr/share/kibana/bin/kibana-encryption-keys generate | tail -4 >> /etc/kibana/kibana.yml
systemctl restart kibana

/usr/share/elasticsearch/bin/elasticsearch-create-enrollment-token  --scope kibana
/usr/share/kibana/bin/kibana-verification-code
yes | /usr/share/elasticsearch/bin/elasticsearch-reset-password -u 'elastic' 
