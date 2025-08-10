#!/bin/bash

# Prerequisites check script for bookinfo-istio deployment

echo "=== Prerequisites Check for Bookinfo-Istio ==="

check_command() {
    local cmd=$1
    local package=$2
    
    if command -v $cmd &> /dev/null; then
        echo "✓ $cmd is available"
        return 0
    else
        echo "✗ $cmd is not available"
        if [[ -n "$package" ]]; then
            echo "  Install with: $package"
        fi
        return 1
    fi
}

check_kubernetes_connectivity() {
    echo "Checking Kubernetes connectivity..."
    
    if kubectl cluster-info &> /dev/null; then
        echo "✓ kubectl can connect to cluster"
        
        # Check current context
        CURRENT_CONTEXT=$(kubectl config current-context)
        echo "  Current context: $CURRENT_CONTEXT"
        
        # Check if we can list namespaces
        if kubectl get namespaces &> /dev/null; then
            echo "✓ Can list namespaces"
        else
            echo "✗ Cannot list namespaces (insufficient permissions)"
        fi
    else
        echo "✗ kubectl cannot connect to cluster"
        echo "  Please ensure your kubeconfig is set up correctly"
        return 1
    fi
}

check_kubeslice_clusters() {
    echo "Checking KubeSlice cluster configuration..."
    
    BASE_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
    ENV_FILE=${BASE_DIR}/../kind.env
    
    if [[ -f $ENV_FILE ]]; then
        echo "✓ Found kind.env configuration file"
        source $ENV_FILE
        
        PRODUCT_CLUSTER="${PREFIX}${WORKERS[0]}"
        SERVICES_CLUSTER="${PREFIX}${WORKERS[1]}"
        
        echo "  Product cluster: $PRODUCT_CLUSTER"
        echo "  Services cluster: $SERVICES_CLUSTER"
        
        # Check if kubectx is available
        if command -v kubectx &> /dev/null; then
            echo "✓ kubectx is available"
            
            # Check if clusters exist
            if kubectx $PRODUCT_CLUSTER &> /dev/null; then
                echo "✓ Product cluster ($PRODUCT_CLUSTER) is accessible"
            else
                echo "✗ Product cluster ($PRODUCT_CLUSTER) is not accessible"
            fi
            
            if kubectx $SERVICES_CLUSTER &> /dev/null; then
                echo "✓ Services cluster ($SERVICES_CLUSTER) is accessible"
            else
                echo "✗ Services cluster ($SERVICES_CLUSTER) is not accessible"
            fi
        else
            echo "⚠ kubectx is not available - will use kubectl config use-context instead"
            
            # Check contexts manually
            CONTEXTS=$(kubectl config get-contexts -o name)
            if echo "$CONTEXTS" | grep -q "$PRODUCT_CLUSTER"; then
                echo "✓ Product cluster context exists"
            else
                echo "✗ Product cluster context not found"
            fi
            
            if echo "$CONTEXTS" | grep -q "$SERVICES_CLUSTER"; then
                echo "✓ Services cluster context exists"
            else
                echo "✗ Services cluster context not found"
            fi
        fi
    else
        echo "✗ kind.env configuration file not found at $ENV_FILE"
        echo "  Please ensure you're running this from the correct directory"
        return 1
    fi
}

check_istio_availability() {
    echo "Checking Istio availability..."
    
    if command -v istioctl &> /dev/null; then
        echo "✓ istioctl is available"
        ISTIO_VERSION=$(istioctl version --short 2>/dev/null || echo "unknown")
        echo "  Version: $ISTIO_VERSION"
    else
        echo "⚠ istioctl is not available"
        echo "  The deployment will use kubectl to install Istio manifests"
        echo "  For better control, consider installing istioctl:"
        echo "  curl -L https://istio.io/downloadIstio | sh -"
    fi
}

main() {
    echo "Required tools:"
    check_command "kubectl" "https://kubernetes.io/docs/tasks/tools/install-kubectl/"
    echo ""
    
    echo "Optional tools:"
    check_command "kubectx" "https://github.com/ahmetb/kubectx"
    check_command "istioctl" "https://istio.io/latest/docs/setup/getting-started/"
    echo ""
    
    check_kubernetes_connectivity
    echo ""
    
    check_kubeslice_clusters
    echo ""
    
    check_istio_availability
    echo ""
    
    echo "=== Summary ==="
    echo "If all checks pass, you're ready to deploy bookinfo with Istio!"
    echo ""
    echo "Deployment steps:"
    echo "1. Install Istio (optional): ./install-istio.sh"
    echo "2. Deploy bookinfo: ./bookinfo.sh"
    echo "3. Test deployment: ./utils/bookinfo_test.sh"
    echo "4. Verify mTLS: ./utils/verify_mtls.sh"
}

main