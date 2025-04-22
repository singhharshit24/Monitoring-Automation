#!/bin/bash

# Update package list
echo "Updating package list..."
sudo apt update

# Install required dependencies
echo "Installing required dependencies..."
sudo apt-get install -y gnupg2 curl software-properties-common

# Add Grafana GPG key
echo "Adding Grafana GPG key..."
curl https://packages.grafana.com/gpg.key | sudo apt-key add -

# Add Grafana APT repository without prompt
echo "Adding Grafana APT repository..."
echo "deb https://packages.grafana.com/oss/deb stable main" | sudo tee /etc/apt/sources.list.d/grafana.list

# Update package list again after adding the repository
echo "Updating package list again..."
sudo apt update

# Install Grafana
echo "Installing Grafana..."
sudo apt -y install grafana

# Create provisioning directory if it doesn't exist
echo "Setting up Grafana provisioning directory..."
sudo mkdir -p /etc/grafana/provisioning/datasources
sudo chown -R grafana:grafana /etc/grafana/provisioning

# Add Prometheus datasource configuration
echo "Adding Prometheus as the default datasource for Grafana..."
sudo tee /etc/grafana/provisioning/datasources/prometheus-datasource.yaml > /dev/null <<EOF
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    url: http://localhost:9090
    access: proxy
    isDefault: true
EOF

# Ensure proper permissions
sudo chown grafana:grafana /etc/grafana/provisioning/datasources/prometheus-datasource.yaml

# Start Grafana service
echo "Starting Grafana service..."
sudo systemctl start grafana-server

# Enable Grafana to start on boot
echo "Enabling Grafana service to start on boot..."
sudo systemctl enable grafana-server

echo "Grafana installation and Prometheus datasource configuration completed successfully!"
