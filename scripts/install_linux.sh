#!/bin/bash
echo "===================================================="
echo "SnapDNS Service Installer (Linux Systemd)"
echo "===================================================="

if [ "$EUID" -ne 0 ]; then 
  echo "[ERROR] Please run with sudo: sudo ./install_linux.sh"
  exit
fi

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
chmod +x "$DIR/SnapDnsService"
chmod +x "$DIR/snapdns"

UNIT_FILE="/etc/systemd/system/snapdns.service"

cat <<EOF > $UNIT_FILE
[Unit]
Description=SnapDNS Background Service
After=network.target

[Service]
ExecStart=$DIR/SnapDnsService
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

# Hardening: Lock unit file permissions so standard users cannot write or overwrite the service file
chmod 644 $UNIT_FILE

systemctl daemon-reload
systemctl enable snapdns.service
systemctl start snapdns.service

echo "[SUCCESS] Service installed and started! You can now run the snapdns app."