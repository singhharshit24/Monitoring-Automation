#!/bin/bash

# Install Node Exporter on a remote server
set -e

# Usage: ./install_node_exporter.sh <remote_ip> <username> <key_path>

REMOTE_IP=$1
USERNAME=$2
KEY_PATH=$3

echo "Installing Node Exporter on $REMOTE_IP..."

# Download and install Node Exporter
ssh -o "StrictHostKeyChecking no" -i "$KEY_PATH" "$USERNAME@$REMOTE_IP" << 'ENDSSH'
    wget https://github.com/prometheus/node_exporter/releases/download/v1.3.1/node_exporter-1.3.1.linux-amd64.tar.gz
    tar xvf node_exporter-1.3.1.linux-amd64.tar.gz
    cd node_exporter-1.3.1.linux-amd64
    nohup ./node_exporter &> node_exporter.log &
    sudo cp node_exporter /usr/local/bin
ENDSSH

echo "Node Exporter installation initiated on $REMOTE_IP."
