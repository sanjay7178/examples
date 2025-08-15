#!/bin/bash

# Test script for CockroachDB Todo Application
# This script validates the multi-cluster deployment

BASE_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
ENV_FILE=${BASE_DIR}/../kind.env

if [[ ! -f $ENV_FILE ]]; then
  echo "${ENV_FILE} file not found! Exiting"
  exit 1
fi

source $ENV_FILE

DB_CLUSTER="${PREFIX}${CONTROLLER}"
API_CLUSTER="${PREFIX}${WORKERS[0]}"
FRONTEND_CLUSTER="${PREFIX}${WORKERS[1]}"
TODO_NAMESPACE=todo-app

echo "🧪 Testing CockroachDB Todo Application"
echo "======================================"

# Test 1: Check if all clusters are accessible
echo "Test 1: Checking cluster connectivity..."
for cluster in $DB_CLUSTER $API_CLUSTER $FRONTEND_CLUSTER; do
    kubectx $cluster > /dev/null
    if [ $? -eq 0 ]; then
        echo "✅ $cluster is accessible"
    else
        echo "❌ $cluster is not accessible"
        exit 1
    fi
done

# Test 2: Check namespace exists in all clusters
echo -e "\nTest 2: Checking namespace existence..."
for cluster in $DB_CLUSTER $API_CLUSTER $FRONTEND_CLUSTER; do
    kubectx $cluster > /dev/null
    if kubectl get namespace $TODO_NAMESPACE > /dev/null 2>&1; then
        echo "✅ Namespace $TODO_NAMESPACE exists in $cluster"
    else
        echo "❌ Namespace $TODO_NAMESPACE not found in $cluster"
    fi
done

# Test 3: Check CockroachDB pods
echo -e "\nTest 3: Checking CockroachDB deployments..."
kubectx $DB_CLUSTER > /dev/null
if kubectl get pods -n $TODO_NAMESPACE -l app=cockroachdb | grep -q Running; then
    echo "✅ CockroachDB primary is running in $DB_CLUSTER"
else
    echo "❌ CockroachDB primary not running in $DB_CLUSTER"
fi

kubectx $API_CLUSTER > /dev/null
if kubectl get pods -n $TODO_NAMESPACE -l app=cockroachdb | grep -q Running; then
    echo "✅ CockroachDB API node is running in $API_CLUSTER"
else
    echo "❌ CockroachDB API node not running in $API_CLUSTER"
fi

kubectx $FRONTEND_CLUSTER > /dev/null
if kubectl get pods -n $TODO_NAMESPACE -l app=cockroachdb | grep -q Running; then
    echo "✅ CockroachDB frontend node is running in $FRONTEND_CLUSTER"
else
    echo "❌ CockroachDB frontend node not running in $FRONTEND_CLUSTER"
fi

# Test 4: Check services
echo -e "\nTest 4: Checking application services..."
kubectx $DB_CLUSTER > /dev/null
if kubectl get pods -n $TODO_NAMESPACE -l app=user-service | grep -q Running; then
    echo "✅ User service is running in $DB_CLUSTER"
else
    echo "❌ User service not running in $DB_CLUSTER"
fi

kubectx $API_CLUSTER > /dev/null
if kubectl get pods -n $TODO_NAMESPACE -l app=todo-api | grep -q Running; then
    echo "✅ Todo API is running in $API_CLUSTER"
else
    echo "❌ Todo API not running in $API_CLUSTER"
fi

kubectx $FRONTEND_CLUSTER > /dev/null
if kubectl get pods -n $TODO_NAMESPACE -l app=frontend | grep -q Running; then
    echo "✅ Frontend is running in $FRONTEND_CLUSTER"
else
    echo "❌ Frontend not running in $FRONTEND_CLUSTER"
fi

if kubectl get pods -n $TODO_NAMESPACE -l app=load-generator | grep -q Running; then
    echo "✅ Load generator is running in $FRONTEND_CLUSTER"
else
    echo "❌ Load generator not running in $FRONTEND_CLUSTER"
fi

# Test 5: Check service exports
echo -e "\nTest 5: Checking KubeSlice service exports..."
kubectx $DB_CLUSTER > /dev/null
if kubectl get serviceexport -n $TODO_NAMESPACE cockroachdb > /dev/null 2>&1; then
    echo "✅ CockroachDB service export exists in $DB_CLUSTER"
else
    echo "❌ CockroachDB service export not found in $DB_CLUSTER"
fi

if kubectl get serviceexport -n $TODO_NAMESPACE user-service > /dev/null 2>&1; then
    echo "✅ User service export exists in $DB_CLUSTER"
