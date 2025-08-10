# Deployment Guide: Bookinfo with Istio and mTLS

This guide provides step-by-step instructions for deploying the Istio-enabled Bookinfo application across KubeSlice clusters.

## Overview

The deployment creates a secure, service mesh-enabled microservices application with:
- Cross-cluster communication via KubeSlice
- End-to-end mTLS encryption
- Automatic certificate management
- Traffic monitoring and observability

## Prerequisites Setup

### 1. Verify Environment
```bash
cd kind/bookinfo-istio
./check-prerequisites.sh
```

Expected output should show:
- ✓ kubectl is available
- ✓ Can list namespaces
- ✓ Found kind.env configuration file
- ✓ Product cluster (kind-worker-1) is accessible
- ✓ Services cluster (kind-worker-2) is accessible

### 2. Cluster Requirements
Each cluster should have:
- Kubernetes 1.21+
- 2+ CPU cores available
- 4GB+ RAM available
- KubeSlice operator installed and configured

## Installation Steps

### Step 1: Install Istio (if needed)
```bash
# Check if Istio is already installed
kubectl get pods -n istio-system

# If not installed, run:
./install-istio.sh
```

This script will:
- Install Istio base components
- Deploy Istio control plane (istiod)
- Configure mTLS policies
- Verify installation

### Step 2: Deploy Bookinfo Application
```bash
./bookinfo.sh
```

The deployment process:
1. ✅ Checks Istio installation on both clusters
2. ✅ Creates bookinfo namespace with sidecar injection enabled
3. ✅ Deploys productpage service on cluster 1
4. ✅ Deploys details, reviews, ratings services on cluster 2
5. ✅ Configures KubeSlice ServiceExports for cross-cluster access
6. ✅ Applies mTLS policies
7. ✅ Sets up Istio Gateway for external access

### Step 3: Verify Deployment
```bash
./utils/bookinfo_test.sh
```

This will test:
- Basic application functionality
- Istio sidecar injection
- mTLS configuration
- Cross-cluster connectivity
- Gateway configuration

### Step 4: Verify mTLS Security
```bash
./utils/verify_mtls.sh
```

This validates:
- Certificate presence in Envoy proxies
- PeerAuthentication policies
- Encrypted service communication
- TLS configuration

## Expected Results

### Successful Deployment Indicators

1. **Pods Running**: All pods should have 3 containers (app + netshoot + istio-proxy)
```bash
kubectl get pods -n bookinfo
NAME                              READY   STATUS    RESTARTS   AGE
productpage-v1-xyz                3/3     Running   0          5m
```

2. **mTLS Enabled**: STRICT mode configured
```bash
kubectl get peerauthentication default -n bookinfo -o yaml
spec:
  mtls:
    mode: STRICT
```

3. **Cross-cluster Services**: ServiceImports available
```bash
kubectl get serviceimport -n bookinfo
NAME      TYPE          IP           AGE
details   ClusterSetIP  10.x.x.x     5m
reviews   ClusterSetIP  10.x.x.x     5m
```

4. **Application Accessible**: Web interface responds
```bash
curl http://<gateway-ip>/productpage
# Should return HTML content with book information
```

## Troubleshooting

### Common Issues and Solutions

#### Issue: Pods stuck in Pending
```bash
kubectl describe pod <pod-name> -n bookinfo
```
**Solutions**:
- Check resource availability
- Verify Istio sidecar injector is running
- Ensure namespace has injection label

#### Issue: mTLS connection failures
```bash
kubectl logs <pod-name> -n bookinfo -c istio-proxy
```
**Solutions**:
- Verify PeerAuthentication is applied
- Check certificate rotation
- Validate service account permissions

#### Issue: Cross-cluster connectivity problems
```bash
kubectl get serviceexport -n bookinfo
kubectl get serviceimport -n bookinfo
```
**Solutions**:
- Verify KubeSlice configuration
- Check slice connectivity
- Validate DNS resolution

#### Issue: Istio installation problems
```bash
kubectl get pods -n istio-system
kubectl logs deployment/istiod -n istio-system
```
**Solutions**:
- Ensure sufficient cluster resources
- Check image pull policies
- Verify cluster permissions

### Debug Commands

```bash
# Check Istio configuration
istioctl analyze -n bookinfo

# View Envoy configuration
kubectl exec -n bookinfo <pod-name> -c istio-proxy -- curl localhost:15000/config_dump

# Check service mesh traffic
kubectl exec -n bookinfo <pod-name> -c istio-proxy -- curl localhost:15000/stats | grep cluster

# Verify mTLS certificates
kubectl exec -n bookinfo <pod-name> -c istio-proxy -- openssl s_client -connect details:9080

# View access logs
kubectl logs <pod-name> -n bookinfo -c istio-proxy
```

## Performance Tuning

### Resource Allocation
Adjust resources based on load:
```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 200m
    memory: 256Mi
```

### Istio Configuration
Optimize for your environment:
```yaml
# Reduce proxy resources for testing
spec:
  defaultConfig:
    proxyStatsMatcher:
      inclusionRegexps:
      - ".*circuit_breakers.*"
      - ".*upstream_rq_retry.*"
```

## Security Hardening

### 1. Network Policies
Implement Kubernetes NetworkPolicies alongside Istio:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: bookinfo-deny-all
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

### 2. RBAC Configuration
Use minimal service account permissions:
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: bookinfo-minimal
automountServiceAccountToken: false
```

### 3. Certificate Management
Monitor certificate expiration:
```bash
kubectl exec -n bookinfo <pod-name> -c istio-proxy -- \
  openssl x509 -in /var/run/secrets/istio/root-cert.pem -text -noout
```

## Monitoring Setup

### Enable Telemetry
```bash
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/prometheus.yaml
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/grafana.yaml
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/kiali.yaml
```

### Access Dashboards
```bash
# Kiali (Service Mesh Visualization)
kubectl port-forward svc/kiali -n istio-system 20001:20001

# Grafana (Metrics)
kubectl port-forward svc/grafana -n istio-system 3000:3000

# Prometheus (Raw Metrics)
kubectl port-forward svc/prometheus -n istio-system 9090:9090
```

## Cleanup

### Remove Application
```bash
./bookinfo.sh --delete
```

### Remove Istio (if needed)
```bash
kubectl delete namespace istio-system
kubectl delete validatingwebhookconfiguration istiod-default-validator
kubectl delete mutatingwebhookconfiguration istio-sidecar-injector
```

## Next Steps

1. **Extend with Observability**: Add Jaeger for distributed tracing
2. **Implement Canary Deployments**: Use Istio traffic routing
3. **Add Rate Limiting**: Configure Envoy rate limiting
4. **Security Policies**: Implement fine-grained authorization
5. **Multi-cluster Service Discovery**: Extend to additional clusters

## References

- [Istio Documentation](https://istio.io/latest/docs/)
- [KubeSlice Documentation](https://docs.avesha.io/)
- [Bookinfo Application Guide](https://istio.io/latest/docs/examples/bookinfo/)
- [mTLS Configuration](https://istio.io/latest/docs/concepts/security/#mutual-tls-authentication)