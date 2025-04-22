#!/bin/bash

set -e  # Exit on error

clear

source ./gke-variables.sh

PROMETHEUS_CHART="prometheus-community/kube-prometheus-stack"
LOKI_CHART="grafana/loki-distributed"
PROMTAIL_CHART="grafana/promtail"

NODE_PLACEMENT_CONFIG=""
LOKI_NODE_PLACEMENT_CONFIG=""
STORAGE_CLASS=""
PROMETHEUS_STORAGE_CLASS=""

GRAFANA_SERVICE="prometheus-stack-grafana"
PROMETHEUS_SERVICE="prometheus-stack-kube-prom-prometheus"

configure_GKE_auth (){
  # Set your project ID
  gcloud config set project $PROJECT_ID

  # Get cluster credentials (replace with your cluster name and zone/region)
  gcloud container clusters get-credentials $CLUSTER_NAME --zone $REGION --project $PROJECT_ID

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

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

install_unzip() {
    if ! command_exists unzip; then
        echo "Installing unzip..."
        sudo apt update && sudo apt install -y unzip
    else
        echo "Unzip is already installed."
    fi
}

install_jq() {
    if ! command_exists jq; then
        echo "Installing jq..."
        sudo apt update && sudo apt install -y jq
    else
        echo "jq is already installed."
    fi
}

install_gcloud() {
    if ! command_exists gcloud; then
        echo "Installing Google Cloud SDK..."
        sudo apt update && sudo apt install -y curl apt-transport-https ca-certificates gnupg
        
        # Add Google Cloud SDK repository
        curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
        echo "deb http://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
        
        sudo apt update && sudo apt install -y google-cloud-sdk google-cloud-sdk-gke-gcloud-auth-plugin google-cloud-sdk-storage
    else
        echo "Google Cloud SDK is already installed."
    fi
}

install_kubectl() {
    if ! command_exists kubectl; then
        echo "Installing kubectl..."

        # Ensure the Google Cloud SDK repository is added
        sudo apt update && sudo apt install -y curl apt-transport-https ca-certificates gnupg

        curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
        echo "deb http://packages.cloud.google.com/apt cloud-sdk main" | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list

        sudo apt update && sudo apt install -y google-cloud-sdk

        # Install the GKE authentication plugin
        sudo apt install -y google-cloud-sdk-gke-gcloud-auth-plugin

        # ✅ Install kubectl directly via apt
        sudo apt install -y kubectl
    else
        echo "✅ kubectl is already installed."
    fi
}

install_helm() {
    if ! command_exists helm; then
        echo "Installing Helm..."
        curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    else
        echo "Helm is already installed."
    fi
}

install_dependencies () {
    echo "Checking and installing required dependencies..."
    install_unzip
    install_jq
    install_gcloud
    install_kubectl
    install_helm

    # Verify installations
    echo "Installed versions:"
    gcloud version || echo "gcloud not found"
    kubectl version --client --output=yaml || echo "kubectl not found"
    helm version || echo "Helm not found"

    echo "✅ All required tools are installed!"
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

storageclass (){
  kubectl apply -n $NAMESPACE -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gke-storage-class
provisioner: pd.csi.storage.gke.io
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
parameters:
  type: pd-ssd         # Options: pd-standard, pd-balanced, pd-ssd
  replication-type: none  # none for single-zone, regional-pd for multi-zone
EOF
}

create_service_account (){

  PROJECT_ID_EXISTS=$(gcloud config get-value project 2>/dev/null)

  if [[ -z "$PROJECT_ID_EXISTS" ]]; then
    echo "❌ ERROR: PROJECT_ID is not set."
    gcloud config set project $PROJECT_ID
  fi

  SERVICE_ACCOUNT_NAME="thanos-sa"
  SERVICE_ACCOUNT_DESCRIPTION="GCP Service Account for Prometheus Storage in Bucket"
  SERVICE_ACCOUNT_DISPLAY_NAME="My Service Account"
  KEY_OUTPUT_FILE="thanos-service-account-key.json"

  # Check if the service account already exists
  EXISTING_SA=$(gcloud iam service-accounts list --format="value(email)" --filter="email:$SERVICE_ACCOUNT_NAME@$PROJECT_ID.iam.gserviceaccount.com")

  if [[ -z "$EXISTING_SA" ]]; then
    echo "🚀 Service account '$SERVICE_ACCOUNT_NAME' does not exist. Creating it now..."
    
    gcloud iam service-accounts create "$SERVICE_ACCOUNT_NAME" \
        --description="$SERVICE_ACCOUNT_DESCRIPTION" \
        --display-name="$SERVICE_ACCOUNT_DISPLAY_NAME" \
        --project="$PROJECT_ID"
  else
    echo "✅ Service account '$SERVICE_ACCOUNT_NAME' already exists. Checking roles..."
    
    for ROLE in "roles/storage.objectCreator" "roles/storage.objectViewer"; do
      ROLE_BOUND=$(gcloud projects get-iam-policy "$PROJECT_ID" --flatten="bindings[].members" --format="value(bindings.role)" --filter="bindings.members:serviceAccount:$SERVICE_ACCOUNT_NAME@$PROJECT_ID.iam.gserviceaccount.com" | grep "$ROLE" || true)
      
      if [[ -z "$ROLE_BOUND" ]]; then
        echo "🔗 Role $ROLE is missing. Attaching it now..."
        gcloud projects add-iam-policy-binding "$PROJECT_ID" \
            --member="serviceAccount:$SERVICE_ACCOUNT_NAME@$PROJECT_ID.iam.gserviceaccount.com" \
            --role="$ROLE"
      else
        echo "✅ Role $ROLE is already assigned."
      fi
    done
  fi

  # Check if the key file already exists
  if [[ ! -f "$KEY_OUTPUT_FILE" ]]; then
    echo "🔑 Generating a new key for the service account..."
    gcloud iam service-accounts keys create $KEY_OUTPUT_FILE \
        --iam-account="$SERVICE_ACCOUNT_NAME@$PROJECT_ID.iam.gserviceaccount.com" \
        --project=$PROJECT_ID
  else
    echo "🔑 Key file '$KEY_OUTPUT_FILE' already exists. Skipping key generation."
  fi

  kubectl apply -n $NAMESPACE -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: thanos-sa
  namespace: monitoring
  annotations:
    iam.gke.io/gcp-service-account: $SERVICE_ACCOUNT_NAME@$PROJECT_ID.iam.gserviceaccount.com
EOF

  echo "✅ Service account '$SERVICE_ACCOUNT_NAME' created successfully!"
  echo "🔑 Key saved as '$KEY_OUTPUT_FILE'"
}

configure_GCS_bucket_storage (){
  create_service_account
  # Convert JSON key file to an inline YAML-friendly format
  ESCAPED_JSON=$(jq -c . < $KEY_OUTPUT_FILE)
  CONFIG_FILE="thanos.yaml"

  if [ -f "$CONFIG_FILE" ]; then
      echo "File $CONFIG_FILE found. Deleting..."
      rm "$CONFIG_FILE"
      echo "File deleted."
  else
      echo "File $CONFIG_FILE does not exist."
  fi
  # Create the updated YAML content
  cat <<EOF > $CONFIG_FILE
type: GCS
config:
  bucket: "$BUCKET_NAME"
  service_account: |-
    $ESCAPED_JSON
EOF

  echo "✅ Updated $CONFIG_FILE with the service account key."

  kubectl create secret generic thanos --from-file=thanos.yaml=$CONFIG_FILE --namespace $NAMESPACE

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
          - --objstore.config-file=/etc/thanos/$CONFIG_FILE
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

  PROMETHEUS_STORAGE_CLASS=$(cat <<EOF
prometheus:
  prometheusSpec:
    retention: 24h 
    retentionSize: 10GB 
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: standard
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi 

    thanos:
      enable: true
      objectStorageConfig:
        existingSecret:
          name: thanos
          key: $CONFIG_FILE
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
}

configure_prometheus_storage() {
  case $PROMETHEUS_STORAGE_CHOICE in
    1)
      PR_PV_SIZE_ST=$(gcloud compute disks describe "$PR_PV_ID_ST" \
        --project="$PROJECT_ID" \
        --zone="$REGION" \
        --format="value(sizeGb)")
      kubectl apply -n $NAMESPACE -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${PR_PV_NAME_ST}  
  labels:
    type: prometheus-storage
spec:
  capacity:
    storage: ${PR_PV_SIZE_ST}Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: gke-storage-class
  gcePersistentDisk:
    pdName: ${PR_PV_ID_ST}
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
          storageClassName: gke-storage-class
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: ${PR_PV_SIZE_ST}Gi
          selector:
            matchLabels:
              type: prometheus-storage
EOF
)  # Ensure the HEREDOC closes correctly

      # Node Selector Handling
      if [ "$NODE_PLACEMENT" = "NodeSelector" ]; then
        PROMETHEUS_STORAGE_CLASS+=$(cat <<EOF

    nodeSelector:
      $NODE_SELECTOR_KEY: $NODE_SELECTOR_VALUE
EOF
)
      fi

      # Node Affinity Handling
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
      fi  # Make sure the 'fi' closes correctly

      # Taints and Tolerations Handling
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
      fi  # Closing condition for `TaintsAndTolerations`
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
          storageClassName: gke-storage-class
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: ${PR_PV_SIZE_DY}Gi
EOF
      )  # Ensure EOF is correctly placed

      # Node Selector Handling
      if [ "$NODE_PLACEMENT" = "NodeSelector" ]; then
        PROMETHEUS_STORAGE_CLASS+=$(cat <<EOF

    nodeSelector:
      $NODE_SELECTOR_KEY: $NODE_SELECTOR_VALUE
EOF
)
      fi

      # Node Affinity Handling
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

      # Taints and Tolerations Handling
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
      configure_GCS_bucket_storage
      ;;
    4)
      echo "No Storage Required"
      ;;
    *)
      echo "Invalid storage choice"
      exit 1
      ;;
  esac
}

