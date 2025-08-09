# Bookinfo with Contour Ingress Gateway

This example demonstrates how to deploy the Istio Bookinfo application using Contour as an ingress gateway instead of Istio Gateway or direct NodePort exposure.

## Architecture

```
Internet -> Contour Envoy (NodePort) -> HTTPProxy -> ProductPage Service (ClusterIP) -> Backend Services (via KubeSlice)
```

## Table of Contents
- [Bookinfo with Contour Ingress Gateway](#bookinfo-with-contour-ingress-gateway)
  - [Architecture](#architecture)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [Architecture](#architecture-1)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
    - [1. Setup Environment Variables](#1-setup-environment-variables)
    - [2. KubeSlice Setup (Controller and Workers)](#2-kubeslice-setup-controller-and-workers)
    - [3. Product Cluster Setup](#3-product-cluster-setup)
    - [4. Services Cluster Setup](#4-services-cluster-setup)
  - [Testing the Application](#testing-the-application)
    - [Option 1: Access via Contour Ingress](#option-1-access-via-contour-ingress)
    - [Option 2: Port-Forward the Product Page](#option-2-port-forward-the-product-page)
  - [Troubleshooting](#troubleshooting)
    - [Verify Cross-Cluster Communication](#verify-cross-cluster-communication)
    - [Verify KubeSlice Components](#verify-kubeslice-components)
  - [Cleanup](#cleanup)

## Overview

The bookinfo application is deployed across two KubeSlice clusters:
- **Product Cluster**: Contains the productpage service and Contour ingress gateway
- **Services Cluster**: Contains details, reviews, and ratings services

## Architecture

```
Internet -> Contour Envoy (NodePort) -> HTTPProxy -> ProductPage Service (ClusterIP) -> Backend Services (via KubeSlice)
```

## Prerequisites

- KubeSlice installed and configured across clusters
- `kubectl` configured with proper contexts
- `kubectx` installed for context switching
- Access to all three clusters (controller + 2 worker clusters)

## Installation

### 1. Setup Environment Variables

```bash
# Define cluster contexts and namespace
export PRODUCT_CLUSTER="kind-ks-w-1"      
export CONTROLLER_CLUSTER="kind-ks-ctrl"  
export SERVICES_CLUSTER="kind-ks-w-2"     
export BOOKINFO_NAMESPACE="bookinfo"       
export SLICE_NAME="bookinfo-slice"         # KubeSlice slice name  
```

### 2. KubeSlice Setup (Controller and Workers)

```bash
# Verify KubeSlice controller and worker agents are installed
kubectx $CONTROLLER_CLUSTER
kubectl get pods -n kubeslice-controller --no-headers

kubectx $PRODUCT_CLUSTER
kubectl get pods -n kubeslice-system --no-headers

kubectx $SERVICES_CLUSTER
kubectl get pods -n kubeslice-system --no-headers

# Apply the slice configuration on the controller
kubectx $CONTROLLER_CLUSTER
kubectl apply -f slice.yaml

# Create and label the application namespace on both worker clusters so workloads join the slice
kubectx $PRODUCT_CLUSTER
kubectl create namespace $BOOKINFO_NAMESPACE || true
kubectl label namespace $BOOKINFO_NAMESPACE kubeslice.io/slice=$SLICE_NAME --overwrite

kubectx $SERVICES_CLUSTER
kubectl create namespace $BOOKINFO_NAMESPACE || true
kubectl label namespace $BOOKINFO_NAMESPACE kubeslice.io/slice=$SLICE_NAME --overwrite

# Wait for slice gateways to be ready on both worker clusters
kubectx $PRODUCT_CLUSTER
kubectl get workerslicegateway -n kubeslice-system
kubectx $SERVICES_CLUSTER
kubectl get workerslicegateway -n kubeslice-system
```

### 3. Product Cluster Setup

```bash
# Switch to product cluster (namespace already created and labeled in Step 2)
kubectx $PRODUCT_CLUSTER

# Install Contour ingress controller and its components
kubectl apply -f https://projectcontour.io/quickstart/contour.yaml
kubectl apply -f contour-install.yaml
kubectl apply -f contour-rbac.yaml

# Verify Contour is ready
kubectl get pods -n projectcontour -o wide

# Deploy productpage component into the slice namespace
kubectl apply -f ${CONFIG_DIR}/productpage.yaml -n $BOOKINFO_NAMESPACE

# Configure HTTP Proxy for ingress routing
kubectl apply -f ${CONFIG_DIR}/bookinfo-httpproxy.yaml -n $BOOKINFO_NAMESPACE

# Verify all pods are running
kubectl get pods -n $BOOKINFO_NAMESPACE
```

### 4. Services Cluster Setup

```bash
# Switch to services cluster (namespace already created and labeled in Step 2)
kubectx $SERVICES_CLUSTER

# Install backend services
kubectl apply -f details.yaml -n $BOOKINFO_NAMESPACE
kubectl apply -f ratings.yaml -n $BOOKINFO_NAMESPACE
kubectl apply -f reviews.yaml -n $BOOKINFO_NAMESPACE

# Create service exports for cross-cluster communication
kubectl apply -f serviceexports.yaml -n $BOOKINFO_NAMESPACE

# Verify service exports were created
kubectl get serviceexport -n $BOOKINFO_NAMESPACE
```

## Testing the Application

### Option 1: Access via Contour Ingress

Get the Contour Envoy endpoint
```bash
kubectx $PRODUCT_CLUSTER
kubectl get -n projectcontour service envoy -o wide

```
Access the application using the Envoy endpoint
Example: http://<ENVOY_EXTERNAL_IP>:<PORT>/productpage

### Option 2: Port-Forward the Product Page

```bash
kubectx $PRODUCT_CLUSTER
kubectl port-forward -n bookinfo svc/productpage 9080:9080
```
Test individual services
```bash
curl http://localhost:9080/details/1
curl http://localhost:9080/reviews/1
curl http://localhost:9080/ratings/1
```
Test main page
```bash
curl http://localhost:9080/productpage
```

Or access in browser: http://localhost:9080/productpage


## Troubleshooting

### Verify Cross-Cluster Communication

Check DNS resolution from productpage pod
```bash
kubectx $PRODUCT_CLUSTER
PRODUCTPAGE_POD=$(kubectl get pods -n bookinfo -l app=productpage -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it -n bookinfo $PRODUCTPAGE_POD -c netshoot -- /bin/bash 

# From inside the pod, test DNS resolution
nslookup details
nslookup reviews
nslookup ratings
```

### Verify KubeSlice Components

Check slice gateway status
```bash
kubectl get slicegw -A
kubectl get workerslicegateway -n kubeslice-system
```
Verify DNS configuration for cross-cluster services
```bash
kubectl get configmap -n kubeslice-system kubeslice-dns -o yaml
```
Verify namespace membership on the slice
```bash
kubectl get ns $BOOKINFO_NAMESPACE --show-labels
```

## Cleanup

```bash
# Clean up services cluster
kubectx $SERVICES_CLUSTER
kubectl delete namespace $BOOKINFO_NAMESPACE

# Clean up product cluster
kubectx $PRODUCT_CLUSTER
kubectl delete namespace $BOOKINFO_NAMESPACE
kubectl delete -f contour-install.yaml
kubectl delete -f contour-rbac.yaml
kubectl delete namespace projectcontour

# Remove slice configuration
kubectx $CONTROLLER_CLUSTER
kubectl delete -f slice.yaml
```