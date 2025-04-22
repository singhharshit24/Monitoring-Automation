#!/bin/bash
# This script checks whether all prerequisites are installed.

echo "Checking prerequisites..."

# Check for python3
if! command -v python3 &> /dev/null; then
    echo "python3 is not installed. Please install python3."
    exit 1
fi

# Check for pip3
if! command -v pip3 &> /dev/null; then
    echo "pip3 is not installed. Please install pip3."
    exit 1
fi

# Check for required Python packages
missing_packages=()
for package in flask boto3 flask_cors; do
    python3 -c "import $package" 2>/dev/null
    if [ $? -ne 0 ]; then
        missing_packages+=($package)
    fi
done

if [ ${#missing_packages[@]} -ne 0 ]; then
    echo "The following Python packages are missing: ${missing_packages[@]}"
    exit 1
fi

# Check for Terraform
if! command -v terraform &> /dev/null; then
    echo "Terraform is not installed. Please install Terraform."
    exit 1
fi

# Check for AWS CLI
if! command -v aws &> /dev/null; then
    echo "AWS CLI is not installed. Please install AWS CLI."
    exit 1
fi

# Check for Nginx
if! command -v nginx &> /dev/null; then
    echo "Nginx is not installed. Please install Nginx."
    exit 1
fi

# Check for CloudWatch agent
if! command -v /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl &> /dev/null; then
    echo "CloudWatch agent is not installed. Please install the CloudWatch agent."
    exit 1
fi

echo "All prerequisites are met."