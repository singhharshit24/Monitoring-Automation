#!/bin/bash

set -e  # Exit on error

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install missing dependencies
install_dependencies() {
    echo "Checking and installing required dependencies..."

    if ! command_exists aws; then
        echo "Installing AWS CLI..."
        curl -sL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip -q awscliv2.zip
        sudo ./aws/install
        rm -rf awscliv2.zip aws
    fi

    if ! command_exists kubectl; then
        echo "Installing kubectl..."
        KUBECTL_VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)
        curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
        sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
        rm -f kubectl
    fi

    if ! command_exists eksctl; then
        echo "Installing eksctl..."
        curl -sL "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" | tar xz -C /tmp
        sudo mv /tmp/eksctl /usr/local/bin/
    fi

    if ! command_exists jq; then
        echo "Installing jq..."
        sudo apt update && sudo apt install -y jq || sudo yum install -y jq
    fi
}

# Attach IAM Role to EC2 Instance
attach_iam_role() {
    INSTANCE_ID=$1
    IAM_ROLE=$2

    if [[ -z "$INSTANCE_ID" || -z "$IAM_ROLE" ]]; then
        echo "Usage: attach_iam_role <INSTANCE_ID> <IAM_ROLE_NAME>"
        exit 1
    fi

    echo "Attaching IAM role '$IAM_ROLE' to EC2 instance '$INSTANCE_ID'..."
    aws ec2 associate-iam-instance-profile --instance-id "$INSTANCE_ID" --iam-instance-profile Name="$IAM_ROLE"
}

# Configure AWS EKS
configure_eks() {
    EKS_CLUSTER=$1
    AWS_REGION=$2

    if [[ -z "$EKS_CLUSTER" || -z "$AWS_REGION" ]]; then
        echo "Usage: configure_eks <EKS_CLUSTER_NAME> <AWS_REGION>"
        exit 1
    fi

    echo "Updating kubeconfig for EKS cluster '$EKS_CLUSTER' in region '$AWS_REGION'..."
    aws eks update-kubeconfig --region "$AWS_REGION" --name "$EKS_CLUSTER"
}

# Main Execution
echo "Starting EC2 IAM Role attachment and EKS configuration..."

install_dependencies  # Ensure all dependencies are installed

# User input
read -p "Enter EC2 Instance ID: " INSTANCE_ID
read -p "Enter IAM Role Name: " IAM_ROLE
read -p "Enter EKS Cluster Name: " EKS_CLUSTER
read -p "Enter AWS Region (e.g., ap-south-1): " AWS_REGION

attach_iam_role "$INSTANCE_ID" "$IAM_ROLE"
configure_eks "$EKS_CLUSTER" "$AWS_REGION"

echo "✅ IAM Role attached and EKS configured successfully!"
