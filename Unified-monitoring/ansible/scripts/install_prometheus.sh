#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Variables
PROMETHEUS_VERSION="3.1.0"
PROMETHEUS_ARCHIVE="prometheus-$PROMETHEUS_VERSION.linux-amd64.tar.gz"
PROMETHEUS_URL="https://github.com/prometheus/prometheus/releases/download/v$PROMETHEUS_VERSION/$PROMETHEUS_ARCHIVE"
PROMETHEUS_DIR="prometheus-$PROMETHEUS_VERSION.linux-amd64"

# Step 1: Download and extract Prometheus
wget $PROMETHEUS_URL

tar xvfz $PROMETHEUS_ARCHIVE
rm $PROMETHEUS_ARCHIVE

# Step 2: Create necessary directories
sudo mkdir -p /etc/prometheus /var/lib/prometheus

# Step 3: Move binaries and configuration
cd $PROMETHEUS_DIR
sudo mv prometheus promtool /usr/local/bin/
sudo mv prometheus.yml /etc/prometheus/prometheus.yml
#sudo mv consoles/ console_libraries/ /etc/prometheus/

# Step 4: Create Prometheus user
sudo useradd -rs /bin/false prometheus
sudo chown -R prometheus: /etc/prometheus /var/lib/prometheus

# Step 5: Create systemd service file
sudo tee /etc/systemd/system/prometheus.service > /dev/null << EOF
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
Restart=on-failure
RestartSec=5s
ExecStart=/usr/local/bin/prometheus \\
    --config.file /etc/prometheus/prometheus.yml \\
    --storage.tsdb.path /var/lib/prometheus/ \\
    --web.console.templates=/etc/prometheus/consoles \\
    --web.console.libraries=/etc/prometheus/console_libraries \\
    --web.listen-address=0.0.0.0:9090 \\
    --web.enable-lifecycle \\
    --log.level=info

[Install]
WantedBy=multi-user.target
EOF

# Step 6: Reload systemd, enable and start Prometheus
sudo systemctl daemon-reload
sudo systemctl enable prometheus
sudo systemctl start prometheus

# Print success message
echo "Prometheus installation and configuration complete. Access it at http://<your-server-ip>:9090"

