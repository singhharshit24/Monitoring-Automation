#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Step 1: Install prerequisites
sudo apt-get install -y software-properties-common wget

# Step 2: Add Grafana GPG key and repository
sudo wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key
echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main" | sudo tee -a /etc/apt/sources.list.d/grafana.list

# Step 3: Update package list and install Grafana
sudo apt-get update
sudo apt-get install -y grafana

# Step 3.5: Create provisioning directory if it doesn't exist
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

# Step 4: Start and enable Grafana service
sudo systemctl daemon-reload
sudo systemctl start grafana-server
sudo systemctl enable grafana-server

# Print success message
echo "Grafana installation complete. Access it at http://<your-server-ip>:3000 with default credentials (admin/admin)."
