# Distributed CockroachDB Multi-Cluster with KubeSlice

This example demonstrates how to deploy a distributed CockroachDB cluster across multiple Kubernetes clusters using KubeSlice. CockroachDB is a distributed SQL database that provides strong consistency, horizontal scaling, and built-in resilience.

## Architecture Overview

The setup consists of:
- **3 Kubernetes worker clusters** (worker-1, worker-2, worker-3)
- **1 KubeSlice controller cluster**
- **CockroachDB nodes** distributed across the worker clusters
- **KubeSlice networking** connecting all clusters via a secure overlay network

Each worker cluster runs one CockroachDB node, and all nodes form a single distributed database cluster that can handle distributed SQL queries, automatic failover, and horizontal scaling.

## Prerequisites

1. **KubeSlice Controller Setup**: A controller cluster with KubeSlice controller installed
2. **Multiple Kubernetes Clusters**: 3 worker clusters registered with the KubeSlice controller
3. **kubectl**: Configured to access all clusters
4. **kubeslice-cli**: For automated setup (optional)

## Directory Structure

```
distributed-cockroachdb/
├── kubeslice-cli-topology-template/     # KubeSlice infrastructure templates
│   ├── kubeslice-cli-topology-template.yaml
│   └── kubeslice-cli-topology-oss-template.yaml
├── cockroachdb-slice/                   # Slice configuration files
│   ├── cockroachdb-slice.yaml
│   └── cockroachdb-slice-lb.yaml
├── service-export/                      # Service export configurations
│   ├── k8s-cluster-1.yaml
│   ├── k8s-cluster-2.yaml
│   └── k8s-cluster-3.yaml
└── README.md
```

## Setup Instructions

### Step 1: Infrastructure Setup (Optional)

If you need to set up KubeSlice infrastructure from scratch, use the topology templates:

```bash
# For Enterprise version
kubeslice-cli create topology -f kubeslice-cli-topology-template/kubeslice-cli-topology-template.yaml

# For OSS version
kubeslice-cli create topology -f kubeslice-cli-topology-template/kubeslice-cli-topology-oss-template.yaml
```

### Step 2: Create the KubeSlice Project and Slice

1. **Create the project namespace on the controller cluster:**
```bash
kubectl create namespace kubeslice-cockroachdb-project
```

2. **Apply the slice configuration:**
```bash
# For basic setup
kubectl apply -f cockroachdb-slice/cockroachdb-slice.yaml

# For load balancer setup (if you need external access)
kubectl apply -f cockroachdb-slice/cockroachdb-slice-lb.yaml
```

### Step 3: Deploy CockroachDB

Create the `cockroachdb` namespace on all worker clusters:
```bash
# On each worker cluster
kubectl create namespace cockroachdb
```

Deploy CockroachDB using a StatefulSet. Here's an example manifest for each cluster:

**Worker-1 (cockroachdb-0):**
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: cockroachdb
  namespace: cockroachdb
spec:
  serviceName: "cockroachdb"
  replicas: 1
  selector:
    matchLabels:
      app: cockroachdb
  template:
    metadata:
      labels:
        app: cockroachdb
    spec:
      containers:
      - name: cockroachdb
        image: cockroachdb/cockroach:latest
        ports:
        - containerPort: 26257
          name: grpc
        - containerPort: 8080
          name: http
        command:
          - "/cockroach/cockroach"
          - "start"
          - "--insecure"
          - "--advertise-addr=cockroachdb-0.cockroachdb.svc.cluster.local"
          - "--join=cockroachdb-0.cockroachdb.svc.cluster.local:26257,cockroachdb-1.cockroachdb.svc.cluster.local:26257,cockroachdb-2.cockroachdb.svc.cluster.local:26257"
          - "--cache=25%"
          - "--max-sql-memory=25%"
        volumeMounts:
        - name: datadir
          mountPath: /cockroach/cockroach-data
  volumeClaimTemplates:
  - metadata:
      name: datadir
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 10Gi
---
apiVersion: v1
kind: Service
metadata:
  name: cockroachdb
  namespace: cockroachdb
spec:
  ports:
  - port: 26257
    targetPort: 26257
    name: grpc
  - port: 8080
    targetPort: 8080
    name: http
  selector:
    app: cockroachdb
