# Bookinfo with Istio and mTLS on KubeSlice - Deployment Guide

This example deploys the Istio Bookinfo application across two KubeSlice-connected clusters with Istio service mesh and mTLS enabled for secure service-to-service communication.

## Prerequisites

- Two Kubernetes clusters connected via KubeSlice
- `kubectl` installed and configured to access both clusters
- `kubectx` for easier cluster switching (optional)
- `istioctl` for Istio installation and management
- Sufficient permissions to deploy resources in both clusters

## Deployment Steps

### 1. Create KubeSlice Configuration

First, we need to create a slice configuration on the KubeSlice controller:

```bash
# Switch to controller context
kubectx gke_graphic-transit-458312-f7_us-central1_ks-controller

# Apply slice configuration
kubectl apply -f '/home/sanjay7178/examples2/kind/bookinfo-istio/config_files/slice-config.yaml'
```

Expected output:
```
sliceconfig.controller.kubeslice.io/bookinfo-slice created
```

### 2. Install Istio on Both Clusters

Installing Istio using istioctl provides a simpler, more direct approach with built-in profiles.

```bash
# Install Istio on Worker Cluster 1 (Product Cluster)
istioctl install --set profile=demo --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-1 -y

# Install Istio on Worker Cluster 2 (Services Cluster)
istioctl install --set profile=demo --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-2 -y
```

Expected output for each command:
```
        |\          
        | \         
        |  \        
        |   \       
      /||    \      
     / ||     \     
    /  ||      \    
   /   ||       \   
  /    ||        \  
 /     ||         \ 
/______||__________\
____________________
  \__       _____/  
     \_____/        

✔ Istio core installed ⛵️
✔ Istiod installed 🧠
✔ CNI installed 🪢
✔ Egress gateways installed 🛫
✔ Ingress gateways installed 🛬
✔ Installation complete
```

> **Note**: If you see warnings about version downgrades or revision changes, these are generally safe to proceed with for a fresh installation.

#### 2.1 Verify Istio Installation

```bash
# Check Istio services
kubectl get svc -n istio-system
```

Expected output:
```
NAME                   TYPE           CLUSTER-IP       EXTERNAL-IP     PORT(S)                                      AGE
istio-egressgateway    ClusterIP      10.96.x.x        <none>          80/TCP,443/TCP                               1m
istio-ingressgateway   LoadBalancer   10.96.x.x        34.23.96.143    15021:31xxx/TCP,80:31xxx/TCP,443:31xxx/TCP   1m
istiod                 ClusterIP      10.96.x.x        <none>          15010/TCP,15012/TCP,443/TCP,15014/TCP        1m
```

Get the external IP of the ingress gateway:

```bash
kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

Expected output:
```
34.23.96.143
```

### 3. Prepare Application Namespace

Perform these steps on both worker clusters:

```bash
# Create bookinfo namespace
kubectl create namespace bookinfo

# Enable Istio injection
kubectl label namespace bookinfo istio-injection=enabled
```

Expected output:
```
namespace/bookinfo created
namespace/bookinfo labeled
```

> **Note**: If the namespace already exists, you'll see: "Error from server (AlreadyExists): namespaces "bookinfo" already exists"

### 4. Deploy Bookinfo Application

#### 4.1 Deploy Frontend on Worker Cluster 1

```bash
# Deploy productpage service
kubectl --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-1 apply -f config_files/productpage.yaml -n bookinfo

# Deploy Istio gateway for external access
kubectl --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-1 apply -f config_files/gateway.yaml -n bookinfo
```

Expected output:
```
service/productpage created
serviceaccount/bookinfo-productpage created
deployment.apps/productpage-v1 created
gateway.networking.istio.io/bookinfo-gateway created
virtualservice.networking.istio.io/bookinfo created
```

#### 4.2 Deploy Backend Services on Worker Cluster 2

```bash
# Deploy details service
kubectl --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-2 apply -f config_files/details.yaml -n bookinfo

# Deploy reviews service
kubectl --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-2 apply -f config_files/reviews.yaml -n bookinfo

