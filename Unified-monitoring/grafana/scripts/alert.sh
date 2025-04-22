#!/bin/bash
# Download Alertmanager binary
wget https://github.com/prometheus/alertmanager/releases/download/v0.27.0/alertmanager-0.27.0.linux-386.tar.gz
# Create Alertmanager user and group (if they don't exist)
sudo groupadd -f alertmanager || true
sudo useradd -g alertmanager --no-create-home --shell /bin/false alertmanager || true
# Create Alertmanager directories
sudo mkdir -p /etc/alertmanager/templates /var/lib/alertmanager
# Set ownership of Alertmanager directories
sudo chown alertmanager:alertmanager /etc/alertmanager /var/lib/alertmanager
# Extract Alertmanager archive
tar -xvf alertmanager-0.27.0.linux-386.tar.gz
# Move extracted directory
mv alertmanager-0.27.0.linux-386 alertmanager-files
# Copy Alertmanager binary and tool to system binaries directory
sudo cp alertmanager-files/alertmanager /usr/bin/
sudo cp alertmanager-files/amtool /usr/bin/
# Set ownership of Alertmanager binary and tool
sudo chown alertmanager:alertmanager /usr/bin/alertmanager
sudo chown alertmanager:alertmanager /usr/bin/amtool
# Copy Alertmanager configuration file
sudo cp alertmanager-files/alertmanager.yml /etc/alertmanager/alertmanager.yml
# Set ownership of Alertmanager configuration file
sudo chown alertmanager:alertmanager /etc/alertmanager/alertmanager.yml
# Clean up downloaded archive
rm alertmanager-0.27.0.linux-386.tar.gz
# Remove temporary directory (optional)
# rm -rf alertmanager-files
# Create Systemd service file
cat <<EOF > /etc/systemd/system/alertmanager.service
[Unit]
Description=Alertmanager
Wants=network-online.target
After=network-online.target
[Service]
User=alertmanager
Group=alertmanager
Type=simple
ExecStart=/usr/bin/alertmanager \
    --config.file /etc/alertmanager/alertmanager.yml \
    --storage.path /var/lib/alertmanager/
Restart=on-failure
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF
# Reload systemd and enable/start Alertmanager service
sudo systemctl daemon-reload
sudo systemctl enable alertmanager
sudo systemctl start alertmanager
# Check Alertmanager service status
sudo systemctl status alertmanager
echo "Alertmanager installation and service setup complete!"
