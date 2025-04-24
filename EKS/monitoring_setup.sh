#!/bin/bash

clear

set -e  # Exit on error

# ********************

# Add logging to script
exec 1> >(logger -s -t $(basename $0)) 2>&1

# Log script start
echo "Starting monitoring setup script"
echo "Current user: $(whoami)"
echo "Current directory: $(pwd)"
echo "Environment variables:"
env

# ********************

source ./variables.sh


PROMETHEUS_CHART="prometheus-community/kube-prometheus-stack"
LOKI_CHART="grafana/loki-distributed"
PROMTAIL_CHART="grafana/promtail"

NODE_PLACEMENT_CONFIG=""
LOKI_NODE_PLACEMENT_CONFIG=""
STORAGE_CLASS=""
PROMETHEUS_STORAGE_CLASS=""

GRAFANA_SERVICE="prometheus-stack-grafana"
PROMETHEUS_SERVICE="prometheus-stack-kube-prom-prometheus"

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

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

install_dependencies () {
  echo "Checking and installing required dependencies: kubectl, eksctl, aws-cli, and helm..."

  # Detect OS
  ios_type="$(uname -s | tr '[:upper:]' '[:lower:]')"

  install_unzip

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
}

# Function to check if the cluster exists in the specified region
check_cluster_exists() {
  local region=$1
  local cluster_name=$2

  # Using AWS CLI to describe the EKS cluster
  aws eks --region "$region" describe-cluster --name "$cluster_name" > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo "Cluster '$cluster_name' exists in region '$region'."
    return 0
  else
    echo "Cluster '$cluster_name' does not exist in region '$region'. Please check the cluster name or region."
    return 1
  fi
}

# Function to connect to the EKS cluster
connect_to_eks_cluster() {
  # Fetch the cluster name and region from the variables file
  local cluster_name=$CLUSTER_NAME
  local region=$REGION

  # Check if the cluster exists
  if check_cluster_exists "$region" "$cluster_name"; then
    # Connect to the EKS cluster if it exists
    echo "Connecting to EKS cluster: $cluster_name in region: $region"
    aws eks --region "$region" update-kubeconfig --name "$cluster_name"
    echo "Connected to the cluster '$cluster_name'."
  else
    echo "Failed to connect to the cluster."
  fi
}

ebs_csi_controller_setup () {
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
  INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:eks:cluster-name,Values=$CLUSTER_NAME" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text)

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

  ### 4️⃣ Restart EBS CSI Driver ###
  echo "🔹 Restarting EBS CSI Driver..."
  kubectl delete pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver

  echo "🎉 EBS CSI Driver setup completed successfully!"
}

create_namespace() {
    # Use "default" if NAMESPACE is not set
    NAMESPACE=${NAMESPACE:-default}

    if kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
        echo "Namespace '$NAMESPACE' already exists or is default."
    else
        kubectl create namespace "$NAMESPACE"
        echo "Namespace '$NAMESPACE' created."
    fi

    kubectl config set-context --current --namespace="$NAMESPACE"
}

node_affinity() {

  NODE_PLACEMENT_CONFIG=$(cat <<EOF
alertmanager:
  alertmanagerSpec:
    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: $NODE_AFFINITY_KEY
              operator: In
              values:
              - $NODE_AFFINITY_VALUE
grafana:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: $NODE_AFFINITY_KEY
              operator: In
              values:
              - $NODE_AFFINITY_VALUE
kube-state-metrics:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: $NODE_AFFINITY_KEY
              operator: In
              values:
              - $NODE_AFFINITY_VALUE
prometheusOperator:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: $NODE_AFFINITY_KEY
              operator: In
              values:
              - $NODE_AFFINITY_VALUE
prometheus:
  prometheusSpec:
    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: $NODE_AFFINITY_KEY
              operator: In
              values:
              - $NODE_AFFINITY_VALUE
thanosRuler:
  thanosRulerSpec:
    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: $NODE_AFFINITY_KEY
              operator: In
              values:
              - $NODE_AFFINITY_VALUE
EOF
)
}

