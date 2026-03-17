#!/bin/bash
set -e

if [[ $EUID -ne 0 ]]; then
    echo "This script needs to be executed as root."
    exit 1
fi

install -m 755 letsnote-wireless-switch.sh /usr/local/bin/letsnote-wireless-switch.sh
install -m 644 letsnote-wireless-switch.service /etc/systemd/system/letsnote-wireless-switch.service
install -m 644 ec_sys.conf /etc/modules-load.d/ec_sys.conf

modprobe ec_sys 2>/dev/null || true

systemctl daemon-reload
systemctl enable --now letsnote-wireless-switch.service

echo "Installed and started."