else
    echo "❌ User service export not found in $DB_CLUSTER"
fi

kubectx $API_CLUSTER > /dev/null
if kubectl get serviceexport -n $TODO_NAMESPACE todo-api > /dev/null 2>&1; then
    echo "✅ Todo API service export exists in $API_CLUSTER"
else
    echo "❌ Todo API service export not found in $API_CLUSTER"
fi

# Test 6: Test database connectivity
echo -e "\nTest 6: Testing database connectivity..."
kubectx $DB_CLUSTER > /dev/null
DB_POD=$(kubectl get pods -n $TODO_NAMESPACE -l app=cockroachdb -o jsonpath='{.items[0].metadata.name}')
if [ -n "$DB_POD" ]; then
    if kubectl exec -n $TODO_NAMESPACE $DB_POD -- /cockroach/cockroach sql --insecure --execute="SELECT 1" > /dev/null 2>&1; then
        echo "✅ Database is accepting connections"
    else
        echo "❌ Database is not accepting connections"
    fi
else
    echo "❌ No database pod found"
fi

# Test 7: Test multi-tenant schema
echo -e "\nTest 7: Testing multi-tenant database schema..."
if [ -n "$DB_POD" ]; then
    for tenant in tenant_a tenant_b tenant_c; do
        if kubectl exec -n $TODO_NAMESPACE $DB_POD -- /cockroach/cockroach sql --insecure --execute="USE tododb; SELECT COUNT(*) FROM $tenant.users;" > /dev/null 2>&1; then
            echo "✅ Schema $tenant exists and is accessible"
        else
            echo "❌ Schema $tenant not found or not accessible"
        fi
    done
fi

# Test 8: Test cross-cluster service connectivity
echo -e "\nTest 8: Testing cross-cluster service connectivity..."
kubectx $FRONTEND_CLUSTER > /dev/null
FRONTEND_POD=$(kubectl get pods -n $TODO_NAMESPACE -l app=frontend -o jsonpath='{.items[0].metadata.name}')
if [ -n "$FRONTEND_POD" ]; then
    # Test connection to Todo API in different cluster
    if kubectl exec -n $TODO_NAMESPACE $FRONTEND_POD -c frontend -- wget -q --spider http://todo-api.todo-app.svc.cluster.local 2>/dev/null; then
        echo "✅ Frontend can reach Todo API across clusters"
    else
        echo "❌ Frontend cannot reach Todo API"
    fi
    
    # Test connection to User Service in different cluster  
    if kubectl exec -n $TODO_NAMESPACE $FRONTEND_POD -c frontend -- wget -q --spider http://user-service.todo-app.svc.cluster.local 2>/dev/null; then
        echo "✅ Frontend can reach User Service across clusters"
    else
        echo "❌ Frontend cannot reach User Service"
    fi
fi

# Test 9: Test load generator
echo -e "\nTest 9: Testing load generator..."
kubectx $FRONTEND_CLUSTER > /dev/null
LOAD_POD=$(kubectl get pods -n $TODO_NAMESPACE -l app=load-generator -o jsonpath='{.items[0].metadata.name}')
if [ -n "$LOAD_POD" ]; then
    echo "✅ Load generator pod is running"
    echo "  To see load generator logs: kubectl logs -n $TODO_NAMESPACE $LOAD_POD -c load-generator"
else
    echo "❌ Load generator pod not found"
fi

echo -e "\n🎉 Test Summary"
echo "=================="
echo "The CockroachDB Todo application test is complete."
echo ""
echo "To access the application:"
echo "1. Frontend UI:"
echo "   kubectl port-forward -n $TODO_NAMESPACE svc/frontend 3000:80 --context=$FRONTEND_CLUSTER"
echo "   Then visit: http://localhost:3000"
echo ""
echo "2. CockroachDB Admin UI:"
echo "   kubectl port-forward -n $TODO_NAMESPACE svc/cockroachdb 8080:8080 --context=$DB_CLUSTER"
echo "   Then visit: http://localhost:8080"
echo ""
echo "3. Todo API:"
echo "   kubectl port-forward -n $TODO_NAMESPACE svc/todo-api 8090:80 --context=$API_CLUSTER"
echo "   Test with: curl -H 'X-Tenant-ID: tenant-a' http://localhost:8090/api/todos"
echo ""
echo "4. Load Generator Metrics:"
echo "   kubectl port-forward -n $TODO_NAMESPACE svc/load-generator 8095:8080 --context=$FRONTEND_CLUSTER"
echo "   Then visit: http://localhost:8095"