node_selector() {

  NODE_PLACEMENT_CONFIG=$(cat <<EOF
alertmanager:
  alertmanagerSpec:
    nodeSelector:
      $NODE_SELECTOR_KEY: $NODE_SELECTOR_VALUE
grafana:
  nodeSelector:
    $NODE_SELECTOR_KEY: $NODE_SELECTOR_VALUE
kube-state-metrics:
  nodeSelector:
    $NODE_SELECTOR_KEY: $NODE_SELECTOR_VALUE
prometheusOperator:
  admissionWebhooks:
    deployment:
      nodeSelector:
        $NODE_SELECTOR_KEY: $NODE_SELECTOR_VALUE
prometheusOperator:
  admissionWebhooks:
    patch:
      nodeSelector:
        $NODE_SELECTOR_KEY: $NODE_SELECTOR_VALUE
prometheusOperator:
  nodeSelector:
    $NODE_SELECTOR_KEY: $NODE_SELECTOR_VALUE
prometheus:
  prometheusSpec:
    nodeSelector:
      $NODE_SELECTOR_KEY: $NODE_SELECTOR_VALUE
thanosRuler:
  thanosRulerSpec:
    nodeSelector:
      $NODE_SELECTOR_KEY: $NODE_SELECTOR_VALUE
EOF
)
}

toleration() {

  NODE_PLACEMENT_CONFIG=$(cat <<EOF
alertmanager:
  alertmanagerSpec:
    tolerations:
      - key: $TAINT_KEY
        operator: "Equal"
        value: $TAINT_VALUE
        effect: $TAINT_EFFECT
    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: $NODE_AFFINITY_KEY_TT
              operator: In
              values:
              - $NODE_AFFINITY_VALUE_TT
grafana:
  tolerations:
    - key: $TAINT_KEY
      operator: "Equal"
      value: $TAINT_VALUE
      effect: $TAINT_EFFECT
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: $NODE_AFFINITY_KEY_TT
                operator: "In"
                values:
                  - $NODE_AFFINITY_VALUE_TT

kube-state-metrics:
  tolerations:
    - key: $TAINT_KEY
      operator: "Equal"
      value: $TAINT_VALUE
      effect: $TAINT_EFFECT
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: $NODE_AFFINITY_KEY_TT
            operator: In
            values:
            - $NODE_AFFINITY_VALUE_TT
prometheusOperator:
  admissionWebhooks:
    deployment:
      tolerations:
        - key: $TAINT_KEY
          operator: "Equal"
          value: $TAINT_VALUE
          effect: $TAINT_EFFECT
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: $NODE_AFFINITY_KEY_TT
                operator: In
                values:
                - $NODE_AFFINITY_VALUE_TT
prometheusOperator:
  admissionWebhooks:
    patch:
      tolerations:
        - key: $TAINT_KEY
          operator: "Equal"
          value: $TAINT_VALUE
          effect: $TAINT_EFFECT
prometheusOperator:
  tolerations:
    - key: $TAINT_KEY
      operator: "Equal"
      value: $TAINT_VALUE
      effect: $TAINT_EFFECT
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: $NODE_AFFINITY_KEY_TT
            operator: In
            values:
            - $NODE_AFFINITY_VALUE_TT
prometheus:
  prometheusSpec:
    tolerations:
      - key: $TAINT_KEY
        operator: "Equal"
        value: $TAINT_VALUE
        effect: $TAINT_EFFECT
    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: $NODE_AFFINITY_KEY_TT
              operator: In
              values:
              - $NODE_AFFINITY_VALUE_TT
thanosRuler:
  thanosRulerSpec:
    tolerations:
      - key: $TAINT_KEY
        operator: "Equal"
        value: $TAINT_VALUE
        effect: $TAINT_EFFECT
    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: $NODE_AFFINITY_KEY_TT
              operator: In
              values:
              - $NODE_AFFINITY_VALUE_TT
EOF
)
}

configure_node_placement() {

  case $NODE_STRATEGY in
    1)
      NODE_PLACEMENT="NodeSelector"
      node_selector
      ;;
    2)
      NODE_PLACEMENT="NodeAffinity"
      node_affinity
      ;;
    3)
      NODE_PLACEMENT="TaintsAndTolerations"
      toleration
      ;;
    4)
      echo "No Node Placement"
      ;;
    *)
      echo "Invalid choice. Exiting."
      exit 1
      ;;
  esac
}

