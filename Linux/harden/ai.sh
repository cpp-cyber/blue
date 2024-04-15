#!/bin/sh

if command -v docker >/dev/null || command -v kubectl >/dev/null || command -v podman; then
    echo "Container detected, skipping"
    exit 1
fi

if [ -f /proc/sys/kernel/unprivileged_userns_clone ]; then
    sysctl -w kernel.unprivileged_userns_clone=0
fi

if [ -f /proc/sys/user/max_user_namespaces ]; then
    sysctl -w user.max_user_namespaces=0
fi
