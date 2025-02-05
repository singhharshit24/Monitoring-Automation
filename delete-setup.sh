#!/bin/bash

set -e  # Exit on error

RELEASES=("prometheus-stack" "loki" "promtail")
NAMESPACE="monitoring"

for RELEASE in "${RELEASES[@]}"; do
  echo "Checking if Helm release $RELEASE exists in namespace $NAMESPACE..."

  # Check if the release exists
  if helm list -n $NAMESPACE | grep -q "^$RELEASE"; then
    echo "Release $RELEASE found. Uninstalling..."
    helm uninstall $RELEASE -n $NAMESPACE

    if [ $? -eq 0 ]; then
      echo "Release $RELEASE uninstalled successfully."
    else
      echo "Failed to uninstall $RELEASE." >&2
      exit 1
    fi
  else
    echo "Release $RELEASE not found in namespace $NAMESPACE. Skipping..."
  fi
done

# Function to delete PVs
delete_pvs() {
  echo "Checking for PersistentVolumes (PVs)..."
  PV_LIST=$(kubectl get pv --no-headers | awk '/monitoring/ {print $1}')
  
  if [ -n "$PV_LIST" ]; then
    echo "Found the following PVs:"
    echo "$PV_LIST"
    echo "Deleting PVs..."
    for pv in $PV_LIST; do
      kubectl delete pv "$pv"
      echo "Deleted PV: $pv"
    done
  else
    echo "No PVs found in the $NAMESPACE namespace."
  fi
}

# Function to delete PVCs
delete_pvcs() {
  echo "Checking for PersistentVolumeClaims (PVCs)..."
  PVC_LIST=$(kubectl get pvc -n "$NAMESPACE" --no-headers | awk '{print $1}')
  
  if [ -n "$PVC_LIST" ]; then
    echo "Found the following PVCs:"
    echo "$PVC_LIST"
    echo "Deleting PVCs..."
    for pvc in $PVC_LIST; do
      kubectl delete pvc "$pvc" -n "$NAMESPACE"
      echo "Deleted PVC: $pvc"
    done
  else
    echo "No PVCs found in the $NAMESPACE namespace."
  fi
}

# Main script execution
echo "Starting cleanup in the $NAMESPACE namespace..."

delete_pvcs
delete_pvs

echo "Cleanup completed."

echo "Script completed."