get_AZ_node() {
  # CLUSTER_NAME="eks-demo1"  # EKS cluster name
  # LABEL_KEY="type"                  # Label key to filter nodes
  # LABEL_VALUE="monitoring"          # Label value to filter nodes
  # REGION="ap-south-1"               # AWS region

  # Get nodes with the specified label
  NODES=$(kubectl get nodes \
    -l "${LABEL_KEY}=${LABEL_VALUE}" \
    --no-headers \
    -o custom-columns=":metadata.name")

  if [ -z "$NODES" ]; then
      echo "No nodes found with label ${LABEL_KEY}=${LABEL_VALUE}"
      exit 1
  fi

  # Loop through each node and get its AZ
  for NODE in $NODES; do
      echo "Getting availability zone for node: $NODE"
      
      # Get instance ID from the node name
      INSTANCE_ID=$(aws ec2 describe-instances \
          --filters "Name=private-dns-name,Values=${NODE}" \
          --region "${REGION}" \
          --query 'Reservations[].Instances[].InstanceId' \
          --output text)
      
      if [ -z "$INSTANCE_ID" ]; then
          echo "Could not find EC2 instance for node ${NODE}"
          continue
      fi
      
      # Get the AZ using the instance ID
      AZ=$(aws ec2 describe-instances \
          --instance-ids "${INSTANCE_ID}" \
          --region "${REGION}" \
          --query 'Reservations[].Instances[].Placement.AvailabilityZone' \
          --output text)
      
      echo "Node: ${NODE}"
      echo "Instance ID: ${INSTANCE_ID}"
      echo "Availability Zone: ${AZ}"
      echo "------------------------"
  done
}

storageclass() {
  # get_AZ_node
  kubectl apply -n $NAMESPACE -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3-sc
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  fsType: ext4
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
# allowedTopologies:
#   - matchLabelExpressions:
#       - key: topology.ebs.csi.aws.com/zone
#         values:
#           - $AZ
EOF
}

configure_s3_storage() {
  SERVICE_ACCOUNT_NAME="prometheus-thanos-sa"
  IAM_POLICY_NAME="PrometheusS3AccessPolicy"
  IAM_ROLE_NAME="PrometheusS3AccessRole"

  # Get AWS account ID dynamically
  AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

  # 1. Create IAM Policy if not exists
  if ! aws iam get-policy --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/$IAM_POLICY_NAME &>/dev/null; then
    echo "Creating IAM policy: $IAM_POLICY_NAME"
    aws iam create-policy --policy-name "$IAM_POLICY_NAME" --policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "s3:ListBucket"
                ],
                "Resource": [
                    "arn:aws:s3:::'"$S3_BUCKET_NAME"'",
                    "arn:aws:s3:::'"$S3_BUCKET_NAME"'/*"
                ]
            }
        ]
    }'
  else
    echo "IAM policy $IAM_POLICY_NAME already exists."
  fi

  eksctl create iamserviceaccount \
        --name "$SERVICE_ACCOUNT_NAME" \
        --namespace $NAMESPACE \
        --cluster "$CLUSTER_NAME" \
        --attach-policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/$IAM_POLICY_NAME \
        --approve \
        --region "$REGION" \
        --override-existing-serviceaccounts

  OIDC_PROVIDER=$(aws eks describe-cluster --name new-cluster --query "cluster.identity.oidc.issuer" --output text | awk -F'/' '{print $NF}')

  # Create Role
  if aws iam get-role --role-name "$IAM_ROLE_NAME" >/dev/null 2>&1; then
      echo "Role $IAM_ROLE_NAME already exists."
  else
      aws iam create-role --role-name $IAM_ROLE_NAME --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [
          {
            "Effect": "Allow",
            "Principal": {
              "Federated": "arn:aws:iam::'$AWS_ACCOUNT_ID':oidc-provider/oidc.eks.'$REGION'.amazonaws.com/id/'$OIDC_PROVIDER'"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
              "StringEquals": {
                "oidc.eks.$REGION.amazonaws.com/id/'$OIDC_PROVIDER':sub": "system:serviceaccount:'$NAMESPACE':'$SERVICE_ACCOUNT_NAME'"
              }
            }
          }
        ]
      }'

      echo "Role $IAM_ROLE_NAME created successfully."
  fi

  # 2. Delete & Recreate IAM Service Account to ensure correct policy attachment
  # eksctl delete iamserviceaccount \
  #       --name "$SERVICE_ACCOUNT_NAME" \
  #       --namespace $NAMESPACE \
  #       --cluster "$CLUSTER_NAME" \
  #       --region "$REGION" \
  #       --wait || echo "No existing service account to delete"

  # 3. Create Thanos storage configuration
  FILE="object-store.yaml"

  if [ -f "$FILE" ]; then
      echo "File $FILE found. Deleting..."
      rm "$FILE"
      echo "File deleted."
  else
      echo "File $FILE does not exist."
  fi

  cat <<EOF >> object-store.yaml
