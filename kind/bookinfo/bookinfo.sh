#!/usr/bin/env bash

BASE_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
CONFIG_DIR=${BASE_DIR}/config_files

ENV_FILE=${BASE_DIR}/../kind.env

if [[ ! -f $ENV_FILE ]]; then
  echo "${ENV_FILE} file not found! Exiting"
  exit 1
fi

source $ENV_FILE

PRODUCT_CLUSTER="${PREFIX}${WORKERS[0]}"
SERVICES_CLUSTER="${PREFIX}${WORKERS[1]}"
BOOKINFO_NAMESPACE=bookinfo

uninstall() {
    for cluster in $SERVICES_CLUSTER $PRODUCT_CLUSTER; do
      echo "Deleting namespace $BOOKINFO_NAMESPACE on cluster $cluster"
      kubectx $cluster
      [[ $(kubectl get namespaces | grep $BOOKINFO_NAMESPACE) ]] && kubectl delete namespace $BOOKINFO_NAMESPACE
    done
    
    echo "Cleaning up Contour on product cluster"
    kubectx $PRODUCT_CLUSTER
    kubectl delete -f ${CONFIG_DIR}/contour-install.yaml --ignore-not-found=true
    kubectl delete -f ${CONFIG_DIR}/contour-rbac.yaml --ignore-not-found=true
    kubectl delete namespace projectcontour --ignore-not-found=true
}

help() {
    echo "Usage: bookinfo.sh [--delete]"
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

kubectx $PRODUCT_CLUSTER

echo "Installing Contour ingress controller"
kubectl apply -f ${CONFIG_DIR}/contour-rbac.yaml
kubectl apply -f ${CONFIG_DIR}/contour-install.yaml

echo "Waiting for Contour to be ready"
kubectl wait --for=condition=available --timeout=120s deployment/contour -n projectcontour
kubectl wait --for=condition=ready --timeout=120s daemonset/envoy -n projectcontour

kubectl create namespace $BOOKINFO_NAMESPACE

function wait_for_pods {
  for pod in $(kubectl get pods -n $BOOKINFO_NAMESPACE | grep -v NAME | awk '{ print $1 }'); do
    counter=0

    while [[ $(kubectl get pods $pod -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}' -n $BOOKINFO_NAMESPACE) != True ]]; do
      sleep 1
      let counter=counter+1

      if ((counter == 120)); then
        echo "POD $pod failed to start in 120 seconds"
        echo "Exiting"

        exit -1
      fi
    done
  done
}

echo "Installing productpage"
kubectl apply -f ${CONFIG_DIR}/productpage.yaml -n $BOOKINFO_NAMESPACE

echo "Waiting for pods to be ready"
wait_for_pods

echo "Installing HTTPProxy for ingress"
kubectl apply -f ${CONFIG_DIR}/bookinfo-httpproxy.yaml -n $BOOKINFO_NAMESPACE

echo "Productpage installed"
kubectl get pods -n $BOOKINFO_NAMESPACE

kubectx $SERVICES_CLUSTER
kubectl create namespace $BOOKINFO_NAMESPACE

kubectl apply -f ${CONFIG_DIR}/details.yaml -n $BOOKINFO_NAMESPACE
kubectl apply -f ${CONFIG_DIR}/ratings.yaml -n $BOOKINFO_NAMESPACE
kubectl apply -f ${CONFIG_DIR}/reviews.yaml -n $BOOKINFO_NAMESPACE

echo "Waiting for pods to be ready"
wait_for_pods

kubectl apply -f ${CONFIG_DIR}/serviceexports.yaml -n $BOOKINFO_NAMESPACE
echo "Waiting for serviceeport to be created"
sleep 30

echo "Verifying serviceexport"
kubectl get serviceexport -n $BOOKINFO_NAMESPACE

echo "Verifying productpage"
kubectx $PRODUCT_CLUSTER
kubectl get serviceimport -n $BOOKINFO_NAMESPACE

echo "Printing services"
kubectl get services -n $BOOKINFO_NAMESPACE

echo "**** Testing bookinfo services"
echo "Waiting for services to be available"
sleep 40

bash ${BASE_DIR}/utils/bookinfo_test.sh
