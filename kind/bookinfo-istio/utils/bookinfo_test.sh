#!/bin/bash

# Enhanced test script for bookinfo with Istio and mTLS verification

BASE_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
CONFIG_FILE=${BASE_DIR}/../../kind.env

if [[ -f $CONFIG_FILE ]]; then
  source $CONFIG_FILE
else
  echo "File $CONFIG_FILE not found"
  exit 1
fi

PRODUCT_CLUSTER="${PREFIX}${WORKERS[0]}"
SERVICES_CLUSTER="${PREFIX}${WORKERS[1]}"

echo "=== Testing Bookinfo with Istio and mTLS ==="

# Test basic connectivity
test_basic_connectivity() {
    echo "#### Testing basic Bookinfo connectivity"
    kubectx $PRODUCT_CLUSTER
    PRODUCT_NODE=$(kubectl get pods -o wide -n bookinfo | tail -1 | awk '{ print $7 }')
    
    BI_PORT=$(kubectl get services -n bookinfo | egrep 'productpage' | grep -o -P '(?<=:).*(?=/TCP)')
    echo "Product page port: $BI_PORT"
    
    BI_ADDR_STR=$(kubectl get nodes -o wide | egrep "$PRODUCT_NODE" | awk '{ print $6 }')
    
    WSL=$(ps -elf | egrep "wsl\/docker-desktop" | egrep -v grep | awk '{ print $15 }')
    
    if [[ $WSL != "" ]]; then
        echo "#### WSL Environment Detected"
        echo "Started forwarding the port to access the ProductPage UI"
        echo "Please use CTRL-C to exit & stop the port forwarding"
        echo "Access productpage on browser with the URL: http://localhost:$BI_PORT/productpage"
        kubectl port-forward svc/productpage -n bookinfo $BI_PORT:9080
        return
    fi
    
    echo "Testing: curl http://$BI_ADDR_STR:$BI_PORT/productpage"
    if curl -s http://$BI_ADDR_STR:$BI_PORT/productpage | grep -q 'Comedy of Errors'; then
        echo "✓ Bookinfo Reviews Page OK"
    else
        echo "✗ Bookinfo Reviews Page FAIL"
    fi
    
    if curl -s http://$BI_ADDR_STR:$BI_PORT/productpage | grep -q 'Type'; then
        echo "✓ Bookinfo Details Page OK"
    else
        echo "✗ Bookinfo Details Page FAIL"
    fi
    
    if curl -s http://$BI_ADDR_STR:$BI_PORT/productpage | grep -q 'slapstick'; then
        echo "✓ Bookinfo Product Page OK"
    else
        echo "✗ Bookinfo Product Page FAIL"
    fi
}

# Test Istio proxy presence
test_istio_sidecars() {
    echo "#### Testing Istio sidecar injection"
    
    echo "Checking productpage sidecars on $PRODUCT_CLUSTER..."
    kubectx $PRODUCT_CLUSTER
    PROD_CONTAINERS=$(kubectl get pods -n bookinfo -l app=productpage -o jsonpath='{.items[0].spec.containers[*].name}')
    if echo "$PROD_CONTAINERS" | grep -q "istio-proxy"; then
        echo "✓ Productpage has Istio sidecar"
    else
        echo "✗ Productpage missing Istio sidecar"
        echo "Containers: $PROD_CONTAINERS"
    fi
    
    echo "Checking services sidecars on $SERVICES_CLUSTER..."
    kubectx $SERVICES_CLUSTER
    
    for service in details reviews ratings; do
        CONTAINERS=$(kubectl get pods -n bookinfo -l app=$service -o jsonpath='{.items[0].spec.containers[*].name}' 2>/dev/null)
        if echo "$CONTAINERS" | grep -q "istio-proxy"; then
            echo "✓ $service has Istio sidecar"
        else
            echo "✗ $service missing Istio sidecar"
            echo "Containers: $CONTAINERS"
        fi
    done
}

