#!/bin/bash

echo "Fetching EC2 instances in region: $REGION..."

# Get instance IDs and IPs
instances=$(aws ec2 describe-instances \
  --region "$REGION" \
  --query "Reservations[].Instances[?State.Name=='running'].{ID:InstanceId,IP:PrivateIpAddress,Name:Tags[?Key=='Name']|[0].Value}" \
  --output text)

if [[ -z "$instances" ]]; then
  echo "⚠️ No running EC2 instances found in $REGION."
  exit 1
fi

# REGION=$(aws configure get region)
# NAMESPACE="monitoring"
# SECRET_NAME="additional-scrape-configs"
# SCRAPE_FILE="prometheus-additional.yaml"

# echo "Do you want to enable EC2 monitoring in the same Grafana dashboards? (yes/no)"
# read -r enable_ec2_monitoring

# if [[ "$enable_ec2_monitoring" != "yes" ]]; then
#   echo "❌ Skipping EC2 monitoring setup."
#   exit 0
# fi

# echo "Fetching EC2 instances in region: $REGION..."

# # Get instance IDs and IPs
# instances=$(aws ec2 describe-instances \
#   --region "$REGION" \
#   --query "Reservations[].Instances[?State.Name=='running'].{ID:InstanceId,IP:PrivateIpAddress,Name:Tags[?Key=='Name']|[0].Value}" \
#   --output text)

# if [[ -z "$instances" ]]; then
#   echo "⚠️ No running EC2 instances found in $REGION."
#   exit 1
# fi

# # Let user pick EC2s to monitor
# echo "Select EC2 instances to monitor (space-separated numbers):"
# i=1
# declare -A ip_map
# while read -r id ip name; do
#   echo "$i) $name ($id) - $ip"
#   ip_map[$i]=$ip
#   ((i++))
# done <<< "$instances"

# read -r selected

# # Build target IP list
# targets=()
# for idx in $selected; do
#   targets+=("${ip_map[$idx]}")
# done

# if [[ ${#targets[@]} -eq 0 ]]; then
#   echo "❌ No EC2 instances selected. Aborting."
#   exit 1
# fi

# # Generate Prometheus scrape config
# echo "Generating Prometheus scrape config for selected EC2s..."

# {
#   echo "- job_name: 'ec2-node-exporter'"
#   echo "  static_configs:"
#   echo "    - targets: ["
#   for ip in "${targets[@]}"; do
#     echo "        \"$ip:9100\","
#   done
#   echo "      ]"
# } > $SCRAPE_FILE

# # Create or update the secret in Kubernetes
# echo "Creating/updating Prometheus additional scrape config in Kubernetes..."

# kubectl delete secret "$SECRET_NAME" -n "$NAMESPACE" --ignore-not-found
# kubectl create secret generic "$SECRET_NAME" \
#   --from-file=prometheus-additional.yaml="$SCRAPE_FILE" \
#   -n "$NAMESPACE"

# echo "✅ Secret '$SECRET_NAME' created in namespace '$NAMESPACE'."

# # Optionally: install node exporter on selected EC2s
# echo "Do you want to install node_exporter on the selected EC2 instances now? (yes/no)"
# read -r install_exporter

# if [[ "$install_exporter" == "yes" ]]; then
#   echo "Please enter the username for SSH (e.g., ubuntu, ec2-user):"
#   read -r ssh_user

#   echo "Please enter the path to your private key (e.g., ~/.ssh/key.pem):"
#   read -r ssh_key

#   for ip in "${targets[@]}"; do
#     echo "Installing node_exporter on $ip..."
#     ssh -o StrictHostKeyChecking=no -i "$ssh_key" "$ssh_user@$ip" <<'EOF'
#       curl -LO https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
#       tar xvf node_exporter-1.7.0.linux-amd64.tar.gz
#       sudo mv node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/
#       sudo useradd -rs /bin/false node_exporter
#       cat <<SERVICE | sudo tee /etc/systemd/system/node_exporter.service
# [Unit]
# Description=Node Exporter
# After=network.target

# [Service]
# User=node_exporter
# ExecStart=/usr/local/bin/node_exporter

# [Install]
# WantedBy=default.target
# SERVICE
#       sudo systemctl daemon-reexec
#       sudo systemctl daemon-reload
#       sudo systemctl enable node_exporter
#       sudo systemctl start node_exporter
# EOF
#     echo "✅ node_exporter setup complete on $ip."
#   done
# else
#   echo "⚠️ Skipped node_exporter installation. Please ensure it is running on EC2s."
# fi
