#!/bin/sh
if [ -z "$KEY" ]; then
    echo "KEY not defined, exitting."
    exit 1
fi

echo $KEY >> ~/.ssh/authorized_keys
