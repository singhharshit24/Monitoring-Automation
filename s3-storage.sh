#!/bin/bash

# Variables
SERVICE_ACCOUNT_NAME="prometheus-thanos-sa"
IAM_POLICY_NAME="PrometheusS3AccessPolicy"
IAM_ROLE_NAME="PrometheusS3AccessRole"

# 1. Create an S3 Bucket for Thanos
echo "Creating S3 bucket: $S3_BUCKET_NAME"
aws s3api create-bucket --bucket $S3_BUCKET_NAME --region $REGION --create-bucket-configuration LocationConstraint=$REGION

# 2. Create an IAM Policy for S3 Access
echo "Creating IAM policy: $POLICY_NAME"
cat <<EOF > s3-access-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket",
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject"
            ],
            "Resource": [
                "arn:aws:s3:::$S3_BUCKET_NAME",
                "arn:aws:s3:::$S3_BUCKET_NAME/*"
            ]
        }
    ]
}
EOF
aws iam create-policy --policy-name $POLICY_NAME --policy-document file://s3-access-policy.json

# 3. Create a Kubernetes Namespace for Monitoring
echo "Creating namespace: $NAMESPACE"
kubectl create namespace $NAMESPACE

# 4. Deploy Prometheus using Helm
echo "Deploying Prometheus with Helm"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install $RELEASE_NAME prometheus-community/prometheus --namespace $NAMESPACE

# 5. Create an IAM Role and Service Account for Thanos Sidecar
echo "Creating IAM role and service account for Thanos Sidecar"
eksctl create iamserviceaccount \
  --name $SERVICE_ACCOUNT_NAME \
  --namespace $NAMESPACE \
  --cluster $CLUSTER_NAME \
  --attach-policy-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/$POLICY_NAME \
  --approve

# 6. Deploy Thanos Sidecar with Prometheus
echo "Deploying Thanos Sidecar with Prometheus"
cat <<EOF > thanos-sidecar.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus-server
  namespace: $NAMESPACE
spec:
  template:
    spec:
      serviceAccountName: $SERVICE_ACCOUNT_NAME
      containers:
      - name: prometheus
        # Prometheus container configuration
      - name: thanos-sidecar
        image: quay.io/thanos/thanos:v0.23.1
        args:
        - sidecar
        - --tsdb.path=/data
        - --objstore.config="
            type: S3
            config:
              bucket: \"$S3_BUCKET_NAME\"
              endpoint: \"s3.$REGION.amazonaws.com\"
              region: \"$REGION\"
              access_key: \"\$(AWS_ACCESS_KEY_ID)\"
              secret_key: \"\$(AWS_SECRET_ACCESS_KEY)\"
              insecure: false
          "
        ports:
        - containerPort: 10901
        volumeMounts:
        - name: prometheus-server-db
          mountPath: /data
EOF
kubectl apply -f thanos-sidecar.yaml

echo "Thanos integration with Prometheus and S3 storage has been successfully deployed."
