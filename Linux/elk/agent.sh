#!/bin/sh

if [ -z "$SERVER" ]; then
    echo "Missing SERVER"
    exit 1
fi

if [ -z "$TOKEN" ]; then
    echo "Missing TOKEN"
    exit 1
fi

if [ -z "$DL" ]; then
    echo "Missing DL"
    exit 1
fi

DLA=$DL/elastic-agent-8.13.2-linux-x86_64.tar.gz
URL="https://$SERVER:8220"

if command -v elastic-agent 2>/dev/null; then
    echo "Agent already installed, skipping"
    exit 1;
fi
if command -v curl 2>/dev/null; then
    curl -L -s -O $DLA
elif command -v wget 2>/dev/null; then
    wget -q $DLA
else 
    echo "gg"
    exit 1;
fi

echo $DLA;
echo $URL;

tar xzvf elastic-agent-8.13.2-linux-x86_64.tar.gz
cd elastic-agent-8.13.2-linux-x86_64
./elastic-agent install --force --url=$URL --enrollment-token=$TOKEN --insecure
