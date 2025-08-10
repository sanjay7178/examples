#!/bin/bash

# Demo script to showcase bookinfo-istio features

BASE_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
CONFIG_FILE=${BASE_DIR}/../kind.env

echo "=== Bookinfo with Istio and mTLS Demo ==="
echo ""

if [[ -f $CONFIG_FILE ]]; then
  source $CONFIG_FILE
else
  echo "Configuration file not found. Please ensure KubeSlice clusters are set up."
  exit 1
fi

PRODUCT_CLUSTER="${PREFIX}${WORKERS[0]}"
SERVICES_CLUSTER="${PREFIX}${WORKERS[1]}"

demo_istio_features() {
    echo "🔍 Demonstrating Istio Features:"
    echo ""
    
    echo "1. Sidecar Injection:"
    echo "   Without Istio: 2 containers per pod (app + netshoot)"
    echo "   With Istio: 3 containers per pod (app + netshoot + istio-proxy)"
    echo ""
    
    kubectx $PRODUCT_CLUSTER 2>/dev/null || kubectl config use-context $PRODUCT_CLUSTER
    if kubectl get pods -n bookinfo &>/dev/null; then
        echo "   Current productpage containers:"
        CONTAINERS=$(kubectl get pods -n bookinfo -l app=productpage -o jsonpath='{.items[0].spec.containers[*].name}' 2>/dev/null)
        echo "   $CONTAINERS"
        echo ""
    fi
    
    echo "2. mTLS Configuration:"
    echo "   Checking PeerAuthentication policy..."
    if kubectl get peerauthentication default -n bookinfo &>/dev/null; then
        MODE=$(kubectl get peerauthentication default -n bookinfo -o jsonpath='{.spec.mtls.mode}' 2>/dev/null)
        echo "   ✓ mTLS Mode: $MODE"
    else
        echo "   ⚠ PeerAuthentication not configured"
    fi
    echo ""
    
    echo "3. Cross-Cluster Service Mesh:"
    echo "   Services communicate across clusters with mTLS encryption"
    echo "   productpage (cluster 1) → reviews/details (cluster 2)"
    echo ""
    
    echo "4. Istio Gateway:"
    if kubectl get gateway bookinfo-gateway -n bookinfo &>/dev/null; then
        echo "   ✓ External access configured via Istio Gateway"
    else
        echo "   ⚠ Gateway not configured"
    fi
    echo ""
}

demo_security_features() {
    echo "🔒 Security Features:"
    echo ""
    
    echo "1. Certificate-based Authentication:"
    echo "   All services use X.509 certificates for authentication"
    echo ""
    
    echo "2. Encrypted Communication:"
    echo "   All service-to-service traffic is TLS encrypted"
    echo ""
    
    echo "3. Identity-based Authorization:"
    echo "   Services can only communicate if explicitly allowed"
    echo ""
    
    kubectx $PRODUCT_CLUSTER 2>/dev/null || kubectl config use-context $PRODUCT_CLUSTER
    PRODUCTPAGE_POD=$(kubectl get pods -n bookinfo -l app=productpage -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [[ -n "$PRODUCTPAGE_POD" ]]; then
        echo "4. Certificate Verification:"
        echo "   Checking certificates in productpage pod..."
        CERTS=$(kubectl exec -n bookinfo $PRODUCTPAGE_POD -c istio-proxy -- find /etc/ssl/certs -name "*.pem" 2>/dev/null | wc -l || echo "0")
        echo "   Found $CERTS certificate files"
        echo ""
    fi
}

demo_observability() {
    echo "📊 Observability Features:"
    echo ""
    
    echo "1. Service Mesh Metrics:"
    echo "   Istio automatically collects traffic metrics"
    echo ""
    
    echo "2. Distributed Tracing:"
    echo "   Request tracing across cluster boundaries"
    echo ""
    
    echo "3. Access Logs:"
    echo "   Detailed logs of all service interactions"
    echo ""
    
    kubectx $PRODUCT_CLUSTER 2>/dev/null || kubectl config use-context $PRODUCT_CLUSTER
    PRODUCTPAGE_POD=$(kubectl get pods -n bookinfo -l app=productpage -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [[ -n "$PRODUCTPAGE_POD" ]]; then
        echo "4. Envoy Admin Interface:"
        echo "   Access to Envoy proxy configuration and stats"
        echo "   kubectl exec -n bookinfo $PRODUCTPAGE_POD -c istio-proxy -- curl localhost:15000/stats"
        echo ""
    fi
}

show_comparison() {
    echo "📈 Comparison: Basic vs Istio Deployment"
    echo ""
    
    echo "┌─────────────────────────┬─────────────────────────┬──────────────────────────┐"
    echo "│        Feature          │      Basic Bookinfo     │    Bookinfo with Istio   │"
    echo "├─────────────────────────┼─────────────────────────┼──────────────────────────┤"
    echo "│ Service-to-service      │     Plain HTTP          │      mTLS Encrypted      │"
    echo "│ Authentication          │        None             │   Certificate-based      │"
    echo "│ Authorization           │     Kubernetes RBAC     │  Istio + Kubernetes RBAC │"
    echo "│ Traffic Management      │     Kubernetes Services │   Istio VirtualServices  │"
    echo "│ Load Balancing          │     kube-proxy          │     Envoy Proxy         │"
    echo "│ Observability           │     Basic Kubernetes    │   Rich Istio Telemetry   │"
    echo "│ External Access         │      NodePort/LB        │     Istio Gateway        │"
    echo "│ Circuit Breaking        │        Manual           │     Envoy Built-in       │"
    echo "│ Retry/Timeout           │     Application Level   │     Proxy Level          │"
    echo "│ Cross-cluster Security  │        Basic            │       Enhanced           │"
    echo "└─────────────────────────┴─────────────────────────┴──────────────────────────┘"
    echo ""
}

interactive_demo() {
    echo "🎯 Interactive Testing:"
    echo ""
    
    echo "Available test commands:"
    echo "1. ./utils/bookinfo_test.sh       - Test application functionality"
    echo "2. ./utils/verify_mtls.sh         - Verify mTLS configuration"
    echo "3. ./check-prerequisites.sh       - Check system requirements"
    echo ""
    
    read -p "Would you like to run the mTLS verification? (y/n): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Running mTLS verification..."
        ${BASE_DIR}/utils/verify_mtls.sh
    fi
}

main() {
    demo_istio_features
    demo_security_features
    demo_observability
    show_comparison
    interactive_demo
    
    echo ""
    echo "🎉 Demo completed!"
    echo ""
    echo "Next steps:"
    echo "- Deploy: ./bookinfo.sh"
    echo "- Test: ./utils/bookinfo_test.sh"
    echo "- Verify mTLS: ./utils/verify_mtls.sh"
    echo "- Read documentation: README.md"
}

main