# Test mTLS configuration
test_mtls() {
    echo "#### Testing mTLS configuration"
    
    kubectx $PRODUCT_CLUSTER
    
    # Check PeerAuthentication
    if kubectl get peerauthentication default -n bookinfo &>/dev/null; then
        MTLS_MODE=$(kubectl get peerauthentication default -n bookinfo -o jsonpath='{.spec.mtls.mode}')
        if [[ "$MTLS_MODE" == "STRICT" ]]; then
            echo "✓ mTLS is configured in STRICT mode"
        else
            echo "⚠ mTLS mode: $MTLS_MODE (expected STRICT)"
        fi
    else
        echo "✗ PeerAuthentication not found"
    fi
    
    # Check for mTLS certificates in productpage pod
    PRODUCTPAGE_POD=$(kubectl get pods -n bookinfo -l app=productpage -o jsonpath='{.items[0].metadata.name}')
    if [[ -n "$PRODUCTPAGE_POD" ]]; then
        echo "Checking mTLS certificates in productpage pod..."
        CERTS=$(kubectl exec -n bookinfo $PRODUCTPAGE_POD -c istio-proxy -- find /etc/ssl/certs -name "*.pem" | wc -l 2>/dev/null || echo "0")
        if [[ "$CERTS" -gt 0 ]]; then
            echo "✓ Found $CERTS certificate files in istio-proxy"
        else
            echo "⚠ No certificates found in istio-proxy"
        fi
    fi
}

# Test service connectivity with mTLS
test_service_connectivity() {
    echo "#### Testing service-to-service connectivity with mTLS"
    
    kubectx $PRODUCT_CLUSTER
    PRODUCTPAGE_POD=$(kubectl get pods -n bookinfo -l app=productpage -o jsonpath='{.items[0].metadata.name}')
    
    if [[ -n "$PRODUCTPAGE_POD" ]]; then
        echo "Testing connectivity from productpage to reviews service..."
        
        # Test connection to reviews service through Istio proxy
        REVIEWS_RESPONSE=$(kubectl exec -n bookinfo $PRODUCTPAGE_POD -c productpage -- curl -s "http://reviews.bookinfo.svc.slice.local:9080/reviews/0" | head -c 100)
        if [[ -n "$REVIEWS_RESPONSE" ]]; then
            echo "✓ Productpage can connect to reviews service"
        else
            echo "✗ Failed to connect to reviews service"
        fi
        
        echo "Testing connectivity from productpage to details service..."
        DETAILS_RESPONSE=$(kubectl exec -n bookinfo $PRODUCTPAGE_POD -c productpage -- curl -s "http://details.bookinfo.svc.slice.local:9080/details/0" | head -c 100)
        if [[ -n "$DETAILS_RESPONSE" ]]; then
            echo "✓ Productpage can connect to details service"
        else
            echo "✗ Failed to connect to details service"
        fi
    else
        echo "✗ Productpage pod not found"
    fi
}

# Test Istio configuration
test_istio_config() {
    echo "#### Testing Istio configuration"
    
    kubectx $PRODUCT_CLUSTER
    
    # Check Gateway
    if kubectl get gateway bookinfo-gateway -n bookinfo &>/dev/null; then
        echo "✓ Istio Gateway configured"
    else
        echo "✗ Istio Gateway not found"
    fi
    
    # Check VirtualService
    if kubectl get virtualservice bookinfo -n bookinfo &>/dev/null; then
        echo "✓ Istio VirtualService configured"
    else
        echo "✗ Istio VirtualService not found"
    fi
}

main() {
    test_basic_connectivity
    echo ""
    test_istio_sidecars
    echo ""
    test_mtls
    echo ""
    test_service_connectivity
    echo ""
    test_istio_config
    echo ""
    echo "=== Test Summary ==="
    echo "If all tests pass, your Bookinfo application is running with Istio and mTLS!"
}

main