```

**Important**: Update the `--advertise-addr` and node names for each cluster:
- Worker-1: `cockroachdb-0`
- Worker-2: `cockroachdb-1` 
- Worker-3: `cockroachdb-2`

### Step 4: Export Services

Apply the service exports on each cluster to enable cross-cluster communication:

```bash
# On worker-1
kubectl apply -f service-export/k8s-cluster-1.yaml

# On worker-2
kubectl apply -f service-export/k8s-cluster-2.yaml

# On worker-3
kubectl apply -f service-export/k8s-cluster-3.yaml
```

### Step 5: Initialize the CockroachDB Cluster

Once all nodes are running, initialize the cluster from any node:

```bash
# Connect to any CockroachDB pod
kubectl exec -it cockroachdb-0 -n cockroachdb -- /cockroach/cockroach init --insecure
```

## Verification

### Check Cluster Status
```bash
# Check nodes in the cluster
kubectl exec -it cockroachdb-0 -n cockroachdb -- /cockroach/cockroach node status --insecure

# Check cluster health
kubectl exec -it cockroachdb-0 -n cockroachdb -- /cockroach/cockroach node ls --insecure
```

### Test Database Connectivity
```bash
# Connect to SQL interface
kubectl exec -it cockroachdb-0 -n cockroachdb -- /cockroach/cockroach sql --insecure

# Run test queries
CREATE DATABASE test;
USE test;
CREATE TABLE users (id SERIAL PRIMARY KEY, name STRING);
INSERT INTO users (name) VALUES ('Alice'), ('Bob');
SELECT * FROM users;
```

### Verify Cross-Cluster Communication
```bash
# Check service imports on each cluster
kubectl get serviceimport -n cockroachdb

# Test connectivity between nodes
kubectl exec -it cockroachdb-0 -n cockroachdb -- /cockroach/cockroach node status --insecure --host=cockroachdb-1.cockroachdb.svc.cluster.local
```

## Configuration Details

### Slice Configuration
- **Slice Name**: `cockroachdb-slice`
- **Subnet**: `192.168.0.0/16`
- **Gateway Type**: OpenVPN with Local CA
- **QoS**: Bandwidth control with 5120 Kbps ceiling, 2560 Kbps guaranteed

### Service Exports
Each cluster exports its CockroachDB service with:
- **GRPC Port**: 26257 (main CockroachDB port)
- **HTTP Port**: 8080 (admin UI and API)
- **DNS Aliases**: `cockroachdb-{0,1,2}.cockroachdb.svc.cluster.local`

### Security Considerations
This example uses `--insecure` mode for simplicity. For production deployments:
1. Enable TLS/SSL encryption
2. Set up proper authentication
3. Configure network policies
4. Use secrets for certificates and keys

## Troubleshooting

### Common Issues

1. **Nodes cannot discover each other**:
   - Check ServiceExport and ServiceImport status
   - Verify KubeSlice connectivity
   - Ensure DNS names are resolvable

2. **Cluster initialization fails**:
   - Ensure all nodes are running before initialization
   - Check for network connectivity issues
   - Verify join addresses are correct

3. **Performance issues**:
   - Adjust QoS settings in slice configuration
   - Monitor network latency between clusters
   - Check resource allocation for CockroachDB pods

### Monitoring
- Access CockroachDB Admin UI: `kubectl port-forward svc/cockroachdb 8080:8080 -n cockroachdb`
- View logs: `kubectl logs -f cockroachdb-0 -n cockroachdb`
- Check slice status: `kubectl get slice -n kubeslice-system`

## Cleanup

To remove the deployment:

```bash
# Delete CockroachDB resources
kubectl delete namespace cockroachdb  # On each worker cluster

# Delete slice configuration
kubectl delete -f cockroachdb-slice/cockroachdb-slice.yaml

# Delete project (optional)
kubectl delete namespace kubeslice-cockroachdb-project
```

## References

- [CockroachDB Documentation](https://www.cockroachlabs.com/docs/)
- [KubeSlice Documentation](https://docs.kubeslice.io/)
- [KubeSlice GitHub](https://github.com/kubeslice)
- [CockroachDB Kubernetes Operator](https://github.com/cockroachdb/cockroach-operator)