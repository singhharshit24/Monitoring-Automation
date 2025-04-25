# variables.sh
NAMESPACE=""

CLUSTER_NAME=""
LABEL_KEY=""
LABEL_VALUE=""
REGION=""

PROMETHEUS_VERSION=""
LOKI_VERSION=""
PROMTAIL_VERSION=""

# *************************************************************

# Choose a node placement strategy:
# 1. Node Selector
# 2. Node Affinity
# 3. Taints and Tolerations
# 4. No Node Placement
# Enter your choice (1/2/3/4) in NODE_STRATEGY
NODE_STRATEGY="4"

# if 1. Node Selector
NODE_SELECTOR_KEY=""
NODE_SELECTOR_VALUE=""

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
STORAGE_CHOICE="3"

# if 1. Static EBS Volume  
# **Please ensure that the volume is created in the same AWS region as the node labeled for monitoring. **
PV_NAME_ST=""
PVC_NAME_ST=""
PV_ID_ST=""

# if 2. Dynamic EBS Volume
PVC_NAME_DY=""
PV_SIZE_DY=""

# if 3. No Storage Required

# *************************************************************

# Choose a storage option for Prometheus:
# 1. Static EBS Volume
# 2. Dynamic EBS Volume
# 3. S3 Bucket Storage
# 4. No Storage Required
# Enter your choice (1/2/3): in PROMETHEUS_STORAGE_CHOICE
PROMETHEUS_STORAGE_CHOICE="4"

# if 1. Static EBS Volume  
# **Please ensure that the volume is created in the same AWS region as the node labeled for monitoring. **
PR_PV_NAME_ST=""
PR_PVC_NAME_ST=""
PR_PV_ID_ST=""

# if 2. Dynamic EBS Volume
PR_PVC_NAME_DY=""
PR_PV_SIZE_DY=""

# if 3. S3 Bucket Storage
S3_BUCKET_NAME=""
AWS_ACCESS_KEY=""
AWS_SECRET_KEY=""

# if 4. No Storage Required

# *************************************************************

# Option to enable monitoring for ec2.
# Enter your choice (yes/no)
# EC2 Instances Configuration
EC2_INSTANCES=() # Array to store IP addresses of selected instances
EC2_PEM_FILES=() # Array to store paths to PEM files for each instance
EC2_INSTANCE_IDS=() # Array to store instance IDs
EC2_INSTANCE_NAMES=() # Array to store instance names

# Count of selected instances
EC2_INSTANCE_COUNT=0

# SSH User (typically 'ec2-user' for Amazon Linux or 'ubuntu' for Ubuntu instances)
SSH_USER="ec2-user"

# Node Exporter Configuration for EC2
NODE_EXPORTER_VERSION="1.6.1"  # Version of Node Exporter to install
NODE_EXPORTER_PORT="9100"      # Port for Node Exporter metrics

# EC2 Monitoring Configuration
ENABLE_EC2_MONITORING=""  # Flag to indicate if EC2 monitoring is enabled
EC2_REGION=""

# *********************************