# Deploy ratings service
kubectl --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-2 apply -f config_files/ratings.yaml -n bookinfo
```

Expected output:
```
service/details created
serviceaccount/bookinfo-details created
deployment.apps/details-v1 created
service/reviews created
serviceaccount/bookinfo-reviews created
deployment.apps/reviews-v3 created
service/ratings created
serviceaccount/bookinfo-ratings created
deployment.apps/ratings-v1 created
```

### 5. Configure KubeSlice ServiceExports

Export services from Worker Cluster 2 to make them accessible in Worker Cluster 1:

```bash
kubectl --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-2 apply -f config_files/serviceexports.yaml -n bookinfo
```

Expected output:
```
serviceexport.networking.kubeslice.io/details created
serviceexport.networking.kubeslice.io/reviews created
serviceexport.networking.kubeslice.io/ratings created
```

Verify ServiceExports on Worker Cluster 2:

```bash
kubectl --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-2 get serviceexports -n bookinfo
```

Initial output (status may be PENDING):
```
NAME      SLICE    INGRESS   SERVICEPORT(S)   PORT(S)    ENDPOINTS   STATUS    ALIAS
details   convoy                              9080/TCP               PENDING   
reviews   convoy                              9080/TCP               PENDING 
```

Wait a few minutes, then check again:

```bash
kubectl --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-2 get serviceexports -n bookinfo
```

Expected output after propagation:
```
NAME      SLICE            INGRESS   SERVICEPORT(S)   PORT(S)    ENDPOINTS   STATUS   ALIAS
details   bookinfo-slice   false                      9080/TCP               READY    
ratings   bookinfo-slice                              9080/TCP               READY    
reviews   bookinfo-slice   false                      9080/TCP               READY  
```

Verify ServiceImports on Worker Cluster 1:

```bash
kubectl --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-1 get serviceimports -n bookinfo
```

Expected output:
```
NAME      SLICE            PORT(S)    ENDPOINTS   STATUS   ALIAS
details   bookinfo-slice   9080/TCP               READY    
ratings   bookinfo-slice   9080/TCP               READY    
reviews   bookinfo-slice   9080/TCP               READY    
```

### 6. Enable mTLS Security

Apply strict mTLS policies to both clusters:

```bash
# Apply strict mTLS policy on Worker Cluster 1
kubectl --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-1 apply -f config_files/peer-authentication.yaml

# Apply strict mTLS policy on Worker Cluster 2
kubectl --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-2 apply -f config_files/peer-authentication.yaml 
```

Expected output for each command:
```
peerauthentication.security.istio.io/default created
authorizationpolicy.security.istio.io/bookinfo-allow created
```

### 7. Configure Authorization Policies

Create authorization policies to allow necessary traffic:

```bash
# Allow access to productpage
kubectl --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-1 apply -f config_files/istio-rbac.yaml

# Allow external traffic to the ingress gateway
kubectl --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-1 apply -f config_files/istio-allow-ingress.yaml
```

Expected output:
```
authorizationpolicy.security.istio.io/allow-productpage created
authorizationpolicy.security.istio.io/allow-ingress-gateway created
```

### 8. Verify Cross-Cluster Connectivity

Check DNS resolution and connectivity from the productpage pod:

```bash
# Get the productpage pod name
PRODUCTPAGE_POD=$(kubectl --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-1 get pods -n bookinfo -l app=productpage -o jsonpath='{.items[0].metadata.name}')

# Exec into the pod to test connectivity
kubectl --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-1 exec -it -n bookinfo $PRODUCTPAGE_POD -c netshoot -- /bin/bash
```

Once inside the pod, run these commands:

```bash
# Test DNS resolution for details service
nslookup details

# Test DNS resolution for reviews service
nslookup reviews

# Test DNS resolution for ratings service
nslookup ratings
```

Expected output:
```
Server:         127.0.0.1
Address:        127.0.0.1#53

Name:   details.bookinfo.svc.cluster.local
Address: 34.118.236.170

Server:         127.0.0.1
Address:        127.0.0.1#53

Name:   reviews.bookinfo.svc.cluster.local
Address: 34.118.231.183

Server:         127.0.0.1
Address:        127.0.0.1#53

Name:   ratings.bookinfo.svc.cluster.local
Address: 34.118.226.89
```

Type `exit` to leave the pod.

### 9. Optional: Ensure Certificate Trust Between Clusters

To ensure mutual trust for mTLS between clusters, copy root certificates:

```bash
# Copy root-cert from Cluster 1 to Cluster 2
kubectl --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-1 get configmap -n istio-system istio-ca-root-cert -o yaml | \
  sed 's/namespace: istio-system/namespace: kubeslice-system/' | \
  kubectl --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-2 apply -f -

# Copy root-cert from Cluster 2 to Cluster 1
kubectl --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-2 get configmap -n istio-system istio-ca-root-cert -o yaml | \
  sed 's/namespace: istio-system/namespace: kubeslice-system/' | \
  kubectl --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-1 apply -f -
```

### 10. Verify mTLS Configuration

Check PeerAuthentication policies on both clusters to confirm mTLS is enabled:

```bash
# Check Worker Cluster 1
kubectl --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-1 get peerauthentication -n bookinfo -o yaml

