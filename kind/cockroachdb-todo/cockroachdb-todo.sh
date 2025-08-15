#!/usr/bin/env bash

BASE_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
MANIFESTS_DIR=${BASE_DIR}/manifests
ENV_FILE=${BASE_DIR}/../kind.env

if [[ ! -f $ENV_FILE ]]; then
  echo "${ENV_FILE} file not found! Exiting"
  exit 1
fi

source $ENV_FILE

# Cluster assignment for multi-cluster deployment
DB_CLUSTER="${PREFIX}${CONTROLLER}"         # Controller cluster hosts primary DB node
API_CLUSTER="${PREFIX}${WORKERS[0]}"        # Worker 1 hosts API services and DB node
FRONTEND_CLUSTER="${PREFIX}${WORKERS[1]}"   # Worker 2 hosts frontend and DB node
TODO_NAMESPACE=todo-app

uninstall() {
    echo "Deleting CockroachDB Todo application from all clusters"
    
    # Delete frontend components
    kubectx $FRONTEND_CLUSTER
    kubectl delete -f ${MANIFESTS_DIR}/frontend/ -n $TODO_NAMESPACE --ignore-not-found=true
    kubectl delete -f ${MANIFESTS_DIR}/cockroachdb/cockroachdb-frontend.yaml -n $TODO_NAMESPACE --ignore-not-found=true
    
    # Delete API services
    kubectx $API_CLUSTER
    kubectl delete -f ${MANIFESTS_DIR}/services/ -n $TODO_NAMESPACE --ignore-not-found=true
    kubectl delete -f ${MANIFESTS_DIR}/cockroachdb/cockroachdb-api.yaml -n $TODO_NAMESPACE --ignore-not-found=true
    
    # Delete database primary
    kubectx $DB_CLUSTER
    kubectl delete -f ${MANIFESTS_DIR}/services/user-service.yaml -n $TODO_NAMESPACE --ignore-not-found=true
    kubectl delete -f ${MANIFESTS_DIR}/cockroachdb/cockroachdb-primary.yaml -n $TODO_NAMESPACE --ignore-not-found=true
    
    # Delete slice configuration
    kubectx ${PREFIX}${CONTROLLER}
    kubectl delete -f ${BASE_DIR}/slice-config.yaml -n kubeslice-system --ignore-not-found=true
    
    echo "Wait for todo namespace to be deboarded"
    sleep 30
    
    # Delete namespaces
    for cluster in $DB_CLUSTER $API_CLUSTER $FRONTEND_CLUSTER; do
      echo "Deleting namespace $TODO_NAMESPACE on cluster $cluster"
      kubectx $cluster
      [[ $(kubectl get namespaces | grep $TODO_NAMESPACE) ]] && kubectl delete namespace $TODO_NAMESPACE
    done
}

help() {
    echo "Usage: cockroachdb-todo.sh [--delete]"
    echo ""
    echo "This script deploys a multi-cluster todo application with distributed CockroachDB"
    echo "across KubeSlice clusters."
    echo ""
    echo "Options:"
    echo "  --delete    Remove the todo application"
    echo "  --help      Show this help message"
}

# Get the options
while getopts ":d:delete:help:" option; do
  case $option in
    d | delete) # Uninstall
      uninstall
      exit;;
    h |help)
      help
      exit;;
   esac
done

