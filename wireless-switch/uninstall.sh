#!/bin/bash
set -e

if [[ $EUID -ne 0 ]]; then
    echo "Run as root"
    exit 1
fi

systemctl disable --now letsnote-wireless-switch.service 2>/dev/null || true
rm -f /usr/local/bin/letsnote-wireless-switch.sh
rm -f /etc/systemd/system/letsnote-wireless-switch.service
rm -f /etc/modules-load.d/ec_sys.conf
systemctl daemon-reload

echo "Uninstalled."
