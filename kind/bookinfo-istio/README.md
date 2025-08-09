# Bookinfo with Istio and mTLS on KubeSlice

This example deploys the Istio Bookinfo application across two KubeSlice-connected clusters with Istio service mesh and mTLS enabled for secure service-to-service communication.

## Architecture

```
┌─────────────────────────────────────┐    ┌─────────────────────────────────────┐
│          Cluster 1 (Product)       │    │        Cluster 2 (Services)        │
│  ┌─────────────────────────────────┐ │    │ ┌─────────────────────────────────┐ │
│  │        productpage              │ │    │ │             details             │ │
│  │    ┌─────────────────────┐      │ │    │ │    ┌─────────────────────┐      │ │
│  │    │   Istio Proxy       │      │ │    │ │    │   Istio Proxy       │      │ │
│  │    │    (Envoy)          │◄─────┼─┼────┼─┼────►   (Envoy)          │      │ │
│  │    └─────────────────────┘      │ │    │ │    └─────────────────────┘      │ │
│  │    │   productpage       │      │ │    │ │    │   details           │      │ │
│  │    │   container         │      │ │    │ │    │   container         │      │ │
│  │    └─────────────────────┘      │ │    │ │    └─────────────────────┘      │ │
│  └─────────────────────────────────┘ │    │ └─────────────────────────────────┘ │
│                                      │    │                                      │
│  ┌─────────────────────────────────┐ │    │ ┌─────────────────────────────────┐ │
│  │      Istio Gateway              │ │    │ │             reviews             │ │
│  │  ┌─────────────────────────────┐ │ │    │ │    ┌─────────────────────┐      │ │
│  │  │      External Access        │ │ │    │ │    │   Istio Proxy       │      │ │
│  │  │     (port 80/443)           │ │ │    │ │    │    (Envoy)          │◄─────┼─┼──┐
│  │  └─────────────────────────────┘ │ │    │ │    └─────────────────────┘      │ │  │
│  └─────────────────────────────────┘ │    │ │    │   reviews           │      │ │  │
│                                      │    │ │    │   container         │      │ │  │
│           KubeSlice                  │    │ │    └─────────────────────┘      │ │  │
│        Service Mesh                  │    │ └─────────────────────────────────┘ │  │
└─────────────────────────────────────┘    │                                      │  │
                                           │ ┌─────────────────────────────────┐ │  │
                                           │ │             ratings             │ │  │
                                           │ │    ┌─────────────────────┐      │ │  │
                                           │ │    │   Istio Proxy       │      │ │  │
                                           │ │    │    (Envoy)          │◄─────┼─┼──┘
                                           │ │    └─────────────────────┘      │ │
                                           │ │    │   ratings           │      │ │
                                           │ │    │   container         │      │ │
                                           │ │    └─────────────────────┘      │ │
                                           │ └─────────────────────────────────┘ │
                                           └─────────────────────────────────────┘
```

### Service Distribution
- **Cluster 1 (Product Cluster)**: Runs the productpage service with Istio Gateway for external access
- **Cluster 2 (Services Cluster)**: Runs details, ratings, and reviews services
- **Service Mesh**: Istio with automatic sidecar injection on both clusters
- **Security**: Strict mTLS enabled between all services
- **Cross-cluster connectivity**: KubeSlice ServiceExport/ServiceImport with service mesh overlay

### Security Features
- **Mutual TLS (mTLS)**: All service-to-service communication is encrypted and authenticated
- **PeerAuthentication**: Enforces STRICT mTLS mode for the bookinfo namespace
- **AuthorizationPolicy**: Controls which services can communicate with each other
- **Certificate Management**: Automatic certificate rotation via Istio's Certificate Authority

## Prerequisites

Before deploying this example, ensure you have:

1. **KubeSlice Environment**: Two kind clusters connected via KubeSlice
2. **Required Tools**:
   - `kubectl` - Kubernetes command-line tool
   - `kubectx` (optional) - For easier cluster switching
   - `istioctl` (optional) - For advanced Istio operations

3. **Cluster Requirements**:
   - Kubernetes 1.21+ on both clusters
   - Sufficient resources (2+ CPU cores, 4GB+ RAM per cluster)
   - Network connectivity between clusters via KubeSlice

Run the prerequisites check:
```bash
./check-prerequisites.sh
```

## Quick Start

### 1. Check Prerequisites
```bash
./check-prerequisites.sh
```

### 2. Install Istio (if not already installed)
```bash
./install-istio.sh
```

### 3. Deploy Bookinfo with mTLS
```bash
./bookinfo.sh
```

### 4. Test the Deployment
```bash
./utils/bookinfo_test.sh
```

### 5. Verify mTLS Configuration
```bash
./utils/verify_mtls.sh
```

## Detailed Usage

### Installation Scripts

#### install-istio.sh
Installs Istio service mesh on both KubeSlice clusters:
- Downloads and applies Istio manifests
- Configures Istio discovery service (istiod)
- Sets up mTLS policies
- Verifies installation

```bash
./install-istio.sh --help
```