type: S3
config:
  endpoint: "s3.$REGION.amazonaws.com"
  bucket: "$S3_BUCKET_NAME"
  region: "$REGION"
  access_key: "$AWS_ACCESS_KEY"
  secret_key: "$AWS_SECRET_KEY"
EOF

  # 4. Create Kubernetes Secret for Thanos
  kubectl delete secret -n $NAMESPACE thanos --ignore-not-found=true
  kubectl create secret generic thanos --from-file=object-store.yaml=$FILE --namespace $NAMESPACE

  # Deploy Thanos manifest files

  kubectl apply -n $NAMESPACE -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: thanos-query
spec:
  replicas: 1
  selector:
    matchLabels:
      app: thanos-query
  template:
    metadata:
      labels:
        app: thanos-query
    spec:
      serviceAccountName: $SERVICE_ACCOUNT_NAME
      containers:
      - name: thanos-query
        image: quay.io/thanos/thanos:v0.28.1
        args:
          - query
          - --grpc-address=0.0.0.0:10901
          - --http-address=0.0.0.0:10902
          - --store=thanos-store:10901
        ports:
        - containerPort: 10901
          name: grpc
        - containerPort: 10902
          name: http

---
apiVersion: v1
kind: Service
metadata:
  name: thanos-query
spec:
  selector:
    app: thanos-query
  ports:
    - name: grpc
      port: 10901
      targetPort: 10901
    - name: http
      port: 10902
      targetPort: 10902
  type: ClusterIP

EOF

  kubectl apply -n $NAMESPACE -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: thanos-store
spec:
  replicas: 1
  selector:
    matchLabels:
      app: thanos-store
  template:
    metadata:
      labels:
        app: thanos-store
    spec:
      serviceAccountName: $SERVICE_ACCOUNT_NAME
      containers:
      - name: thanos-store
        image: quay.io/thanos/thanos:v0.28.1
        args:
          - store
          - --data-dir=/data
          - --objstore.config-file=/etc/thanos/object-store.yaml
          - --index-cache-size=500MB
          - --chunk-pool-size=2GB
        ports:
        - containerPort: 10901
          name: grpc
        - containerPort: 10902
          name: http
        volumeMounts:
          - name: thanos-config
            mountPath: /etc/thanos
            readOnly: true
      volumes:
        - name: thanos-config
          secret:
            secretName: thanos
---
apiVersion: v1
kind: Service
metadata:
  name: thanos-store
spec:
  selector:
    app: thanos-store
  ports:
    - name: grpc
      port: 10901
      targetPort: 10901
    - name: http
      port: 10902
      targetPort: 10902
  type: ClusterIP
