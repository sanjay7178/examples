#!/usr/bin/env bash

# Script to install and configure Istio on KubeSlice clusters
# This script uses kubectl to install Istio when istioctl is not available

set -e

BASE_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
ENV_FILE=${BASE_DIR}/../kind.env

if [[ ! -f $ENV_FILE ]]; then
  echo "${ENV_FILE} file not found! Exiting"
  exit 1
fi

source $ENV_FILE

PRODUCT_CLUSTER="${PREFIX}${WORKERS[0]}"
SERVICES_CLUSTER="${PREFIX}${WORKERS[1]}"
ISTIO_VERSION="1.20.1"

install_istio_cluster() {
    local cluster=$1
    echo "Installing Istio on cluster: $cluster"
    
    kubectx $cluster
    
    # Check if Istio is already installed
    if kubectl get namespace istio-system &> /dev/null; then
        echo "Istio appears to be already installed on $cluster"
        if kubectl get deployment istiod -n istio-system &> /dev/null; then
            echo "Istio control plane is running on $cluster"
            return 0
        fi
    fi
    
    echo "Installing Istio base components..."
    # Install Istio base using the official manifests
    kubectl apply -f https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istio-base.yaml || {
        echo "Failed to install Istio base from remote URL, using local fallback"
        kubectl create namespace istio-system || true
        kubectl apply -f ${BASE_DIR}/config_files/istio-base.yaml
    }
    
    echo "Installing Istio discovery service..."
    # Install Istio discovery (istiod)
    kubectl apply -f https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istio-discovery.yaml || {
        echo "Failed to install Istio discovery from remote URL, using local fallback"
        kubectl apply -f ${BASE_DIR}/config_files/istio-discovery.yaml
    }
    
    # Wait for Istio to be ready
    echo "Waiting for Istio to be ready..."
    kubectl wait --for=condition=Available deployment/istiod -n istio-system --timeout=300s || {
        echo "Warning: Istio deployment may not be fully ready. Continuing..."
        kubectl get pods -n istio-system
    }
    
    echo "Istio installation completed on $cluster"
}

install_istio_gateway() {
    local cluster=$1
    echo "Installing Istio Gateway on cluster: $cluster"
    
    kubectx $cluster
    
    # Install Istio Ingress Gateway
    kubectl apply -f https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istio-gateway.yaml || {
        echo "Warning: Could not install Istio Gateway from remote URL"
        echo "Istio Gateway installation requires manual setup"
    }
    
    echo "Istio Gateway installation attempted on $cluster"
}

configure_mtls() {
    local cluster=$1
    echo "Configuring mTLS on cluster: $cluster"
    
    kubectx $cluster
    
    # Ensure bookinfo namespace exists
    kubectl create namespace bookinfo || true
    
    # Apply PeerAuthentication for strict mTLS
    kubectl apply -f ${BASE_DIR}/config_files/peer-authentication.yaml || {
        echo "Warning: Failed to apply mTLS configuration"
    }
    
    echo "mTLS configuration applied on $cluster"
}

verify_istio() {
    local cluster=$1
    echo "Verifying Istio installation on cluster: $cluster"
    
    kubectx $cluster
    
    echo "Checking Istio system pods..."
    kubectl get pods -n istio-system
    
    echo "Checking Istio version..."
    kubectl get deployment istiod -n istio-system -o jsonpath='{.metadata.labels.app\.version}' || echo "Unable to get Istio version"
    
    echo ""
}

main() {
    echo "=== Installing Istio on KubeSlice clusters ==="
    echo "Istio version: $ISTIO_VERSION"
    echo ""
    
    # Install Istio on both clusters
    install_istio_cluster $PRODUCT_CLUSTER
    echo ""
    install_istio_cluster $SERVICES_CLUSTER
    echo ""
    
    # Install Istio Gateway (optional, for external access)
    install_istio_gateway $PRODUCT_CLUSTER
    echo ""
    
    # Configure mTLS on both clusters
    configure_mtls $PRODUCT_CLUSTER
    configure_mtls $SERVICES_CLUSTER
    echo ""
    
    # Verify installations
    echo "=== Verification ==="
    verify_istio $PRODUCT_CLUSTER
    verify_istio $SERVICES_CLUSTER
    
    echo "=== Istio installation completed ==="
    echo "You can now deploy the bookinfo application with: ./bookinfo.sh"
}

help() {
    echo "Usage: install-istio.sh [--help]"
    echo "  Install Istio service mesh on KubeSlice clusters"
    echo "  --help    Show this help message"
}

# Get the options
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      help
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      help
      exit 1
      ;;
  esac
done

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi