# CockroachDB Multi-Cluster Todo Application

This example demonstrates a **multi-cluster, multi-tenant** todo application using **distributed CockroachDB** on KubeSlice clusters. 

## Architecture Overview

This example showcases:
- **Distributed CockroachDB cluster** spanning multiple Kubernetes clusters
- **Multi-tenant architecture** with tenant isolation
- **Cross-cluster microservices communication** via KubeSlice
- **High availability and fault tolerance** through database distribution

### Cluster Distribution

- **Cluster 1 (Database Primary)**: CockroachDB node + User Management Service
- **Cluster 2 (API Services)**: CockroachDB node + Todo API Service + Auth Service  
- **Cluster 3 (Frontend)**: CockroachDB node + Frontend Service + Load Generator

### Application Components

1. **CockroachDB Cluster**: Distributed SQL database with 3 nodes across clusters
2. **User Service**: Manages user authentication and tenant isolation
3. **Todo API**: CRUD operations for todos with tenant-aware routing
4. **Frontend**: Web application for todo management
5. **Load Generator**: Simulates multi-tenant traffic patterns

## Quick Start

### Prerequisites

Ensure you have the basic KubeSlice kind environment set up:

```bash
cd ../
bash kind.sh
```

### Deploy the Todo Application

```bash
cd cockroachdb-todo
bash cockroachdb-todo.sh
```

### Access the Application

The script will provide URLs to access:
- Frontend UI (port-forwarded to localhost:3000)
- CockroachDB Admin UI (port-forwarded to localhost:8080)
- API endpoints for direct testing

### Multi-Tenant Demo

The example includes three demo tenants:
- **Tenant A**: Free tier (basic features)
- **Tenant B**: Premium tier (advanced features) 
- **Tenant C**: Enterprise tier (full features)

Each tenant's data is isolated and can be distributed across different clusters for compliance or performance requirements.

## What This Example Demonstrates

### 1. Distributed Database Architecture
- CockroachDB nodes distributed across 3 Kubernetes clusters
- Automatic data replication and consistency
- Fault tolerance - application continues working even if a cluster goes down

### 2. Multi-Tenancy Patterns
- Tenant isolation at the database schema level
- Tenant-aware routing in microservices
- Different service tiers for different tenant types

### 3. KubeSlice Integration
- Service exports/imports for cross-cluster communication
- Namespace onboarding for proper network connectivity
- Slice configuration for secure inter-cluster networking

### 4. Real-World Scenarios
- Demonstrates how to build production-ready distributed applications
- Shows database scaling patterns across geographic regions
- Illustrates compliance and data sovereignty considerations

## Cleanup

To remove the todo application and preserve KubeSlice setup:

```bash
bash cockroachdb-todo.sh --delete
```

To cleanup everything including KubeSlice:

```bash
cd ../
bash kind.sh --clean
```

## Technical Details

### Database Schema
Each tenant gets their own schema within the CockroachDB cluster:
- `tenant_a.todos`, `tenant_a.users`
- `tenant_b.todos`, `tenant_b.users`  
- `tenant_c.todos`, `tenant_c.users`

### Cross-Cluster Communication
Services communicate across clusters using KubeSlice service exports:
- Frontend → Todo API (via serviceimport)
- Todo API → User Service (via serviceimport)
- All services → CockroachDB (via cluster-local services)

### High Availability
- CockroachDB provides automatic failover between nodes
- Services are deployed with multiple replicas across clusters
- Load balancing ensures traffic distribution

## Customization

You can modify the following files to customize the deployment:
- `configs/tenant-config.yaml`: Tenant definitions and features
- `manifests/cockroachdb/`: Database configuration and resources
- `manifests/services/`: Microservice deployments and configurations
- `scripts/load-generator.sh`: Traffic simulation patterns

This example provides a foundation for building production-scale, multi-cluster applications with distributed databases on KubeSlice.