EOF

  # 5. Prepare Helm values for Prometheus with S3 storage
  PROMETHEUS_STORAGE_CLASS=$(cat <<EOF

prometheus:
  prometheusSpec:
    retention: 24h 
    retentionSize: 10GB
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: gp3-sc
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi

    thanos:
      objectStorageConfig:
        existingSecret:
          name: thanos
          key: object-store.yaml
      image: quay.io/thanos/thanos:v0.28.1

EOF
)
  if [ "$NODE_PLACEMENT" = "NodeSelector" ]; then
        PROMETHEUS_STORAGE_CLASS+=$(cat <<EOF

    nodeSelector:
      $NODE_SELECTOR_KEY: $NODE_SELECTOR_VALUE
EOF
)
      fi

      if [ "$NODE_PLACEMENT" = "NodeAffinity" ]; then
        PROMETHEUS_STORAGE_CLASS+=$(cat <<EOF
  
    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
            - matchExpressions:
                - key: $NODE_AFFINITY_KEY
                  operator: "In"
                  values:
                    - $NODE_AFFINITY_VALUE
EOF
)
      fi

      if [ "$NODE_PLACEMENT" = "TaintsAndTolerations" ]; then
        PROMETHEUS_STORAGE_CLASS+=$(cat <<EOF
  
    tolerations:
      - key: $TAINT_KEY
        operator: "Equal"
        value: $TAINT_VALUE
        effect: $TAINT_EFFECT
    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
            - matchExpressions:
                - key: $NODE_AFFINITY_KEY_TT
                  operator: "In"
                  values:
                    - $NODE_AFFINITY_VALUE_TT
EOF
)
      fi

  echo "Prometheus with S3 storage using IRSA has been configured successfully!"
}

configure_prometheus_storage() {

  case $PROMETHEUS_STORAGE_CHOICE in
    1)
      PR_PV_SIZE_ST=$(aws ec2 describe-volumes --volume-ids $PR_PV_ID_ST --query "Volumes[0].Size" --output text)
      echo "The size of volume $PR_PV_ID_ST is ${PR_PV_SIZE_ST}GiB"
      kubectl apply -n $NAMESPACE -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: $PR_PV_NAME_ST
spec:
  capacity:
    storage: ${PR_PV_SIZE_ST}Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: gp3-sc
  csi:
    driver: ebs.csi.aws.com
    volumeHandle: $PR_PV_ID_ST
    fsType: ext4
  claimRef:
    namespace: $NAMESPACE
    name: ${PR_PVC_NAME_ST}-prometheus-prometheus-stack-kube-prom-prometheus-0
EOF

      PROMETHEUS_STORAGE_CLASS=$(cat <<EOF
prometheus:
  prometheusSpec:
    storageSpec:
      volumeClaimTemplate:
        metadata:
          name: $PR_PVC_NAME_ST
        spec:
          storageClassName: gp3-sc
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: ${PR_PV_SIZE_ST}Gi
          volumeName: $PR_PV_NAME_ST
EOF
)
      if [ "$NODE_PLACEMENT" = "NodeSelector" ]; then
        PROMETHEUS_STORAGE_CLASS+=$(cat <<EOF

    nodeSelector:
      $NODE_SELECTOR_KEY: $NODE_SELECTOR_VALUE
EOF
)
      fi

      if [ "$NODE_PLACEMENT" = "NodeAffinity" ]; then
        PROMETHEUS_STORAGE_CLASS+=$(cat <<EOF

    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
            - matchExpressions:
                - key: $NODE_AFFINITY_KEY
                  operator: "In"
                  values:
                    - $NODE_AFFINITY_VALUE
EOF
)
      fi

      if [ "$NODE_PLACEMENT" = "TaintsAndTolerations" ]; then
        PROMETHEUS_STORAGE_CLASS+=$(cat <<EOF

    tolerations:
      - key: $TAINT_KEY
        operator: "Equal"
        value: $TAINT_VALUE
        effect: $TAINT_EFFECT
    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
            - matchExpressions:
                - key: $NODE_AFFINITY_KEY_TT
                  operator: "In"
                  values:
                    - $NODE_AFFINITY_VALUE_TT
EOF
)
      fi
      ;;
    2)

      PROMETHEUS_STORAGE_CLASS=$(cat <<EOF
prometheus:
  prometheusSpec:
    storageSpec:
      volumeClaimTemplate:
        metadata:
          name: $PR_PVC_NAME_DY
        spec:
          storageClassName: gp3-sc
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: ${PR_PV_SIZE_DY}Gi
EOF
      )

      if [ "$NODE_PLACEMENT" = "NodeSelector" ]; then
        PROMETHEUS_STORAGE_CLASS+=$(cat <<EOF

    nodeSelector:
      $NODE_SELECTOR_KEY: $NODE_SELECTOR_VALUE
EOF
)
      fi

      if [ "$NODE_PLACEMENT" = "NodeAffinity" ]; then
        PROMETHEUS_STORAGE_CLASS+=$(cat <<EOF

    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
            - matchExpressions:
                - key: $NODE_AFFINITY_KEY
                  operator: "In"
                  values:
                    - $NODE_AFFINITY_VALUE
EOF
)
      fi

      if [ "$NODE_PLACEMENT" = "TaintsAndTolerations" ]; then
        PROMETHEUS_STORAGE_CLASS+=$(cat <<EOF

    tolerations:
      - key: $TAINT_KEY
        operator: "Equal"
        value: $TAINT_VALUE
        effect: $TAINT_EFFECT
    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
            - matchExpressions:
                - key: $NODE_AFFINITY_KEY_TT
                  operator: "In"
                  values:
                    - $NODE_AFFINITY_VALUE_TT
EOF
)
      fi
      ;;
      3)
        configure_s3_storage
      ;;
      4)
        echo "No Storage Required"
      ;;
    *)
      echo "Invalid choice. Exiting."
      exit 1
      ;;
  esac
}

