#!/bin/bash

set -e  # Exit on error

clear

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

command_exists_1() {
  command -v "$1" &>/dev/null
}

ebs_csi_setup () {
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
}

create_namespace() {
    if kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
        echo "Namespace '$NAMESPACE' already exists."
    else
        kubectl create namespace "$NAMESPACE"
        echo "Namespace '$NAMESPACE' created."
    fi
    kubectl config set-context --current --namespace=$NAMESPACE
}

loki_node_selector() {
  LOKI_NODE_SELECTOR_KEY="type"
  LOKI_NODE_SELECTOR_VALUE="monitoring"
  LOKI_NODE_PLACEMENT_CONFIG=$(cat <<EOF
ingester:
  nodeSelector:
    $LOKI_NODE_SELECTOR_KEY: $LOKI_NODE_SELECTOR_VALUE
distributor:
  nodeSelector:
    $LOKI_NODE_SELECTOR_KEY: $LOKI_NODE_SELECTOR_VALUE
querier:
  nodeSelector:
    $LOKI_NODE_SELECTOR_KEY: $LOKI_NODE_SELECTOR_VALUE
queryFrontend:
  nodeSelector:
    $LOKI_NODE_SELECTOR_KEY: $LOKI_NODE_SELECTOR_VALUE
queryScheduler:
  nodeSelector:
    $LOKI_NODE_SELECTOR_KEY: $LOKI_NODE_SELECTOR_VALUE
tableManager:
  nodeSelector:
    $LOKI_NODE_SELECTOR_KEY: $LOKI_NODE_SELECTOR_VALUE
gateway:
  nodeSelector:
    $LOKI_NODE_SELECTOR_KEY: $LOKI_NODE_SELECTOR_VALUE
compactor:
  nodeSelector:
    $LOKI_NODE_SELECTOR_KEY: $LOKI_NODE_SELECTOR_VALUE
ruler:
  nodeSelector:
    $LOKI_NODE_SELECTOR_KEY: $LOKI_NODE_SELECTOR_VALUE
indexGateway:
  nodeSelector:
    $LOKI_NODE_SELECTOR_KEY: $LOKI_NODE_SELECTOR_VALUE
memcachedChunks:
  nodeSelector:
    $LOKI_NODE_SELECTOR_KEY: $LOKI_NODE_SELECTOR_VALUE
memcachedFrontend:
  nodeSelector:
    $LOKI_NODE_SELECTOR_KEY: $LOKI_NODE_SELECTOR_VALUE
memcachedIndexQueries:
  nodeSelector:
    $LOKI_NODE_SELECTOR_KEY: $LOKI_NODE_SELECTOR_VALUE
memcachedIndexWrites:
  nodeSelector:
    $LOKI_NODE_SELECTOR_KEY: $LOKI_NODE_SELECTOR_VALUE
EOF
)
}

loki_node_affinity() {
  LOKI_NODE_AFFINITY_KEY="type"
  LOKI_NODE_AFFINITY_VALUE="monitoring"
  LOKI_NODE_PLACEMENT_CONFIG=$(cat <<EOF
ingester:
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchLabels:
              {{- include "loki.ingesterSelectorLabels" . | nindent 10 }}
          topologyKey: kubernetes.io/hostname
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          podAffinityTerm:
            labelSelector:
              matchLabels:
                {{- include "loki.ingesterSelectorLabels" . | nindent 12 }}
            topologyKey: failure-domain.beta.kubernetes.io/zone
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: $LOKI_NODE_AFFINITY_KEY
              operator: In
              values:
              - $LOKI_NODE_AFFINITY_VALUE
distributor:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: $LOKI_NODE_AFFINITY_KEY
              operator: In
              values:
              - $LOKI_NODE_AFFINITY_VALUE
querier:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: $LOKI_NODE_AFFINITY_KEY
              operator: In
              values:
              - $LOKI_NODE_AFFINITY_VALUE
queryFrontend:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: $LOKI_NODE_AFFINITY_KEY
              operator: In
              values:
              - $LOKI_NODE_AFFINITY_VALUE
queryScheduler:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: $LOKI_NODE_AFFINITY_KEY
              operator: In
              values:
              - $LOKI_NODE_AFFINITY_VALUE
tableManager:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: $LOKI_NODE_AFFINITY_KEY
              operator: In
              values:
              - $LOKI_NODE_AFFINITY_VALUE
gateway:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: $LOKI_NODE_AFFINITY_KEY
              operator: In
              values:
              - $LOKI_NODE_AFFINITY_VALUE
compactor:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: $LOKI_NODE_AFFINITY_KEY
              operator: In
              values:
              - $LOKI_NODE_AFFINITY_VALUE
ruler:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: $LOKI_NODE_AFFINITY_KEY
              operator: In
              values:
              - $LOKI_NODE_AFFINITY_VALUE
indexGateway:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: $LOKI_NODE_AFFINITY_KEY
              operator: In
              values:
              - $LOKI_NODE_AFFINITY_VALUE
memcachedChunks:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: $LOKI_NODE_AFFINITY_KEY
              operator: In
              values:
              - $LOKI_NODE_AFFINITY_VALUE
memcachedFrontend:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: $LOKI_NODE_AFFINITY_KEY
              operator: In
              values:
              - $LOKI_NODE_AFFINITY_VALUE
memcachedIndexQueries:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: $LOKI_NODE_AFFINITY_KEY
              operator: In
              values:
              - $LOKI_NODE_AFFINITY_VALUE
memcachedIndexWrites:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: $LOKI_NODE_AFFINITY_KEY
              operator: In
              values:
              - $LOKI_NODE_AFFINITY_VALUE
EOF
)
}

configure_loki_node_placement() {
  echo "Choose a node placement strategy for loki:"
  echo "1. Node Selector"
  echo "2. Node Affinity"
  # echo "3. Taints and Tolerations"
  echo "3. No Node Placement"
  read -p "Enter your choice (1/2/3): " NODE_STRATEGY

  case $NODE_STRATEGY in
    1)
      loki_node_selector
      ;;
    2)
      loki_node_affinity
      ;;
    # 3)
    #   NODE_PLACEMENT="TaintsAndTolerations"
    #   toleration
    #   ;;
    3)
      echo "No Node Placement"
      ;;
    *)
      echo "Invalid choice. Exiting."
      exit 1
      ;;
  esac
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
  get_AZ_node
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
allowedTopologies:
  - matchLabelExpressions:
      - key: topology.ebs.csi.aws.com/zone
        values:
          - $AZ
EOF
}

configure_prometheus_storage() {

  case $PROMETHEUS_STORAGE_CHOICE in
    1)

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
              storage: ${PR_PV_SIZE_DY}
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

deploy_loki() {
  echo "Deploying loki..."
  helm upgrade --install loki $LOKI_CHART -f loki-values.yaml -n $NAMESPACE --values - <<EOF
$LOKI_NODE_PLACEMENT_CONFIG
EOF
  helm upgrade --install promtail $PROMTAIL_CHART -f promtail-values.yaml -n $NAMESPACE
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
  ebs_csi_setup
  create_namespace
  storageclass
  configure_node_placement
  configure_grafana_storage
  configure_prometheus_storage
  # configure_loki_node_placement
  check_and_add_helm_repo
  # deploy_loki
  deploy_prometheus
  patch_service
  echo "** Setup completed! **"
}

main