#### bookinfo.sh
Main deployment script that:
- Verifies Istio installation
- Creates bookinfo namespace with sidecar injection enabled
- Deploys services across clusters
- Configures KubeSlice ServiceExports
- Applies mTLS policies
- Sets up Istio Gateway for external access

```bash
# Deploy the application
./bookinfo.sh

# Remove the application
./bookinfo.sh --delete

# Show help
./bookinfo.sh --help
```

### Testing and Verification

#### bookinfo_test.sh
Comprehensive test suite that verifies:
- Basic application functionality
- Istio sidecar injection
- mTLS configuration
- Service-to-service connectivity
- Istio networking components

#### verify_mtls.sh
Specialized mTLS verification script that:
- Checks certificate presence in Envoy proxies
- Verifies PeerAuthentication policies
- Tests encrypted communication between services
- Validates TLS configuration

### Configuration Files

#### Service Configurations
- `productpage.yaml` - Frontend service with Istio sidecar
- `details.yaml` - Book details service with Istio sidecar
- `reviews.yaml` - Book reviews service with Istio sidecar
- `ratings.yaml` - Star ratings service with Istio sidecar

#### Istio Configuration
- `gateway.yaml` - Istio Gateway for external access
- `peer-authentication.yaml` - mTLS enforcement policy
- `istio-base.yaml` - Basic Istio installation manifest
- `istio-discovery.yaml` - Istio control plane configuration

#### KubeSlice Configuration
- `serviceexports.yaml` - Cross-cluster service exports

## Troubleshooting

### Common Issues

1. **Istio not installed**:
   ```bash
   Error: Istio not found on cluster
   ```
   **Solution**: Run `./install-istio.sh` first

2. **Pods stuck in Pending**:
   ```bash
   kubectl describe pod <pod-name> -n bookinfo
   ```
   Check for resource constraints or scheduling issues

3. **mTLS connection failures**:
   ```bash
   ./utils/verify_mtls.sh
   ```
   Verify certificates and PeerAuthentication policies

4. **Cross-cluster connectivity issues**:
   ```bash
   kubectl get serviceimport -n bookinfo
   kubectl get serviceexport -n bookinfo
   ```
   Ensure KubeSlice is properly configured

### Debug Commands

```bash
# Check Istio installation
kubectl get pods -n istio-system

# Verify sidecar injection
kubectl get pods -n bookinfo -o jsonpath='{.items[*].spec.containers[*].name}'

# Check mTLS certificates
kubectl exec -n bookinfo <pod-name> -c istio-proxy -- openssl s_client -connect reviews:9080

# View Envoy configuration
kubectl exec -n bookinfo <pod-name> -c istio-proxy -- curl localhost:15000/config_dump

# Check service mesh connectivity
istioctl proxy-config cluster <pod-name> -n bookinfo
```

## Architecture Details

### mTLS Flow
1. Service A initiates connection to Service B
2. Istio Envoy proxy intercepts the connection
3. Mutual certificate exchange occurs
4. Connection is established with encryption
5. All subsequent traffic is encrypted

### Cross-Cluster Communication
1. productpage (Cluster 1) calls reviews.bookinfo.svc.slice.local
2. KubeSlice routes traffic to Cluster 2
3. Istio maintains mTLS encryption across cluster boundaries
4. reviews service responds through encrypted channel

### Security Policies
- **PeerAuthentication**: Enforces STRICT mTLS for all services
- **AuthorizationPolicy**: Controls service-to-service access
- **Certificate Rotation**: Automatic every 24 hours via Istio CA

## Customization

### Adding New Services
1. Create service YAML with `sidecar.istio.io/inject: "true"` annotation
2. Add ServiceExport for cross-cluster access
3. Update AuthorizationPolicy if needed

### Modifying mTLS Policy
Edit `peer-authentication.yaml` to change mTLS mode:
- `STRICT` - Always require mTLS
- `PERMISSIVE` - Allow both mTLS and plain text
- `DISABLE` - Disable mTLS

### External Access
The Istio Gateway exposes the productpage service externally. To access:
1. Find the gateway external IP
2. Access http://<gateway-ip>/productpage

## Performance Considerations

- **Latency**: mTLS adds ~1-2ms latency per hop
- **CPU**: Envoy proxies consume additional CPU (~10-50m per service)
- **Memory**: Each sidecar uses ~50-100MB RAM
- **Network**: Certificate exchange adds startup time (~2-5 seconds)

## Security Best Practices

1. **Certificate Management**: Use short-lived certificates (default 24h)
2. **Network Policies**: Implement Kubernetes NetworkPolicies alongside Istio
3. **RBAC**: Configure proper service account permissions
4. **Monitoring**: Enable Istio telemetry for security monitoring
5. **Updates**: Keep Istio updated for security patches

## Monitoring and Observability

This example can be extended with:
- **Kiali** - Service mesh visualization
- **Jaeger** - Distributed tracing
- **Prometheus** - Metrics collection
- **Grafana** - Metrics visualization

## Contributing

To contribute improvements:
1. Test changes thoroughly
2. Update documentation
3. Verify mTLS functionality
4. Submit pull request with examples

## Related Examples

- [bookinfo](../bookinfo/) - Basic version without Istio
- [boutique](../boutique/) - Another microservices example