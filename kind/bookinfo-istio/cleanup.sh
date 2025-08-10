#!/bin/bash

set -e

BASE_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
CONFIG_FILE=${BASE_DIR}/../kind.env

if [[ -f $CONFIG_FILE ]]; then
  source $CONFIG_FILE
else
  echo "File $CONFIG_FILE not found"
  exit 1
fi

# Define cluster contexts
PRODUCT_CLUSTER="${PREFIX}${WORKERS[0]}"
SERVICES_CLUSTER="${PREFIX}${WORKERS[1]}"

# Use generic contexts if the script is run in an environment without the prefix
if [[ -z "$PRODUCT_CLUSTER" ]]; then
  PRODUCT_CLUSTER="cluster1"
  SERVICES_CLUSTER="cluster2"
fi

echo "==== Starting Bookinfo-Istio Cleanup ===="
echo "Product Cluster: $PRODUCT_CLUSTER"
echo "Services Cluster: $SERVICES_CLUSTER"
echo ""

# Function to remove resources from a specific cluster
cleanup_cluster() {
  local cluster=$1
  echo "Cleaning up resources in $cluster..."
  
  # Switch context to the cluster
  kubectl config use-context $cluster
  
  # Remove authorization policies
  echo "Removing Authorization Policies..."
  kubectl delete authorizationpolicy --all -n bookinfo 2>/dev/null || true
  
  # Remove peer authentication
  echo "Removing Peer Authentication..."
  kubectl delete peerauthentication --all -n bookinfo 2>/dev/null || true
  
  # Remove Istio Gateway and VirtualService
  if [[ "$cluster" == "$PRODUCT_CLUSTER" ]]; then
    echo "Removing Istio Gateway and VirtualService..."
    kubectl delete gateway --all -n bookinfo 2>/dev/null || true
    kubectl delete virtualservice --all -n bookinfo 2>/dev/null || true
  fi
  
  # Remove ServiceExports
  echo "Removing ServiceExports..."
  kubectl delete serviceexports.networking.kubeslice.io --all -n bookinfo 2>/dev/null || true
  
  # Remove Bookinfo deployments and services
  echo "Removing Bookinfo deployments and services..."
  kubectl delete deployment --all -n bookinfo 2>/dev/null || true
  kubectl delete service --all -n bookinfo 2>/dev/null || true
  
  # Remove Bookinfo ServiceAccounts
  echo "Removing Bookinfo ServiceAccounts..."
  kubectl delete serviceaccount --all -n bookinfo 2>/dev/null || true
  
  # Delete the bookinfo namespace last
  echo "Removing bookinfo namespace..."
  kubectl delete namespace bookinfo --grace-period=0 --force 2>/dev/null || true
  
  echo "Cleanup completed for $cluster"
  echo ""
}

# Cleanup Istio resources
cleanup_istio() {
  local cluster=$1
  echo "Cleaning up Istio from $cluster (optional)..."
  
  kubectl config use-context $cluster
  
  # Check if istioctl is available
  if command -v istioctl &> /dev/null; then
    echo "Using istioctl to remove Istio..."
    istioctl uninstall --purge -y 2>/dev/null || true
  else
    echo "istioctl not found, removing Istio resources manually..."
    kubectl delete namespace istio-system --grace-period=0 --force 2>/dev/null || true
  fi
  
  echo "Istio cleanup completed for $cluster"
  echo ""
}

# Ask user if they want to cleanup just Bookinfo or also Istio
read -p "Do you want to remove Istio as well? (y/n, default: n): " remove_istio
remove_istio=${remove_istio:-n}

# Clean up both clusters
cleanup_cluster $PRODUCT_CLUSTER
cleanup_cluster $SERVICES_CLUSTER

# Optionally clean up Istio
if [[ "$remove_istio" == "y" ]]; then
  cleanup_istio $PRODUCT_CLUSTER
  cleanup_istio $SERVICES_CLUSTER
fi

echo "==== Bookinfo-Istio Cleanup Complete ===="
echo "All Bookinfo resources have been removed from both clusters."
if [[ "$remove_istio" == "y" ]]; then
  echo "Istio has also been removed."
else
  echo "Istio is still installed. To remove it later, use 'istioctl uninstall --purge' or run this script again."
fi
echo ""
echo "To remove the KubeSlice slice, use the kubeslice controller commands."
echo "For example: kubectl delete sliceconfig convoy -n kubeslice-system"

chmod +x $BASE_DIR/cleanup.sh