configure_grafana_storage() {

  case $STORAGE_CHOICE in
    1)
      PV_SIZE_ST=$(aws ec2 describe-volumes --volume-ids $PV_ID_ST --query "Volumes[0].Size" --output text)
      echo "The size of volume $PV_ID_ST is ${PV_SIZE_ST}GiB"
      kubectl apply -n $NAMESPACE -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: $PV_NAME_ST
spec:
  capacity:
    storage: "${PV_SIZE_ST}Gi"
  volumeMode: Filesystem
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain 
  storageClassName: gp3-sc
  awsElasticBlockStore:
    volumeID: $PV_ID_ST
    fsType: ext4
EOF

      kubectl apply -n $NAMESPACE -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $PVC_NAME_ST
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: gp3-sc 
  resources:
    requests:
      storage: ${PV_SIZE_ST}Gi
EOF

      STORAGE_CLASS=$(cat <<EOF
grafana:
  persistence:
    enabled: true
    type: pvc
    accessModes:
      - ReadWriteOnce
    size: ${PV_SIZE_ST}Gi
    storageClassName: gp3-sc
    existingClaim: $PVC_NAME_ST

  extraVolumes:
    - name: grafana-storage
      persistentVolumeClaim:
        claimName: $PVC_NAME_ST

  extraVolumeMounts:
    - name: grafana-storage
      mountPath: /tmp
EOF
)
      if [ "$NODE_PLACEMENT" = "NodeSelector" ]; then
        STORAGE_CLASS+=$(cat <<EOF

  nodeSelector:
    $NODE_SELECTOR_KEY: $NODE_SELECTOR_VALUE
EOF
)
      fi

      if [ "$NODE_PLACEMENT" = "NodeAffinity" ]; then
        STORAGE_CLASS+=$(cat <<EOF

  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: $NODE_AFFINITY_KEY
                operator: "In"
                values:
                  - $NODE_AFFINITY_VALUE
EOF
)
      fi

      if [ "$NODE_PLACEMENT" = "TaintsAndTolerations" ]; then
        STORAGE_CLASS+=$(cat <<EOF

  tolerations:
    - key: $TAINT_KEY
      operator: "Equal"
      value: $TAINT_VALUE
      effect: $TAINT_EFFECT
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: $NODE_AFFINITY_KEY_TT
                operator: "In"
                values:
                  - $NODE_AFFINITY_VALUE_TT
EOF
)
      fi
      ;;
    2)

      kubectl apply -n $NAMESPACE -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $PVC_NAME_DY
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: gp3-sc
  resources:
    requests:
      storage: ${PV_SIZE_DY}Gi
