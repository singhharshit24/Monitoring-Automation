#!/bin/bash

set -e  # Exit on error

NAMESPACE="monitoring"
PROMETHEUS_CHART="prometheus-community/kube-prometheus-stack"
LOKI_CHART="grafana/loki-stack"
GRAFANA_CHART="grafana/grafana"
KUBECOST_CHART="kubecost/cost-analyzer"
HELM_VERSION="latest"
STORAGE_CLASS=""
NODE_PLACEMENT_CONFIG=""

# Helper Function: Create Namespace
create_namespace() {
  kubectl create namespace "$NAMESPACE" || echo "Namespace '$NAMESPACE' already exists."
}

# Helper Function: Prompt User for Node Placement Strategy
configure_node_placement() {
  echo "Choose a node placement strategy:"
  echo "1. Node Selector"
  echo "2. Node Affinity"
  echo "3. Taints and Tolerations"
  read -p "Enter your choice (1/2/3): " NODE_STRATEGY

  case $NODE_STRATEGY in
    1)
      read -p "Enter Node Selector key: " NODE_SELECTOR_KEY
      read -p "Enter Node Selector value: " NODE_SELECTOR_VALUE
      NODE_PLACEMENT_CONFIG="nodeSelector:
        $NODE_SELECTOR_KEY: $NODE_SELECTOR_VALUE"
      ;;
    2)
      read -p "Enter Node Affinity key: " NODE_AFFINITY_KEY
      read -p "Enter Node Affinity value: " NODE_AFFINITY_VALUE
      NODE_PLACEMENT_CONFIG="affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: $NODE_AFFINITY_KEY
                operator: In
                values:
                - $NODE_AFFINITY_VALUE"
      ;;
    3)
      read -p "Enter Taint key: " TAINT_KEY
      read -p "Enter Taint effect (NoSchedule/PreferNoSchedule): " TAINT_EFFECT
      NODE_PLACEMENT_CONFIG="tolerations:
        - key: \"$TAINT_KEY\"
          operator: \"Exists\"
          effect: \"$TAINT_EFFECT\""
      ;;
    *)
      echo "Invalid choice. Exiting."
      exit 1
      ;;
  esac
}

# Helper Function: Prompt User for Storage Type
configure_storage() {
  echo "Choose a storage option:"
  echo "1. Static EBS Volume"
  echo "2. Dynamic EBS Volume (via StorageClass)"
  echo "3. S3 Bucket (for Prometheus)"
  read -p "Enter your choice (1/2/3): " STORAGE_CHOICE

  case $STORAGE_CHOICE in
    1)
      read -p "Enter PersistentVolume name for static EBS: " PV_NAME
      STORAGE_CLASS="existingClaim: $PV_NAME"
      ;;
    2)
      read -p "Enter StorageClass name for dynamic provisioning: " STORAGE_CLASS_NAME
      STORAGE_CLASS="storageClassName: $STORAGE_CLASS_NAME"
      ;;
    3)
      read -p "Enter S3 Bucket name: " S3_BUCKET_NAME
      STORAGE_CLASS="remoteWrite:
        - url: \"https://$S3_BUCKET_NAME.s3.amazonaws.com\"
          sigv4:
            region: \"<your-region>\"
            accessKey: \"<your-access-key>\"
            secretKey: \"<your-secret-key>\""
      ;;
    *)
      echo "Invalid choice. Exiting."
      exit 1
      ;;
  esac
}

# Deploy Prometheus
deploy_prometheus() {
  echo "Deploying Prometheus..."
  helm install prometheus $PROMETHEUS_CHART --namespace $NAMESPACE --values - <<EOF
$NODE_PLACEMENT_CONFIG
persistentVolume:
  $STORAGE_CLASS
EOF
}

# Deploy Loki
deploy_loki() {
  echo "Deploying Loki..."
  helm install loki $LOKI_CHART --namespace $NAMESPACE --values - <<EOF
$NODE_PLACEMENT_CONFIG
persistence:
  $STORAGE_CLASS
EOF
}

# Deploy Grafana
deploy_grafana() {
  echo "Deploying Grafana..."
  helm install grafana $GRAFANA_CHART --namespace $NAMESPACE --values - <<EOF
$NODE_PLACEMENT_CONFIG
persistence:
  $STORAGE_CLASS
EOF
}

# Deploy Kubecost
deploy_kubecost() {
  echo "Deploying Kubecost..."
  helm repo add kubecost https://kubecost.github.io/cost-analyzer/
  helm repo update
  helm install kubecost $KUBECOST_CHART --namespace $NAMESPACE --values - <<EOF
$NODE_PLACEMENT_CONFIG
persistentVolume:
  $STORAGE_CLASS
EOF
}

# Main Script Execution
main() {
  create_namespace
  configure_node_placement
  configure_storage

  deploy_prometheus
  deploy_loki
  deploy_grafana
  deploy_kubecost

  echo "Monitoring setup complete!"
  echo "Prometheus, Loki, Grafana, and Kubecost are now running in the '$NAMESPACE' namespace."
}

# Run the main function
main
