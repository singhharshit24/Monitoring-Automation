#!/bin/bash

source ./variables.sh

# Set EKS cluster name and AWS region
# CLUSTER_NAME="app-observability"  # Replace with your EKS cluster name
# AWS_REGION="ap-south-1"          # Replace with your AWS region

# Function to check if a command exists
command_exists() {
  command -v "$1" &>/dev/null
}

# Ensure required CLI tools are installed
for cmd in eksctl kubectl aws helm; do
  if ! command_exists $cmd; then
    echo "Error: $cmd is not installed. Please install it before running this script."
    exit 1
  fi
done

# Check if the EBS CSI Driver is installed
echo "🔍 Checking if the AWS EBS CSI Driver is installed in the EKS cluster..."
if kubectl get pods -n kube-system | grep -q "ebs-csi-controller"; then
  echo "✅ EBS CSI Driver is already installed."
else
  echo "⚠️ EBS CSI Driver is not installed. Proceeding with installation..."
  
  # Check if OIDC provider is enabled for the EKS cluster
  echo "🔍 Checking if OIDC provider is configured..."
  OIDC_PROVIDER=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text)

  if [ -z "$OIDC_PROVIDER" ] || [[ "$OIDC_PROVIDER" == "None" ]]; then
    echo "⚠️ No OIDC provider found. Adding OIDC provider to the EKS cluster..."
    eksctl utils associate-iam-oidc-provider --region $AWS_REGION --cluster $CLUSTER_NAME --approve
    
    # Verify if OIDC is successfully associated
    NEW_OIDC_PROVIDER=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text)
    if [ -z "$NEW_OIDC_PROVIDER" ] || [[ "$NEW_OIDC_PROVIDER" == "None" ]]; then
      echo "❌ Failed to associate OIDC provider. Exiting."
      exit 1
    fi

    echo "✅ OIDC provider added successfully."
  else
    echo "✅ OIDC provider already exists: $OIDC_PROVIDER"
  fi

  # Ensure Node IAM Role has AmazonEBSCSIDriverPolicy
  echo "🔍 Checking if Node IAM Role has the required permissions..."
  NODE_ROLE_ARN=$(aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name <NODEGROUP_NAME> --query "nodegroup.nodeRole" --output text)
  if [ -z "$NODE_ROLE_ARN" ]; then
    echo "❌ Unable to fetch Node IAM Role. Ensure the nodegroup exists."
    exit 1
  fi

  echo "🔗 Attaching AmazonEBSCSIDriverPolicy to Node IAM Role..."
  aws iam attach-role-policy --role-name $(basename $NODE_ROLE_ARN) --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy
  echo "✅ IAM policy attached successfully."

  # Check if IMDSv2 is enforced (which may block credential access)
  echo "🔍 Checking IMDS settings for EC2 nodes..."
  INSTANCE_IDS=$(aws ec2 describe-instances --filters "Name=tag:eks:cluster-name,Values=$CLUSTER_NAME" --query "Reservations[].Instances[].InstanceId" --output text)

  for INSTANCE_ID in $INSTANCE_IDS; do
    METADATA_OPTIONS=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query "Reservations[].Instances[].MetadataOptions" --output json)
    if echo "$METADATA_OPTIONS" | grep -q '"HttpTokens": "required"'; then
      echo "⚠️ IMDSv2 is enforced on $INSTANCE_ID. Modifying to allow optional IMDS access..."
      aws ec2 modify-instance-metadata-options --instance-id $INSTANCE_ID --http-tokens optional
      echo "✅ IMDS settings updated for $INSTANCE_ID."
    fi
  done

  # Install the AWS EBS CSI Driver
  echo "🔧 Installing AWS EBS CSI Driver..."
  eksctl create iamserviceaccount \
    --name ebs-csi-controller-sa \
    --namespace kube-system \
    --cluster $CLUSTER_NAME \
    --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
    --approve \
    --region $AWS_REGION

  echo "🔧 Enabling EBS CSI Driver for the EKS cluster..."
  aws eks update-cluster-config --region $AWS_REGION --name $CLUSTER_NAME --resources-vpc-config endpointPrivateAccess=true,endpointPublicAccess=true

  echo "🚀 Deploying EBS CSI Driver using Helm..."
  helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver/
  helm repo update
  helm install aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver \
    --namespace kube-system \
    --set controller.serviceAccount.create=false \
    --set controller.serviceAccount.name=ebs-csi-controller-sa

  # Restart the EBS CSI driver to apply changes
  echo "🔄 Restarting EBS CSI Controller to apply IAM role changes..."
  kubectl rollout restart deployment -n kube-system ebs-csi-controller

  echo "✅ AWS EBS CSI Driver installed and configured successfully."
fi