function wait_for_pods() {
  local cluster=$1
  local namespace=$2
  
  kubectx $cluster
  echo "Waiting for pods in $cluster to be ready..."
  
  for pod in $(kubectl get pods -n $namespace | grep -v NAME | awk '{ print $1 }'); do
    counter=0

    while [[ $(kubectl get pods $pod -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}' -n $namespace) != True ]]; do
      sleep 10
      let counter=counter+10

      if ((counter == 300)); then
        echo "POD $pod failed to start in 300 seconds"
        echo "Exiting"
        exit -1
      fi
    done
  done
  echo "All pods in $cluster are ready"
}

function wait_for_cockroachdb() {
  local cluster=$1
  echo "Waiting for CockroachDB to be ready in $cluster..."
  kubectx $cluster
  
  # Wait for CockroachDB pod to be ready
  kubectl wait --for=condition=ready pod -l app=cockroachdb -n $TODO_NAMESPACE --timeout=300s
  
  # Wait for CockroachDB to accept connections
  local counter=0
  while ! kubectl exec -n $TODO_NAMESPACE $(kubectl get pods -n $TODO_NAMESPACE -l app=cockroachdb -o jsonpath='{.items[0].metadata.name}') -- /cockroach/cockroach sql --insecure --execute="SELECT 1" > /dev/null 2>&1; do
    sleep 10
    let counter=counter+10
    if ((counter == 180)); then
      echo "CockroachDB failed to start accepting connections in 180 seconds"
      exit -1
    fi
  done
  echo "CockroachDB is ready in $cluster"
}

echo "*** Starting CockroachDB Todo Application Deployment ***"

# Create namespaces in all clusters
echo "Creating namespaces in all clusters for todo application"
for cluster in $DB_CLUSTER $API_CLUSTER $FRONTEND_CLUSTER; do
    kubectx $cluster
    kubectl create namespace $TODO_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    sleep 5
done

# Create slice configuration
echo "Creating slice configuration"
kubectx ${PREFIX}${CONTROLLER}
kubectl apply -f ${BASE_DIR}/slice-config.yaml -n kubeslice-system
echo "Waiting for slice to be applied"
sleep 15

# Deploy CockroachDB nodes
echo "Deploying CockroachDB primary node in database cluster"
kubectx $DB_CLUSTER
kubectl apply -f ${MANIFESTS_DIR}/cockroachdb/cockroachdb-primary.yaml -n $TODO_NAMESPACE
wait_for_cockroachdb $DB_CLUSTER

echo "Deploying CockroachDB API node in API cluster"
kubectx $API_CLUSTER
kubectl apply -f ${MANIFESTS_DIR}/cockroachdb/cockroachdb-api.yaml -n $TODO_NAMESPACE
wait_for_cockroachdb $API_CLUSTER

echo "Deploying CockroachDB frontend node in frontend cluster"
kubectx $FRONTEND_CLUSTER
kubectl apply -f ${MANIFESTS_DIR}/cockroachdb/cockroachdb-frontend.yaml -n $TODO_NAMESPACE
wait_for_cockroachdb $FRONTEND_CLUSTER

# Initialize the database cluster
echo "Initializing CockroachDB cluster"
kubectx $DB_CLUSTER
kubectl exec -n $TODO_NAMESPACE $(kubectl get pods -n $TODO_NAMESPACE -l app=cockroachdb -o jsonpath='{.items[0].metadata.name}') -- /cockroach/cockroach init --insecure

# Deploy User Management Service
echo "Deploying User Management Service"
kubectx $DB_CLUSTER
kubectl apply -f ${MANIFESTS_DIR}/services/user-service.yaml -n $TODO_NAMESPACE
wait_for_pods $DB_CLUSTER $TODO_NAMESPACE

# Deploy API Services
echo "Deploying Todo API Services"
kubectx $API_CLUSTER
kubectl apply -f ${MANIFESTS_DIR}/services/ -n $TODO_NAMESPACE
wait_for_pods $API_CLUSTER $TODO_NAMESPACE

# Deploy Frontend Services
echo "Deploying Frontend Services"
kubectx $FRONTEND_CLUSTER
kubectl apply -f ${MANIFESTS_DIR}/frontend/ -n $TODO_NAMESPACE
wait_for_pods $FRONTEND_CLUSTER $TODO_NAMESPACE

# Setup database schema and sample data
echo "Setting up database schema and sample data"
kubectx $DB_CLUSTER
kubectl cp ${BASE_DIR}/scripts/init-db.sql $TODO_NAMESPACE/$(kubectl get pods -n $TODO_NAMESPACE -l app=cockroachdb -o jsonpath='{.items[0].metadata.name}'):/tmp/init-db.sql
kubectl exec -n $TODO_NAMESPACE $(kubectl get pods -n $TODO_NAMESPACE -l app=cockroachdb -o jsonpath='{.items[0].metadata.name}') -- /cockroach/cockroach sql --insecure -f /tmp/init-db.sql

echo ""
echo "*** CockroachDB Todo Application Deployed Successfully! ***"
echo ""
echo "Access the application:"
echo "1. Frontend UI: kubectl port-forward -n $TODO_NAMESPACE svc/frontend 3000:80 --context=$FRONTEND_CLUSTER"
echo "2. CockroachDB Admin UI: kubectl port-forward -n $TODO_NAMESPACE svc/cockroachdb 8080:8080 --context=$DB_CLUSTER"
echo "3. Todo API: kubectl port-forward -n $TODO_NAMESPACE svc/todo-api 8090:80 --context=$API_CLUSTER"
echo ""
echo "Multi-tenant demo:"
echo "- Tenant A (Free): curl -H 'X-Tenant-ID: tenant-a' http://localhost:8090/api/todos"
echo "- Tenant B (Premium): curl -H 'X-Tenant-ID: tenant-b' http://localhost:8090/api/todos"
echo "- Tenant C (Enterprise): curl -H 'X-Tenant-ID: tenant-c' http://localhost:8090/api/todos"
echo ""
echo "To cleanup: bash cockroachdb-todo.sh --delete"