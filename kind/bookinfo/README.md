# Bookinfo with Contour Ingress Gateway

This example demonstrates how to deploy the Istio Bookinfo application using Contour as an ingress gateway instead of Istio Gateway or direct NodePort exposure.

## Overview

The bookinfo application is deployed across two KubeSlice clusters:
- **Product Cluster**: Contains the productpage service and Contour ingress gateway
- **Services Cluster**: Contains details, reviews, and ratings services

## Architecture

```
Internet -> Contour Envoy (NodePort) -> HTTPProxy -> ProductPage Service (ClusterIP) -> Backend Services (via KubeSlice)
```

## Components

### Contour Setup
- **Contour Controller**: Manages ingress configuration and serves xDS API to Envoy
- **Envoy Proxy**: Data plane that handles incoming traffic
- **HTTPProxy**: Custom resource that defines routing rules for the bookinfo application

### Bookinfo Services
- **ProductPage**: Frontend service exposed through Contour ingress
- **Details, Reviews, Ratings**: Backend services connected via KubeSlice

## Configuration Files

- `contour-rbac.yaml`: RBAC permissions and certificate generation for Contour
- `contour-install.yaml`: Contour controller and Envoy DaemonSet deployment
- `bookinfo-httpproxy.yaml`: HTTPProxy configuration for productpage routing
- `productpage.yaml`: Updated to use ClusterIP instead of NodePort

## Usage

### Deploy Bookinfo with Contour

```bash
cd examples/kind/bookinfo
bash bookinfo.sh
```

### Access the Application

The application will be accessible through the Contour ingress gateway:

1. **Local Development (WSL/Docker Desktop)**:
   ```bash
   # The script will automatically set up port forwarding
   # Access via: http://localhost:<port>/productpage
   # Add to /etc/hosts: 127.0.0.1 bookinfo.local
   ```

2. **Direct Node Access**:
   ```bash
   # Find the Envoy service NodePort
   kubectl get svc envoy -n projectcontour
   
   # Access via node IP and port with Host header
   curl -H "Host: bookinfo.local" http://<node-ip>:<nodeport>/productpage
   ```

### Test the Application

```bash
bash utils/bookinfo_test.sh
```

### Clean Up

```bash
bash bookinfo.sh --delete
```

## Differences from NodePort Approach

1. **Service Type**: ProductPage service uses ClusterIP instead of NodePort
2. **Routing**: Traffic is routed through Contour HTTPProxy instead of direct service access
3. **Virtual Hosting**: Uses `bookinfo.local` as the virtual host for proper routing
4. **Load Balancing**: Contour provides additional load balancing and traffic management features

## Benefits of Using Contour

1. **Production Ready**: More suitable for production deployments than NodePort
2. **Traffic Management**: Advanced routing, retries, and circuit breaking capabilities
3. **TLS Termination**: Built-in support for SSL/TLS certificate management
4. **Observability**: Integrated metrics and logging capabilities
5. **Kubernetes Native**: Uses standard Kubernetes Ingress resources and custom HTTPProxy CRDs

## Troubleshooting

1. **Check Contour Status**:
   ```bash
   kubectl get pods -n projectcontour
   kubectl logs -n projectcontour deployment/contour
   ```

2. **Verify HTTPProxy**:
   ```bash
   kubectl get httpproxy -n bookinfo
   kubectl describe httpproxy bookinfo-productpage -n bookinfo
   ```

3. **Check Envoy Configuration**:
   ```bash
   kubectl port-forward -n projectcontour daemonset/envoy 9001:9001
   # Access admin interface at http://localhost:9001
   ```