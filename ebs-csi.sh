#!/bin/bash

source ./variables.sh

# Set EKS cluster name and AWS region
CLUSTER_NAME="app-observability"  # Replace with your EKS cluster name
AWS_REGION="ap-south-1"          # Replace with your AWS region

# Function to check if a command exists
command_exists_1() {
  command -v "$1" &>/dev/null
}

# Ensure required CLI tools are installed
for cmd in eksctl kubectl aws; do
  if ! command_exists_1 $cmd; then
    echo "Error: $cmd is not installed. Please install it before running this script."
    exit 1
  fi
done

# Check if the EBS CSI Driver is installed
echo "Checking if the AWS EBS CSI Driver is installed in the EKS cluster..."
if kubectl get daemonset -n kube-system | grep -q "ebs-csi-controller"; then
  echo "✅ EBS CSI Driver is already installed."
else
  echo "⚠️ EBS CSI Driver is not installed. Proceeding with installation..."
  
  # Check if OIDC provider is enabled for the EKS cluster
  echo "Checking if OIDC provider is configured..."
  OIDC_PROVIDER=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text)

  if [ -z "$OIDC_PROVIDER" ] || [[ "$OIDC_PROVIDER" == "None" ]]; then
    echo "⚠️ No OIDC provider found. Adding OIDC provider to the EKS cluster..."
    eksctl utils associate-iam-oidc-provider --region $AWS_REGION --cluster $CLUSTER_NAME --approve
    echo "✅ OIDC provider added successfully."
  else
    echo "✅ OIDC provider already exists: $OIDC_PROVIDER"
  fi

  # Install the AWS EBS CSI Driver
  echo "Installing AWS EBS CSI Driver..."
  eksctl create iamserviceaccount \
    --name ebs-csi-controller-sa \
    --namespace kube-system \
    --cluster $CLUSTER_NAME \
    --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
    --approve \
    --region $AWS_REGION

  echo "Enabling EBS CSI Driver for the EKS cluster..."
  aws eks update-cluster-config --region $AWS_REGION --name $CLUSTER_NAME --resources-vpc-config endpointPrivateAccess=true,endpointPublicAccess=true

  echo "Deploying EBS CSI Driver using Helm..."
  helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver/
  helm repo update
  helm install aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver \
    --namespace kube-system \
    --set controller.serviceAccount.create=false \
    --set controller.serviceAccount.name=ebs-csi-controller-sa

  echo "✅ AWS EBS CSI Driver installed successfully."
fi