configure_grafana_storage (){
  case $STORAGE_CHOICE in
    1)
    PV_SIZE_ST=$(gcloud compute disks describe "$PV_ID_ST" \
        --project="$PROJECT_ID" \
        --zone="$REGION" \
        --format="value(sizeGb)")
    kubectl apply -n $NAMESPACE -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${PV_NAME_ST}  
  labels:
    type: prometheus-storage
spec:
  capacity:
    storage: ${PV_SIZE_ST}Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: gke-storage-class
  gcePersistentDisk:
    pdName: ${PV_ID_ST}
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
  resources:
    requests:
      storage: ${PV_SIZE_ST}Gi
  storageClassName: gke-storage-class
  volumeName: $PV_NAME_ST
EOF

  STORAGE_CLASS=$(cat <<EOF
grafana:
  persistence:
    enabled: true
    type: pvc
    accessModes:
      - ReadWriteOnce
    size: ${PV_SIZE_ST}Gi
    storageClassName: gke-storage-class
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
              - key: "$NODE_AFFINITY_KEY"
                operator: "In"
                values:
                  - "$NODE_AFFINITY_VALUE"
EOF
)
    fi

    if [ "$NODE_PLACEMENT" = "TaintsAndTolerations" ]; then
        STORAGE_CLASS+=$(cat <<EOF

  tolerations:
    - key: "$TAINT_KEY"
      operator: "Equal"
      value: "$TAINT_VALUE"
      effect: "$TAINT_EFFECT"
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: "$NODE_AFFINITY_KEY_TT"
                operator: "In"
                values:
                  - "$NODE_AFFINITY_VALUE_TT"
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
  resources:
    requests:
      storage: ${PV_SIZE_DY}Gi
  storageClassName: gke-storage-class
EOF

  STORAGE_CLASS=$(cat <<EOF
grafana:
  persistence:
    enabled: true
    type: pvc
    accessModes:
      - ReadWriteOnce
    size: ${PV_SIZE_DY}Gi
    storageClassName: gke-storage-class
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
              - key: "$NODE_AFFINITY_KEY"
                operator: "In"
                values:
                  - "$NODE_AFFINITY_VALUE"
EOF
)
    fi

    if [ "$NODE_PLACEMENT" = "TaintsAndTolerations" ]; then
        STORAGE_CLASS+=$(cat <<EOF

  tolerations:
    - key: "$TAINT_KEY"
      operator: "Equal"
      value: "$TAINT_VALUE"
      effect: "$TAINT_EFFECT"
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: "$NODE_AFFINITY_KEY_TT"
                operator: "In"
                values:
                  - "$NODE_AFFINITY_VALUE_TT"
EOF
)
    fi
    ;;

    3)
      echo "No Storage Required"
    ;;
    *)
      echo "Invalid storage choice"
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

main () {
  configure_GKE_auth
  install_dependencies
  create_namespace
  check_and_add_helm_repo
  configure_node_placement
  storageclass
  configure_grafana_storage
  configure_prometheus_storage
  deploy_prometheus
  patch_service
  echo "** Script Completed **"
}

main