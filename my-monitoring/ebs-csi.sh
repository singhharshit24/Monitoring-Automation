#!/bin/bash

set -e  # Exit on any error

### CONFIGURATION ###
CLUSTER_NAME="new-cluster"
REGION="ap-south-1"
SERVICE_ACCOUNT="ebs-csi-controller-sa"
POLICY_ARN="arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"

echo "🚀 Checking if EBS CSI Driver is installed in cluster: $CLUSTER_NAME"

### CHECK IF EBS CSI DRIVER IS INSTALLED ###
if kubectl get deployment -n kube-system | grep "ebs-csi-controller"; then
    echo "✅ EBS CSI Driver is already installed."
else
    echo "🔹 EBS CSI Driver not found. Installing..."

    # Install EBS CSI Driver as an EKS Addon
    eksctl create addon \
        --name aws-ebs-csi-driver \
        --cluster "$CLUSTER_NAME" \
        --region "$REGION" \
        --service-account-role-arn "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy" \
        --force

    echo "⏳ Waiting for EBS CSI Driver to become available..."
    sleep 30

    # Verify installation
    if kubectl get deployment -n kube-system | grep -q "ebs-csi-controller"; then
        echo "✅ EBS CSI Driver successfully installed!"
    else
        echo "❌ Installation failed. Check logs for issues."
        exit 1
    fi
fi

echo "🚀 Starting EBS CSI Driver setup for cluster: $CLUSTER_NAME in region: $REGION"

### 1️⃣ Verify OIDC Provider ###
OIDC_ISSUER=$(aws eks describe-cluster --name "$CLUSTER_NAME" --query "cluster.identity.oidc.issuer" --output text)

if [ -z "$OIDC_ISSUER" ]; then
    echo "🔹 OIDC not found. Enabling OIDC..."
    eksctl utils associate-iam-oidc-provider --region "$REGION" --cluster "$CLUSTER_NAME" --approve
else
    echo "✅ OIDC is already enabled: $OIDC_ISSUER"
fi

### 2️⃣ Create Service Account for EBS CSI Driver ###
echo "🔹 Checking if Service Account exists..."
if ! kubectl get sa -n kube-system | grep -q "$SERVICE_ACCOUNT"; then
    echo "🔹 Creating Service Account..."
    eksctl create iamserviceaccount \
        --name "$SERVICE_ACCOUNT" \
        --namespace kube-system \
        --cluster "$CLUSTER_NAME" \
        --role-name AmazonEBSCSIDriverRole \
        --attach-policy-arn "$POLICY_ARN" \
        --approve \
        --region "$REGION" \
        --override-existing-serviceaccounts
else
    echo "✅ Service Account '$SERVICE_ACCOUNT' already exists"
fi

### 3️⃣ Ensure EC2 IMDS is Configured ###
echo "🔹 Checking EC2 IMDS Configuration..."
INSTANCE_IDS=$(aws ec2 describe-instances --filters "Name=tag:eks:nodegroup-name,Values=*" --query "Reservations[].Instances[].InstanceId" --output text)

for INSTANCE_ID in $INSTANCE_IDS; do
    HTTP_TOKENS=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --query "Reservations[].Instances[].MetadataOptions.HttpTokens" --output text)
    
    if [ "$HTTP_TOKENS" == "required" ]; then
        echo "🔹 Setting IMDS to optional for instance: $INSTANCE_ID"
        aws ec2 modify-instance-metadata-options \
            --instance-id "$INSTANCE_ID" \
            --http-tokens optional \
            --region "$REGION"
    else
        echo "✅ IMDS already set to optional for instance: $INSTANCE_ID"
    fi
done

### 4️⃣ Ensure Worker Node IAM Role Has Correct Permissions ###
# echo "🔹 Attaching EBS CSI IAM policy to worker nodes..."
# NODE_ROLE_NAMES=$(aws ec2 describe-instances --filters "Name=tag:eks:nodegroup-name,Values=*" --query "Reservations[].Instances[].IamInstanceProfile.Arn" --output text | awk -F '/' '{print $2}')

# for ROLE_NAME in $NODE_ROLE_NAMES; do
#     aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY_ARN"
#     echo "✅ Attached EBS CSI policy to role: $ROLE_NAME"
# done

### 5️⃣ Restart EBS CSI Driver ###
echo "🔹 Restarting EBS CSI Driver..."
kubectl delete pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver

echo "🎉 EBS CSI Driver setup completed successfully!"
