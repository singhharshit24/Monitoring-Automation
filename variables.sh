# variables.sh
NAMESPACE="monitoring"

CLUSTER_NAME="eks-demo1"         # EKS cluster name
LABEL_KEY="type"                  # Label key to filter nodes
LABEL_VALUE="monitoring"          # Label value to filter nodes
REGION="ap-south-1"               # AWS region of the cluster

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
NODE_AFFINITY_KEY="type"
NODE_AFFINITY_VALUE="monitoring"

# if 3. Taints and Tolerations
TAINT_KEY="type"
TAINT_EFFECT="NoSchedule"
TAINT_VALUE="monitoring"
NODE_AFFINITY_KEY_TT="type"
NODE_AFFINITY_VALUE_TT="monitoring"

# if 4. No Node Placement

# *************************************************************

# Choose a storage option for Grafana:
# 1. Static EBS Volume
# 2. Dynamic EBS Volume
# 3. No Storage Required
# Enter your choice (1/2/3) in STORAGE_CHOICE
STORAGE_CHOICE="1"

# if 1. Static EBS Volume  
# **Please ensure that the volume is created in the same AWS region as the node labeled for monitoring. **
PV_NAME_ST="grafana-pv"
PVC_NAME_ST="grafana-pvc"
PV_ID_ST="vol-0d78fe9ec45e89da3"
PV_SIZE_ST="1"                      # as created in the Volumes

# if 2. Dynamic EBS Volume
PVC_NAME_DY="grafana-pvc"
PV_SIZE_DY="2"

# if 3. No Storage Required

# *************************************************************

# Choose a storage option for Prometheus:
# 1. Static EBS Volume
# 2. Dynamic EBS Volume
# 3. No Storage Required
# Enter your choice (1/2/3): in PROMETHEUS_STORAGE_CHOICE
PROMETHEUS_STORAGE_CHOICE="1"

# if 1. Static EBS Volume  
# **Please ensure that the volume is created in the same AWS region as the node labeled for monitoring. **
PR_PV_ID_ST="vol-05d19e03b04fdc584"
PR_PV_SIZE_ST="1"
PR_PV_NAME_ST="prometheus-pv"
PR_PVC_NAME_ST="prometheus-pvc"

# if 2. Dynamic EBS Volume
PR_PV_SIZE_DY="2"
PR_PVC_NAME_DY="prometheus-pvc"

# if 3. No Storage Required

# *************************************************************