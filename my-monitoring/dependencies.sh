#!/bin/bash

set -e  # Exit on error

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}


echo "Checking and installing required dependencies: kubectl, eksctl, aws-cli, and helm..."

# Detect OS
ios_type="$(uname -s | tr '[:upper:]' '[:lower:]')"

install_unzip() {
    if ! command_exists unzip; then
        echo "Installing unzip..."
        if command_exists apt; then
            sudo apt update && sudo apt install -y unzip
        elif command_exists yum; then
            sudo yum install -y unzip
        elif command_exists dnf; then
            sudo dnf install -y unzip
        elif command_exists brew; then
            brew install unzip
        else
            echo "Unsupported OS: Cannot install unzip. Please install it manually."
            exit 1
        fi
    fi
}

install_unzip 

install_aws_cli() {
    echo "Installing AWS CLI..."
    if [[ "$ios_type" == "darwin" ]]; then
        brew install awscli
    else
        curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip -q awscliv2.zip
        sudo ./aws/install
        rm -rf awscliv2.zip aws
    fi
}

install_kubectl() {
    echo "Installing kubectl..."
    
    # Fetch the latest stable version (fix redirect issue by adding -L)
    KUBECTL_VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)

    # Debugging: Print the retrieved version
    echo "Retrieved kubectl version: '$KUBECTL_VERSION'"

    # Validate the version
    if [[ -z "$KUBECTL_VERSION" ]]; then
        echo "Error: Failed to fetch the latest kubectl version."
        exit 1
    fi

    # Download kubectl
    KUBECTL_URL="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
    echo "Downloading from: $KUBECTL_URL"
    curl -LO "$KUBECTL_URL"

    # Verify if the file was downloaded
    if [[ ! -f "kubectl" ]]; then
        echo "Error: Failed to download kubectl."
        exit 1
    fi

    # Install kubectl
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm -f kubectl
}

install_helm() {
    echo "Installing Helm..."
    if [[ "$ios_type" == "darwin" ]]; then
        brew install helm
    else
        curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi
}

install_eksctl() {
    echo "Installing eksctl..."
    if [[ "$ios_type" == "darwin" ]]; then
        brew install eksctl
    else
        curl -sL "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" | tar xz -C /tmp
        sudo mv /tmp/eksctl /usr/local/bin/
    fi
}

# Install missing tools
if ! command_exists aws; then install_aws_cli; else echo "AWS CLI is already installed."; fi
if ! command_exists kubectl; then install_kubectl; else echo "kubectl is already installed."; fi
if ! command_exists helm; then install_helm; else echo "Helm is already installed."; fi
if ! command_exists eksctl; then install_eksctl; else echo "eksctl is already installed."; fi

# Verify installations
echo "Installed versions:"
aws --version || echo "AWS CLI not found"
kubectl version --client --output=yaml || echo "kubectl not found"
helm version || echo "Helm not found"
eksctl version || echo "eksctl not found"

echo "All required tools are installed!"