# Check Worker Cluster 2
kubectl --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-2 get peerauthentication -n bookinfo -o yaml
```

Expected output should show `mode: STRICT` in the spec section:
```yaml
apiVersion: v1
items:
- apiVersion: security.istio.io/v1
  kind: PeerAuthentication
  metadata:
    annotations:
      kubectl.kubernetes.io/last-applied-configuration: |
        {"apiVersion":"security.istio.io/v1beta1","kind":"PeerAuthentication","metadata":{"annotations":{},"name":"default","namespace":"bookinfo"},"spec":{"mtls":{"mode":"STRICT"}}}
    creationTimestamp: "2025-08-10T15:48:31Z"
    generation: 1
    name: default
    namespace: bookinfo
    resourceVersion: "1754840911946783017"
    uid: 9cf690b8-e895-455b-8d76-c875fdd9fa5e
  spec:
    mtls:
      mode: STRICT
kind: List
metadata:
  resourceVersion: ""
```

### 11. Access the Application

Access the Bookinfo application using the Istio Ingress Gateway's external IP:

```bash
# Get the Ingress Gateway IP
GATEWAY_IP=$(kubectl --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-1 get svc istio-ingress -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "Access the Bookinfo application at: http://$GATEWAY_IP/productpage"
```

## Troubleshooting

### 1. ServiceImports Stuck in PENDING State

If ServiceImports are stuck in PENDING state:

```bash
# Check status
kubectl --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-1 get serviceimports -n bookinfo
kubectl --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-2 get serviceexports -n bookinfo

# Delete and recreate the ServiceExport
kubectl --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-2 delete serviceexport <service-name> -n bookinfo
kubectl --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-2 apply -f config_files/serviceexports.yaml -n bookinfo
```

### 2. Istio CRDs Not Installed

If you encounter errors about missing Istio CRDs, reinstall Istio:

```bash
# Install Istio using istioctl
istioctl install --set profile=demo --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-1 -y
istioctl install --set profile=demo --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-2 -y
```

### 3. Blank Productpage

If the productpage shows a blank page or cannot be reached:

```bash
# Check if the Istio Gateway is properly configured
kubectl --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-1 get gateway -n bookinfo
kubectl --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-1 get virtualservice -n bookinfo

# Ensure authorization policies allow external traffic
kubectl --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-1 apply -f config_files/istio-allow-ingress.yaml
```

## Conclusion

You have successfully deployed the Bookinfo application across two KubeSlice-connected clusters with Istio service mesh and mTLS enabled. The application architecture provides:

1. Secure service-to-service communication with mTLS
2. Cross-cluster service discovery via KubeSlice
3. External access through Istio Gateway

For more details on the architecture and features, refer to the [README.md](./README.md).
  resourceVersion: ""
```

### 11. Access the Application

Access the Bookinfo application using the Istio Ingress Gateway's external IP:

```bash
# Get the Ingress Gateway IP
GATEWAY_IP=$(kubectl --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-1 get svc istio-ingress -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "Access the Bookinfo application at: http://$GATEWAY_IP/productpage"
```

## Troubleshooting

### 1. ServiceImports Stuck in PENDING State

If ServiceImports are stuck in PENDING state:

```bash
# Check status
kubectl --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-1 get serviceimports -n bookinfo
kubectl --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-2 get serviceexports -n bookinfo

# Delete and recreate the ServiceExport
kubectl --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-2 delete serviceexport <service-name> -n bookinfo
kubectl --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-2 apply -f config_files/serviceexports.yaml -n bookinfo
```

### 2. Istio CRDs Not Installed

If you encounter errors about missing Istio CRDs:

```bash
# Install Istio using istioctl
istioctl install --set profile=demo --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-1 -y
istioctl install --set profile=demo --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-2 -y
```

### 3. Blank Productpage

If the productpage shows a blank page or cannot be reached:

```bash
# Check if the Istio Gateway is properly configured
kubectl --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-1 get gateway -n bookinfo
kubectl --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-1 get virtualservice -n bookinfo

# Ensure authorization policies allow external traffic
kubectl --context=gke_graphic-transit-458312-f7_us-east1_ks-worker-1 apply -f config_files/istio-allow-ingress.yaml
```

## Conclusion

You have successfully deployed the Bookinfo application across two KubeSlice-connected clusters with Istio service mesh and mTLS enabled. The application architecture provides:

1. Secure service-to-service communication with mTLS
2. Cross-cluster service discovery via KubeSlice
3. External access through Istio Gateway

For more details on the architecture and features, refer to the [README.md](./README.md).
