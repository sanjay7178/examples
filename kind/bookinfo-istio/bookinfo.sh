#!/usr/bin/env bash

# Bookinfo deployment with Istio service mesh and mTLS across KubeSlice clusters

BASE_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
CONFIG_DIR=${BASE_DIR}/config_files

ENV_FILE=${BASE_DIR}/../kind.env

if [[ ! -f $ENV_FILE ]]; then
  echo "${ENV_FILE} file not found! Exiting"
  exit 1
fi

source $ENV_FILE

PRODUCT_CLUSTER="${PREFIX}${WORKERS[0]}"
SERVICES_CLUSTER="${PREFIX}${WORKERS[1]}"
BOOKINFO_NAMESPACE=bookinfo

uninstall() {
    echo "Uninstalling Bookinfo with Istio..."
    for cluster in $SERVICES_CLUSTER $PRODUCT_CLUSTER; do
      echo "Deleting namespace $BOOKINFO_NAMESPACE on cluster $cluster"
      kubectx $cluster
      [[ $(kubectl get namespaces | grep $BOOKINFO_NAMESPACE) ]] && kubectl delete namespace $BOOKINFO_NAMESPACE
    done
    echo "Uninstall completed"
}

help() {
    echo "Usage: bookinfo.sh [--delete] [--help]"
    echo "  Deploy Istio Bookinfo application with mTLS across KubeSlice clusters"
    echo "  --delete  Uninstall the bookinfo application"
    echo "  --help    Show this help message"
}

check_istio() {
    local cluster=$1
    echo "Checking Istio installation on cluster $cluster..."
    kubectx $cluster
    
    if ! kubectl get namespace istio-system &> /dev/null; then
        echo "Istio not found on $cluster. Please install Istio first:"
        echo "kubectl apply -f https://github.com/istio/istio/releases/download/1.20.1/istio-base.yaml"
        echo "kubectl apply -f https://github.com/istio/istio/releases/download/1.20.1/istio-discovery.yaml"
        echo "Or run: ${BASE_DIR}/install-istio.sh"
        return 1
    fi
    
    if ! kubectl get deployment istiod -n istio-system &> /dev/null; then
        echo "Istio control plane not found on $cluster"
        return 1
    fi
    
    echo "Istio verified on $cluster"
    return 0
}

enable_injection() {
    local cluster=$1
    echo "Enabling Istio sidecar injection for namespace $BOOKINFO_NAMESPACE on $cluster"
    kubectx $cluster
    kubectl label namespace $BOOKINFO_NAMESPACE istio-injection=enabled --overwrite
}

# Get the options
while getopts ":d:delete:help:" option; do
  case $option in
    d | delete) # Uninstall
      uninstall
      exit;;
    h |help)
      help
      exit;;
   esac
done

echo "=== Deploying Bookinfo with Istio and mTLS ==="

# Check Istio installation on both clusters
check_istio $PRODUCT_CLUSTER || exit 1
check_istio $SERVICES_CLUSTER || exit 1

# Create namespaces and enable injection
echo "Creating bookinfo namespace on product cluster..."
kubectx $PRODUCT_CLUSTER
kubectl create namespace $BOOKINFO_NAMESPACE || true
enable_injection $PRODUCT_CLUSTER

echo "Creating bookinfo namespace on services cluster..."
kubectx $SERVICES_CLUSTER
kubectl create namespace $BOOKINFO_NAMESPACE || true
enable_injection $SERVICES_CLUSTER

function wait_for_pods {
  local cluster=$1
  echo "Waiting for pods to be ready on $cluster..."
  kubectx $cluster
  
  for pod in $(kubectl get pods -n $BOOKINFO_NAMESPACE | grep -v NAME | awk '{ print $1 }'); do
    counter=0

    while [[ $(kubectl get pods $pod -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}' -n $BOOKINFO_NAMESPACE) != True ]]; do
      sleep 1
      let counter=counter+1

      if ((counter == 180)); then  # Increased timeout for Istio sidecar injection
        echo "POD $pod failed to start in 180 seconds"
        kubectl describe pod $pod -n $BOOKINFO_NAMESPACE
        echo "Exiting"
        exit -1
      fi
    done
  done
  echo "All pods ready on $cluster"
}

echo "Installing productpage on $PRODUCT_CLUSTER..."
kubectx $PRODUCT_CLUSTER
kubectl apply -f ${CONFIG_DIR}/productpage.yaml -n $BOOKINFO_NAMESPACE

echo "Waiting for productpage pods to be ready..."
wait_for_pods $PRODUCT_CLUSTER

echo "Installing services on $SERVICES_CLUSTER..."
kubectx $SERVICES_CLUSTER
kubectl apply -f ${CONFIG_DIR}/details.yaml -n $BOOKINFO_NAMESPACE
kubectl apply -f ${CONFIG_DIR}/ratings.yaml -n $BOOKINFO_NAMESPACE
kubectl apply -f ${CONFIG_DIR}/reviews.yaml -n $BOOKINFO_NAMESPACE

echo "Waiting for service pods to be ready..."
wait_for_pods $SERVICES_CLUSTER

echo "Applying KubeSlice ServiceExports..."
kubectl apply -f ${CONFIG_DIR}/serviceexports.yaml -n $BOOKINFO_NAMESPACE
echo "Waiting for ServiceExports to be created..."
sleep 30

echo "Verifying ServiceExports..."
kubectl get serviceexport -n $BOOKINFO_NAMESPACE

echo "Applying mTLS configuration on both clusters..."
kubectx $PRODUCT_CLUSTER
kubectl apply -f ${CONFIG_DIR}/peer-authentication.yaml
kubectx $SERVICES_CLUSTER
kubectl apply -f ${CONFIG_DIR}/peer-authentication.yaml

echo "Applying Istio Gateway configuration..."
kubectx $PRODUCT_CLUSTER
kubectl apply -f ${CONFIG_DIR}/gateway.yaml

echo "Verifying ServiceImports on product cluster..."
kubectl get serviceimport -n $BOOKINFO_NAMESPACE

echo "Printing services on both clusters..."
echo "=== Product Cluster Services ==="
kubectl get services -n $BOOKINFO_NAMESPACE

kubectx $SERVICES_CLUSTER
echo "=== Services Cluster Services ==="
kubectl get services -n $BOOKINFO_NAMESPACE

echo "=== Testing bookinfo services with mTLS ==="
echo "Waiting for services to be available..."
sleep 40

echo "Deployment completed successfully!"
echo "Run: bash ${BASE_DIR}/utils/bookinfo_test.sh"
echo "To test the application."

bash ${BASE_DIR}/utils/bookinfo_test.sh
