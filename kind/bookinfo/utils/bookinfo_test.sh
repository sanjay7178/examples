#!/bin/bash

# Usage:
# demotest <path to project.variables>


# A script to try to test out a "demo" topology
#
# Maybe add...
#   read -p "Press any key to continue... " -n1 -s
# ...to make it a real-time demo

BASE_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
CONFIG_FILE=${BASE_DIR}/../../kind.env

if [[ -f $CONFIG_FILE ]]; then
  source $CONFIG_FILE
else
  echo "File $CONFIG_FILE not found"
  exit 1
fi

kubectx $PRODUCT_CLUSTER
PRODUCT_NODE=$(kubectl get pods -o wide -n bookinfo | tail -1 | awk '{ print $7 }')

echo "#### Collecting bookinfo data"
# Get the Contour Envoy service NodePort
BI_PORT=$(kubectl get services envoy -n projectcontour -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
echo "Contour Envoy HTTP Port: $BI_PORT"

BI_ADDR_STR=$(kubectl get nodes -o wide | egrep "$PRODUCT_NODE" | awk '{ print $6 }')

WSL=$(ps -elf | egrep "wsl\/docker-desktop" | egrep -v grep | awk '{ print $15 }')

echo $WSL
if [[ $WSL != "" ]]
then
    echo "#### Bookinfo Reviews Page WSL"
    echo -e "Started forwarding the port to access the ProductPage UI via Contour"
    echo -e "Please use the CTRL-C command to exit & stop the port forwarding"
    echo -e "Please use the below command to access the Productpage manually"
    echo -e "kubectl port-forward svc/envoy -n projectcontour $BI_PORT:80"
    echo -e "\n\nAccess productpage on browser with the URL  http://localhost:$BI_PORT/productpage"
    echo -e "Make sure to add '127.0.0.1 bookinfo.local' to your /etc/hosts file"

    kubectl port-forward svc/envoy -n projectcontour $BI_PORT:80
    exit
fi

echo "#### Checking BookInfo..."
echo curl -H "Host: bookinfo.local" http://$BI_ADDR_STR":"$BI_PORT/productpage
curl -H "Host: bookinfo.local" http://$BI_ADDR_STR":"$BI_PORT/productpage | egrep 'Comedy of Errors' > /dev/null
if [ $? -eq 0 ]
then
    echo "#### Bookinfo Reviews Page OK"
else
    echo "#### Bookinfo Reviews Page FAIL"
fi
echo curl -H "Host: bookinfo.local" http://$BI_ADDR_STR":"$BI_PORT/productpage
curl -H "Host: bookinfo.local" http://$BI_ADDR_STR":"$BI_PORT/productpage | egrep 'Type'  > /dev/null
if [ $? -eq 0 ]
then
    echo "#### Bookinfo Details Page OK"
else
    echo "#### Bookinfo Details Page FAIL"
fi
if [ $? -eq 0 ]
then
    echo "#### Product Page OK"
else
    echo "#### Product Page FAIL"
fi

echo curl -H "Host: bookinfo.local" http://$BI_ADDR_STR":"$BI_PORT/productpage
curl -H "Host: bookinfo.local" http://$BI_ADDR_STR":"$BI_PORT/productpage | egrep 'slapstick'  > /dev/null
if [ $? -eq 0 ]
then
    echo "#### Bookinfo Reviews Page OK"
else
    echo "#### Bookinfo Reviews Page FAIL"
fi

