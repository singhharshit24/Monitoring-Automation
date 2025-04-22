#!/bin/bash
set -e

VERSION="1.8.2"
DOWNLOAD_URL="https://github.com/prometheus/node_exporter/releases/download/v${VERSION}/node_exporter-${VERSION}.linux-amd64.tar.gz"
INSTALL_DIR="/usr/local/bin"
SERVICE_FILE="/etc/systemd/system/node_exporter.service"

wget $DOWNLOAD_URL
tar xvfz node_exporter-*.tar.gz
sudo mv node_exporter-${VERSION}.linux-amd64/node_exporter $INSTALL_DIR
rm -r node_exporter-${VERSION}.linux-amd64*
sudo useradd -rs /bin/false node_exporter || true

sudo tee $SERVICE_FILE > /dev/null <<EOF
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
Restart=on-failure
RestartSec=5s
ExecStart=$INSTALL_DIR/node_exporter

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter
