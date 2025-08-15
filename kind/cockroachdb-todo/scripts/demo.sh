#!/bin/bash

# Demo script for CockroachDB Todo Application
# This script demonstrates the multi-tenant, multi-cluster capabilities

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

echo "🚀 CockroachDB Multi-Cluster Todo Application Demo"
echo "=================================================="
echo ""

# Function to run a command and show output
demo_command() {
    echo "$ $1"
    eval "$1"
    echo ""
}

# Function to show cluster info
show_cluster_info() {
    echo "📊 Cluster Information"
    echo "====================="
    echo "Database Cluster (Controller): $DB_CLUSTER"
    echo "API Services Cluster (Worker-1): $API_CLUSTER"  
    echo "Frontend Cluster (Worker-2): $FRONTEND_CLUSTER"
    echo ""
}

# Function to show pod distribution
show_pod_distribution() {
    echo "🗂️ Pod Distribution Across Clusters"
    echo "===================================="
    
    echo "Database Cluster ($DB_CLUSTER):"
    kubectx $DB_CLUSTER > /dev/null
    demo_command "kubectl get pods -n $TODO_NAMESPACE -o wide"
    
    echo "API Services Cluster ($API_CLUSTER):"
    kubectx $API_CLUSTER > /dev/null
    demo_command "kubectl get pods -n $TODO_NAMESPACE -o wide"
    
    echo "Frontend Cluster ($FRONTEND_CLUSTER):"
    kubectx $FRONTEND_CLUSTER > /dev/null
    demo_command "kubectl get pods -n $TODO_NAMESPACE -o wide"
}

# Function to show service exports
show_service_exports() {
    echo "🌐 KubeSlice Service Exports"
    echo "============================"
    
    for cluster in $DB_CLUSTER $API_CLUSTER $FRONTEND_CLUSTER; do
        echo "Service exports in $cluster:"
        kubectx $cluster > /dev/null
        demo_command "kubectl get serviceexport -n $TODO_NAMESPACE"
    done
}

# Function to demonstrate database queries
show_database_demo() {
    echo "🗄️ Multi-Tenant Database Demo"
    echo "=============================="
    
    kubectx $DB_CLUSTER > /dev/null
    DB_POD=$(kubectl get pods -n $TODO_NAMESPACE -l app=cockroachdb -o jsonpath='{.items[0].metadata.name}')
    
    if [ -n "$DB_POD" ]; then
        echo "Showing tenant schemas:"
        demo_command "kubectl exec -n $TODO_NAMESPACE $DB_POD -- /cockroach/cockroach sql --insecure --execute='USE tododb; SHOW SCHEMAS;'"
        
        echo "Tenant A (Free Tier) - Users and Todos:"
        demo_command "kubectl exec -n $TODO_NAMESPACE $DB_POD -- /cockroach/cockroach sql --insecure --execute='USE tododb; SELECT COUNT(*) as user_count FROM tenant_a.users; SELECT COUNT(*) as todo_count FROM tenant_a.todos;'"
        
        echo "Tenant B (Premium Tier) - Users and Todos with Premium Features:"
        demo_command "kubectl exec -n $TODO_NAMESPACE $DB_POD -- /cockroach/cockroach sql --insecure --execute='USE tododb; SELECT COUNT(*) as user_count FROM tenant_b.users; SELECT title, tags, category FROM tenant_b.todos LIMIT 2;'"
        
        echo "Tenant C (Enterprise Tier) - Advanced Features:"
        demo_command "kubectl exec -n $TODO_NAMESPACE $DB_POD -- /cockroach/cockroach sql --insecure --execute='USE tododb; SELECT title, custom_fields, workflow_state, estimated_hours FROM tenant_c.todos LIMIT 2;'"
        
        echo "Global Statistics View:"
        demo_command "kubectl exec -n $TODO_NAMESPACE $DB_POD -- /cockroach/cockroach sql --insecure --execute='USE tododb; SELECT * FROM global_stats;'"
    else
        echo "❌ Database pod not found"
    fi
}

# Function to test cross-cluster connectivity
test_connectivity() {
    echo "🔗 Cross-Cluster Connectivity Test"
    echo "=================================="
    
    kubectx $FRONTEND_CLUSTER > /dev/null
    FRONTEND_POD=$(kubectl get pods -n $TODO_NAMESPACE -l app=frontend -o jsonpath='{.items[0].metadata.name}')
    
    if [ -n "$FRONTEND_POD" ]; then
        echo "Testing Frontend → Todo API connectivity:"
        demo_command "kubectl exec -n $TODO_NAMESPACE $FRONTEND_POD -c frontend -- wget -qO- http://todo-api.todo-app.svc.cluster.local/api/ | head -1"
        
        echo "Testing Frontend → User Service connectivity:"
        demo_command "kubectl exec -n $TODO_NAMESPACE $FRONTEND_POD -c frontend -- wget -qO- http://user-service.todo-app.svc.cluster.local/api/ | head -1"
    else
        echo "❌ Frontend pod not found"
    fi
}

# Function to show multi-tenant API calls
demo_api_calls() {
    echo "🏢 Multi-Tenant API Demo"
    echo "========================"
    
    kubectx $API_CLUSTER > /dev/null
    API_POD=$(kubectl get pods -n $TODO_NAMESPACE -l app=todo-api -o jsonpath='{.items[0].metadata.name}')
    
    if [ -n "$API_POD" ]; then
        echo "Testing Tenant A API calls:"
        demo_command "kubectl exec -n $TODO_NAMESPACE $API_POD -c todo-api -- wget -qO- --header='X-Tenant-ID: tenant-a' http://localhost:8080/api/todos"
        
        echo "Testing Tenant B API calls:"
        demo_command "kubectl exec -n $TODO_NAMESPACE $API_POD -c todo-api -- wget -qO- --header='X-Tenant-ID: tenant-b' http://localhost:8080/api/stats"
        
        echo "Testing Tenant C API calls:"
        demo_command "kubectl exec -n $TODO_NAMESPACE $API_POD -c todo-api -- wget -qO- --header='X-Tenant-ID: tenant-c' http://localhost:8080/api/stats"
    else
        echo "❌ Todo API pod not found"
    fi
}

# Function to show load generator activity
show_load_generator() {
    echo "⚡ Load Generator Activity"
    echo "========================="
    
    kubectx $FRONTEND_CLUSTER > /dev/null
    LOAD_POD=$(kubectl get pods -n $TODO_NAMESPACE -l app=load-generator -o jsonpath='{.items[0].metadata.name}')
    
    if [ -n "$LOAD_POD" ]; then
        echo "Recent load generator activity (last 20 lines):"
        demo_command "kubectl logs -n $TODO_NAMESPACE $LOAD_POD -c load-generator --tail=20"
    else
        echo "❌ Load generator pod not found"
    fi
}

# Function to show access instructions
show_access_instructions() {
    echo "🌟 Access Instructions"
    echo "======================"
    echo ""
    echo "1. 🖥️  Frontend Web UI:"
    echo "   kubectl port-forward -n $TODO_NAMESPACE svc/frontend 3000:80 --context=$FRONTEND_CLUSTER"
    echo "   Then visit: http://localhost:3000"
    echo ""
    echo "2. 🗄️  CockroachDB Admin UI:"
    echo "   kubectl port-forward -n $TODO_NAMESPACE svc/cockroachdb 8080:8080 --context=$DB_CLUSTER" 
    echo "   Then visit: http://localhost:8080"
    echo ""
    echo "3. 🚀 Todo API Direct Access:"
    echo "   kubectl port-forward -n $TODO_NAMESPACE svc/todo-api 8090:80 --context=$API_CLUSTER"
    echo "   Test with: curl -H 'X-Tenant-ID: tenant-a' http://localhost:8090/api/todos"
    echo ""
    echo "4. 📊 Load Generator Metrics:"
    echo "   kubectl port-forward -n $TODO_NAMESPACE svc/load-generator 8095:8080 --context=$FRONTEND_CLUSTER"
    echo "   Then visit: http://localhost:8095"
    echo ""
    echo "5. 👥 User Service API:"
    echo "   kubectl port-forward -n $TODO_NAMESPACE svc/user-service 8085:80 --context=$DB_CLUSTER"
    echo "   Then visit: http://localhost:8085"
}

# Main demo flow
echo "This demo will show the multi-cluster, multi-tenant capabilities"
echo "of the CockroachDB Todo application running on KubeSlice."
echo ""
read -p "Press Enter to start the demo..."

show_cluster_info
read -p "Press Enter to continue..."

show_pod_distribution
read -p "Press Enter to continue..."

show_service_exports
read -p "Press Enter to continue..."

show_database_demo
read -p "Press Enter to continue..."

test_connectivity
read -p "Press Enter to continue..."

demo_api_calls
read -p "Press Enter to continue..."

show_load_generator
read -p "Press Enter to continue..."

show_access_instructions

echo ""
echo "🎉 Demo Complete!"
echo "================="
echo ""
echo "This demonstration showed:"
echo "✅ Distributed CockroachDB across 3 Kubernetes clusters"
echo "✅ Multi-tenant application with schema isolation"
echo "✅ Cross-cluster microservices communication via KubeSlice"
echo "✅ Different service tiers (Free, Premium, Enterprise)"
echo "✅ Real-time load generation and monitoring"
echo "✅ High availability through database distribution"
echo ""
echo "To cleanup: bash cockroachdb-todo.sh --delete"