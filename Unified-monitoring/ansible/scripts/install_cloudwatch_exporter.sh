#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Variables
CLOUDWATCH_VERSION="0.16.0"
CLOUDWATCH_JAR="cloudwatch_exporter-$CLOUDWATCH_VERSION-jar-with-dependencies.jar"
CLOUDWATCH_URL="https://github.com/prometheus/cloudwatch_exporter/releases/download/v$CLOUDWATCH_VERSION/$CLOUDWATCH_JAR"
INSTALL_DIR="/home/ubuntu/cloudwatch_exporter"
CONFIG_FILE="$INSTALL_DIR/config.yml"

# Step 1: Install Java
sudo apt update
sudo apt install -y default-jre

# Step 2: Download CloudWatch Exporter
mkdir -p $INSTALL_DIR
wget $CLOUDWATCH_URL -O $INSTALL_DIR/$CLOUDWATCH_JAR

# Step 3: Create systemd service file
sudo tee /etc/systemd/system/cloudwatch_exporter.service > /dev/null << EOF
[Unit]
Description=CloudWatch Exporter
After=network.target

[Service]
User=ubuntu
ExecStart=/usr/bin/java -jar $INSTALL_DIR/$CLOUDWATCH_JAR 9106 $CONFIG_FILE
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Step 3.5: create config.yml:


# Step 4: Reload systemd, enable and start CloudWatch Exporter
sudo systemctl daemon-reload
sudo systemctl enable cloudwatch_exporter
sudo systemctl start cloudwatch_exporter

# Print success message
echo "CloudWatch Exporter installation complete. Ensure the configuration file at $CONFIG_FILE is correctly set up."