EOF

      STORAGE_CLASS=$(cat <<EOF
grafana:
  persistence:
    enabled: true
    type: pvc
    accessModes:
      - ReadWriteOnce
    size: ${PV_SIZE_DY}Gi
    storageClassName: gp3-sc
    existingClaim: $PVC_NAME_DY

  extraVolumes:
    - name: grafana-storage
      persistentVolumeClaim:
        claimName: $PVC_NAME_DY

  extraVolumeMounts:
    - name: grafana-storage
      mountPath: /tmp
EOF
      )

      if [ "$NODE_PLACEMENT" = "NodeSelector" ]; then
        STORAGE_CLASS+=$(cat <<EOF

  nodeSelector:
    $NODE_SELECTOR_KEY: $NODE_SELECTOR_VALUE
EOF
)
      fi

      if [ "$NODE_PLACEMENT" = "NodeAffinity" ]; then
        STORAGE_CLASS+=$(cat <<EOF

  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: $NODE_AFFINITY_KEY
                operator: "In"
                values:
                  - $NODE_AFFINITY_VALUE
EOF
)
      fi

      if [ "$NODE_PLACEMENT" = "TaintsAndTolerations" ]; then
        STORAGE_CLASS+=$(cat <<EOF

  tolerations:
    - key: $TAINT_KEY
      operator: "Equal"
      value: $TAINT_VALUE
      effect: $TAINT_EFFECT
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: $NODE_AFFINITY_KEY_TT
                operator: "In"
                values:
                  - $NODE_AFFINITY_VALUE_TT
EOF
)
      fi
      ;;
      3)
        echo "No Storage Required"
      ;;
      *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
  esac
}

