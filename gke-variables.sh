# variables.sh
PROJECT_ID="rock-star-450114-d3"

NAMESPACE="monitoring"

CLUSTER_NAME="gke-demo1"
LABEL_KEY="type"
LABEL_VALUE="monitoring"
REGION="us-east1-b"

PROMETHEUS_VERSION="68.3.0"
LOKI_VERSION="0.80.0"
PROMTAIL_VERSION="6.16.6"

# *************************************************************

# Choose a node placement strategy:
# 1. Node Selector
# 2. Node Affinity
# 3. Taints and Tolerations
# 4. No Node Placement
# Enter your choice (1/2/3/4) in NODE_STRATEGY
NODE_STRATEGY="1"

# if 1. Node Selector
NODE_SELECTOR_KEY="type"
NODE_SELECTOR_VALUE="monitoring"

# if 2. Node Affinity
NODE_AFFINITY_KEY=""
NODE_AFFINITY_VALUE=""

# if 3. Taints and Tolerations
TAINT_KEY=""
TAINT_EFFECT="NoSchedule"
TAINT_VALUE=""
NODE_AFFINITY_KEY_TT=""
NODE_AFFINITY_VALUE_TT=""

# if 4. No Node Placement

# *************************************************************

# Choose a storage option for Grafana:
# 1. Static EBS Volume
# 2. Dynamic EBS Volume
# 3. No Storage Required
# Enter your choice (1/2/3) in STORAGE_CHOICE
STORAGE_CHOICE="2"

# if 1. Static EBS Volume  
# **Please ensure that the volume is created in the same AWS region as the node labeled for monitoring. **
PV_NAME_ST=""
PVC_NAME_ST=""
PV_ID_ST=""

# if 2. Dynamic EBS Volume
PVC_NAME_DY="grafana-pvc"
PV_SIZE_DY="10"

# if 3. No Storage Required

# *************************************************************

# Choose a storage option for Prometheus:
# 1. Static EBS Volume
# 2. Dynamic EBS Volume
# 3. No Storage Required
# Enter your choice (1/2/3): in PROMETHEUS_STORAGE_CHOICE
PROMETHEUS_STORAGE_CHOICE="2"

# if 1. Static EBS Volume  
# **Please ensure that the volume is created in the same AWS region as the node labeled for monitoring. **
PR_PV_NAME_ST=""
PR_PVC_NAME_ST=""
PR_PV_ID_ST=""

# if 2. Dynamic EBS Volume
PR_PV_SIZE_DY="10"
PR_PVC_NAME_DY="prometheus-pvc"

# if 3. GCS Bucket Storage
BUCKET_NAME=""

# if 4. No Storage Required

# *************************************************************