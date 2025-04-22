#!/bin/bash

# Set AWS region
REGION="ap-south-1"

# Set Key Pair Name
KEY_NAME="grafana"

# Set Security Group ID
SECURITY_GROUP_ID="sg-060802877c503164f"

# Set AMI ID
AMI_ID="ami-00bb6a80f01f03502"

# Set Instance Type
INSTANCE_TYPE="t2.micro"

# Set Subnet ID
SUBNET_ID="subnet-04021524a356a7d38"

# Set IAM Instance Profile ARN (Replace with your actual ARN)
IAM_INSTANCE_PROFILE_ARN="arn:aws:iam::198907177730:instance-profile/cloudwatch-manual-role" # Replace with your IAM role ARN

# Ask for instance name
read -p "Enter instance name (or press Enter for default): " INSTANCE_NAME

# Set default instance name if not provided
if [ -z "$INSTANCE_NAME" ]; then
  RANDOM_NUMBER=$((RANDOM % 900 + 100)) # Generate a random 3-digit number
  INSTANCE_NAME="cloudwatch-poc-$RANDOM_NUMBER"
fi

# Create EC2 instance
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SECURITY_GROUP_ID" \
    --subnet-id "$SUBNET_ID" \
    --iam-instance-profile "Arn=$IAM_INSTANCE_PROFILE_ARN" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --query 'Instances[*].InstanceId' \
    --output text)

# Wait for instance to be running
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

# Get public IP address
PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[*].Instances[*].PublicIpAddress' \
    --output text)

# Display instance ID and public IP
echo "Instance ID: $INSTANCE_ID"
echo "Instance Name: $INSTANCE_NAME"
echo "Public IP: $PUBLIC_IP"


# Optional: Add a sleep to ensure the instance is fully initialized before attempting to connect.
# Adjust the sleep time as needed.
# sleep 30  # Wait for 30 seconds (adjust as needed)

# Example: SSH connection command (Uncomment if needed and adjust username)
# ssh -i "$KEY_NAME" ec2-user@"$PUBLIC_IP"  # Replace ec2-user with your instance's usernam