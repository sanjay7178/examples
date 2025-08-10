#!/bin/bash

# Script to verify mTLS is working between services

set -e

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

echo "=== mTLS Verification Script ==="

verify_certificates() {
    local cluster=$1
    local app=$2
    
    echo "Checking certificates for $app on $cluster..."
    kubectx $cluster
    
    POD=$(kubectl get pods -n bookinfo -l app=$app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [[ -z "$POD" ]]; then
        echo "✗ No pod found for app=$app"
        return 1
    fi
    
    echo "Pod: $POD"
    
    # Check if istio-proxy container exists
    if ! kubectl get pod $POD -n bookinfo -o jsonpath='{.spec.containers[*].name}' | grep -q istio-proxy; then
        echo "✗ istio-proxy container not found"
        return 1
    fi
    
    # Check certificates in the istio-proxy
    echo "Checking certificates in istio-proxy..."
    CERT_COUNT=$(kubectl exec -n bookinfo $POD -c istio-proxy -- sh -c 'find /etc/ssl/certs -name "*.pem" | wc -l' 2>/dev/null || echo "0")
    echo "Certificate files found: $CERT_COUNT"
    
    # Check Envoy config for mTLS
    echo "Checking Envoy configuration for mTLS..."
    TLS_CONFIG=$(kubectl exec -n bookinfo $POD -c istio-proxy -- sh -c 'curl -s localhost:15000/config_dump | grep -c "tls_context"' 2>/dev/null || echo "0")
    echo "TLS contexts found: $TLS_CONFIG"
    
    if [[ "$TLS_CONFIG" -gt 0 ]]; then
        echo "✓ $app has mTLS configuration"
    else
        echo "⚠ $app may not have mTLS properly configured"
    fi
}

test_mtls_communication() {
    echo "Testing mTLS communication between services..."
    
    kubectx $PRODUCT_CLUSTER
    PRODUCTPAGE_POD=$(kubectl get pods -n bookinfo -l app=productpage -o jsonpath='{.items[0].metadata.name}')
    
    if [[ -z "$PRODUCTPAGE_POD" ]]; then
        echo "✗ Productpage pod not found"
        return 1
    fi
    
    echo "Testing connection to reviews service with mTLS..."
    # Try to connect through Envoy proxy
    REVIEWS_TEST=$(kubectl exec -n bookinfo $PRODUCTPAGE_POD -c productpage -- sh -c 'curl -s -w "%{http_code}" -o /dev/null http://reviews.bookinfo.svc.slice.local:9080/reviews/0' 2>/dev/null || echo "000")
    
    if [[ "$REVIEWS_TEST" == "200" ]]; then
        echo "✓ mTLS connection to reviews service successful"
    else
        echo "⚠ mTLS connection to reviews service returned: $REVIEWS_TEST"
    fi
    
    echo "Testing connection to details service with mTLS..."
    DETAILS_TEST=$(kubectl exec -n bookinfo $PRODUCTPAGE_POD -c productpage -- sh -c 'curl -s -w "%{http_code}" -o /dev/null http://details.bookinfo.svc.slice.local:9080/details/0' 2>/dev/null || echo "000")
    
    if [[ "$DETAILS_TEST" == "200" ]]; then
        echo "✓ mTLS connection to details service successful"
    else
        echo "⚠ mTLS connection to details service returned: $DETAILS_TEST"
    fi
}

check_peer_authentication() {
    echo "Checking PeerAuthentication policies..."
    
    for cluster in $PRODUCT_CLUSTER $SERVICES_CLUSTER; do
        echo "Cluster: $cluster"
        kubectx $cluster
        
        if kubectl get peerauthentication default -n bookinfo &>/dev/null; then
            MODE=$(kubectl get peerauthentication default -n bookinfo -o jsonpath='{.spec.mtls.mode}')
            echo "✓ PeerAuthentication mode: $MODE"
        else
            echo "✗ PeerAuthentication not found"
        fi
    done
}

main() {
    echo "Starting mTLS verification..."
    echo ""
    
    check_peer_authentication
    echo ""
    
    verify_certificates $PRODUCT_CLUSTER "productpage"
    echo ""
    
    verify_certificates $SERVICES_CLUSTER "details"
    echo ""
    
    verify_certificates $SERVICES_CLUSTER "reviews"
    echo ""
    
    verify_certificates $SERVICES_CLUSTER "ratings"
    echo ""
    
    test_mtls_communication
    echo ""
    
    echo "=== mTLS Verification Complete ==="
}

CLUSTERS=("cluster1" "cluster2")

echo "=== Verifying mTLS Configuration ==="
echo

for cluster in "${CLUSTERS[@]}"; do
  echo "Checking cluster: $cluster"
  echo "---------------------------------"
  
  # Check PeerAuthentication policy
  echo "PeerAuthentication policy:"
  kubectl --context=$cluster get peerauthentication -n bookinfo
  
  # Get a pod with istio-proxy for verification
  POD=$(kubectl --context=$cluster get pod -n bookinfo -l app=productpage -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || \
        kubectl --context=$cluster get pod -n bookinfo -l app=details -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  
  if [ -n "$POD" ]; then
    echo
    echo "Checking mTLS certificates in pod $POD:"
    kubectl --context=$cluster exec -n bookinfo $POD -c istio-proxy -- pilot-agent request GET stats | grep ssl_context
    
    echo
    echo "Verifying Envoy is configured for mTLS:"
    kubectl --context=$cluster exec -n bookinfo $POD -c istio-proxy -- curl -s localhost:15000/config_dump | grep -o "\"tls_inspector\"\|\"transport_socket\"" | sort | uniq -c
    
    echo
    echo "Checking upstream TLS configuration:"
    kubectl --context=$cluster exec -n bookinfo $POD -c istio-proxy -- curl -s localhost:15000/config_dump | grep '"alpn_protocols": \["istio"\]' -B 5 -A 5 | head -n 15
  else
    echo "No pods with istio-proxy found in namespace bookinfo"
  fi
  
  echo
  echo "Checking for Authorization Policies:"
  kubectl --context=$cluster get authorizationpolicies -n bookinfo
  
  echo
  echo "---------------------------------"
  echo
done

echo "=== mTLS Verification Complete ==="

main