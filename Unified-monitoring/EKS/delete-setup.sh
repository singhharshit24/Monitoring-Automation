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

# Function to delete Deployments
delete_deployments() {
  echo "Checking for Deployments in $NAMESPACE..."
  DEPLOYMENTS=$(kubectl get deployments -n "$NAMESPACE" --no-headers | awk '{print $1}')
  
  if [ -n "$DEPLOYMENTS" ]; then
    echo "Found Deployments:"
    echo "$DEPLOYMENTS"
    echo "Deleting Deployments..."
    for deploy in $DEPLOYMENTS; do
      kubectl delete deployment "$deploy" -n "$NAMESPACE"
      echo "Deleted Deployment: $deploy"
    done
  else
    echo "No Deployments found in the $NAMESPACE namespace."
  fi
}

# Function to delete StatefulSets
delete_statefulsets() {
  echo "Checking for StatefulSets in $NAMESPACE..."
  STATEFULSETS=$(kubectl get statefulsets -n "$NAMESPACE" --no-headers | awk '{print $1}')
  
  if [ -n "$STATEFULSETS" ]; then
    echo "Found StatefulSets:"
    echo "$STATEFULSETS"
    echo "Deleting StatefulSets..."
    for sts in $STATEFULSETS; do
      kubectl delete statefulset "$sts" -n "$NAMESPACE"
      echo "Deleted StatefulSet: $sts"
    done
  else
    echo "No StatefulSets found in the $NAMESPACE namespace."
  fi
}

# Function to delete PVs
delete_pvs() {
  echo "Checking for PersistentVolumes (PVs)..."
  # Modified awk pattern to match both 'prometheus' and 'monitoring'
  PV_LIST=$(kubectl get pv --no-headers | awk '/prometheus|monitoring/ {print $1}')
  
  if [ -n "$PV_LIST" ]; then
    echo "Found the following PVs:"
    echo "$PV_LIST"
    echo "Deleting PVs..."
    for pv in $PV_LIST; do
      kubectl delete pv "$pv"
      echo "Deleted PV: $pv"
    done
  else
    echo "No Prometheus or monitoring PVs found."
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

# Function to delete Services
delete_services() {
  echo "Checking for Services in $NAMESPACE..."
  # Modified awk to exclude specific services
  SERVICE_LIST=$(kubectl get services -n "$NAMESPACE" --no-headers | \
    awk '$1 != "prometheus-stack-grafana" && $1 != "prometheus-stack-kube-prom-prometheus" {print $1}')

  if [ -n "$SERVICE_LIST" ]; then
    echo "Found the following Services:"
    echo "$SERVICE_LIST"
    echo "Deleting Services..."
    for svc in $SERVICE_LIST; do
      kubectl delete service "$svc" -n "$NAMESPACE"
      echo "Deleted Service: $svc"
    done
  else
    echo "No Services found to delete in $NAMESPACE (excluding prometheus-stack-grafana and prometheus-stack-kube-prom-prometheus)."
  fi
}

# Function to delete ServiceMonitors
delete_service_monitors() {
  echo "Checking for ServiceMonitors in $NAMESPACE..."
  SERVICEMONITOR_LIST=$(kubectl get servicemonitor -n "$NAMESPACE" --no-headers | awk '{print $1}')

  if [ -n "$SERVICEMONITOR_LIST" ]; then
    echo "Found the following ServiceMonitors:"
    echo "$SERVICEMONITOR_LIST"
    echo "Deleting ServiceMonitors..."
    for sm in $SERVICEMONITOR_LIST; do
      kubectl delete servicemonitor "$sm" -n "$NAMESPACE"
      echo "Deleted ServiceMonitor: $sm"
    done
  else
    echo "No ServiceMonitors found in $NAMESPACE."
  fi
}

# Main script execution
echo "Starting cleanup in the $NAMESPACE namespace..."

delete_deployments
delete_statefulsets
delete_services
delete_service_monitors
kubectl delete secret thanos -n $NAMESPACE --ignore-not-found=true
delete_pvcs
delete_pvs

echo "Cleanup completed."

echo "Script completed."