monitor_ec2() {
  if [[ "$ENABLE_EC2_MONITORING" != "1" ]]; then
        echo "❌ Skipping EC2 monitoring setup."
        return 0
    fi

    SECRET_NAME="additional-scrape-configs"
    SCRAPE_FILE="prometheus-additional.yaml"
    
    echo "Starting EC2 monitoring setup for ${EC2_INSTANCE_COUNT} instances..."

    # Build target IP list for Prometheus scraping
    targets=()
    for ip in "${EC2_INSTANCES[@]}"; do
        if [[ -n "$ip" ]]; then
            targets+=("$ip")
            echo "Added target IP: $ip"
        fi
    done

    if [[ ${#targets[@]} -eq 0 ]]; then
        echo "❌ No EC2 instances selected. Aborting."
        return 1
    fi

    # Generate Prometheus scrape config
    echo "Generating Prometheus scrape config for selected EC2s..."
    {
        echo "- job_name: 'ec2-node-exporter'"
        echo "  static_configs:"
        echo "    - targets: ["
        for ip in "${targets[@]}"; do
            echo "        \"$ip:${NODE_EXPORTER_PORT}\","
        done
        echo "      ]"
    } > "$SCRAPE_FILE"

    # Create or update the secret in Kubernetes
    echo "Creating/updating Prometheus additional scrape config in Kubernetes..."
    kubectl delete secret "$SECRET_NAME" -n "$NAMESPACE" --ignore-not-found
    kubectl create secret generic "$SECRET_NAME" \
        --from-file=prometheus-additional.yaml="$SCRAPE_FILE" \
        -n "$NAMESPACE"

    echo "✅ Secret '$SECRET_NAME' created in namespace '$NAMESPACE'."

    # Install node exporter on selected EC2 instances
    echo "Installing node_exporter on selected EC2 instances..."

    for ((i=0; i<${EC2_INSTANCE_COUNT}; i++)); do
        instance_ip="${EC2_INSTANCES[$i]}"
        
        echo "📦 Installing node_exporter on ($instance_ip)..."
        
        # SSH into instance and install node_exporter
        ssh -o StrictHostKeyChecking=no -i "${EC2_PEM_FILES[$i]}" "${SSH_USER}@${instance_ip}" <<'EOF'
            # Check if node_exporter is already installed
            if systemctl is-active --quiet node_exporter; then
                echo "node_exporter is already running"
                exit 0
            fi

            # Download and install node_exporter
            wget "${NODE_EXPORTER_DOWNLOAD_URL}" -O node_exporter.tar.gz
            tar xvf node_exporter.tar.gz
            sudo mv node_exporter-*/node_exporter /usr/local/bin/
            rm -rf node_exporter*

            # Create node_exporter user
            sudo useradd -rs /bin/false node_exporter || true

            # Create systemd service
            sudo tee /etc/systemd/system/node_exporter.service <<SERVICE
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter --web.listen-address=:${NODE_EXPORTER_PORT}

[Install]
WantedBy=multi-user.target
SERVICE

            # Start and enable the service
            sudo systemctl daemon-reload
            sudo systemctl start node_exporter
            sudo systemctl enable node_exporter

            # Verify the service is running
            sudo systemctl status node_exporter --no-pager
EOF

        if [ $? -eq 0 ]; then
            echo "✅ Successfully installed node_exporter on ($instance_ip)"
        else
            echo "❌ Failed to install node_exporter on ($instance_ip)"
        fi

        # Verify node_exporter is accessible
        timeout 5 curl -s "http://${instance_ip}:${NODE_EXPORTER_PORT}/metrics" >/dev/null
        if [ $? -eq 0 ]; then
            echo "✅ node_exporter metrics endpoint is accessible on $instance_ip:${NODE_EXPORTER_PORT}"
        else
            echo "❌ Cannot access node_exporter metrics endpoint on $instance_ip:${NODE_EXPORTER_PORT}"
            echo "Please check security groups and firewall settings"
        fi

        echo "------------------------"
    done

    echo "🎉 EC2 monitoring setup completed!"
    echo "📊 Prometheus will scrape metrics from these instances: ${targets[*]}"
}

check_and_add_helm_repo() {
  local repos=(
    "prometheus-community|https://prometheus-community.github.io/helm-charts"
    "grafana|https://grafana.github.io/helm-charts"
  )

  for repo in "${repos[@]}"; do
    local repo_name=${repo%%|*}
    local repo_url=${repo##*|}

    echo "Checking if $repo_name repository is present..."

    # Check if the repository exists in the Helm repo list
    if helm repo list | grep -q "$repo_name"; then
      echo "$repo_name repository is already present."
    else
      echo "$repo_name repository is not present. Adding it..."
      helm repo add "$repo_name" "$repo_url"

      if [ $? -eq 0 ]; then
        echo "$repo_name repository added successfully."
      else
        echo "Failed to add $repo_name repository." >&2
        exit 1
      fi
    fi
  done

  # Update the repositories to ensure the latest charts are available
  echo "Updating Helm repositories..."
  helm repo update
}

deploy_prometheus() {
  echo "Deploying prometheus..."
  helm upgrade --install prometheus-stack $PROMETHEUS_CHART -n $NAMESPACE -f values.yaml --version $PROMETHEUS_VERSION --values - <<EOF
$NODE_PLACEMENT_CONFIG
$STORAGE_CLASS
$PROMETHEUS_STORAGE_CLASS
EOF
}

patch_service() {
  echo "Patching the Grafana service to change the type to LoadBalancer..."
  
  # Check if the service exists
  if kubectl get svc "$GRAFANA_SERVICE" -n "$NAMESPACE" > /dev/null 2>&1; then
    kubectl patch svc "$GRAFANA_SERVICE" -n "$NAMESPACE" \
      --type='merge' -p '{"spec":{"type":"LoadBalancer"}}'
    echo "Service patched successfully. The type is now LoadBalancer."
  else
    echo "Error: Service '$GRAFANA_SERVICE' not found in namespace '$NAMESPACE'."
    exit 1
  fi

  echo "Patching the Prometheus service to change the type to LoadBalancer..."
  
  # Check if the service exists
  if kubectl get svc "$PROMETHEUS_SERVICE" -n "$NAMESPACE" > /dev/null 2>&1; then
    kubectl patch svc "$PROMETHEUS_SERVICE" -n "$NAMESPACE" \
      --type='merge' -p '{"spec":{"type":"LoadBalancer"}}'
    echo "Service patched successfully. The type is now LoadBalancer."
  else
    echo "Error: Service '$PROMETHEUS_SERVICE' not found in namespace '$NAMESPACE'."
    exit 1
  fi
}

main (){
  install_dependencies
  connect_to_eks_cluster
  ebs_csi_controller_setup
  create_namespace
  storageclass
  configure_node_placement
  configure_grafana_storage
  configure_prometheus_storage
  check_and_add_helm_repo
  deploy_prometheus
  patch_service
  echo "** Setup completed! **"
}

main