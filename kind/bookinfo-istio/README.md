# Bookinfo with Istio and mTLS on KubeSlice

This example deploys the Istio Bookinfo application across two KubeSlice-connected clusters with Istio service mesh and mTLS enabled.

## Architecture

- **Cluster 1 (Product Cluster)**: Runs the productpage service
- **Cluster 2 (Services Cluster)**: Runs details, ratings, and reviews services
- **Service Mesh**: Istio with automatic sidecar injection
- **Security**: mTLS enabled between all services
- **Cross-cluster connectivity**: KubeSlice ServiceExport/ServiceImport

## Prerequisites

- Two kind clusters connected via KubeSlice
- Istio installed on both clusters
- kubectl and kubectx available

## Usage

```bash
# Deploy bookinfo with Istio and mTLS
./bookinfo.sh

# Uninstall
./bookinfo.sh --delete

# Test the deployment
./utils/bookinfo_test.sh
```

## Services

- **productpage**: Frontend service (cluster 1)
- **details**: Book details service (cluster 2)
- **reviews**: Book reviews service with ratings (cluster 2)
- **ratings**: Star ratings service (cluster 2)

All services communicate via mTLS-secured connections through the Istio service mesh.