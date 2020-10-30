#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# create new cluster with PSP activated
kind delete cluster
rm -rf "${DIR}/kubeconfig.yaml"
kind create cluster --config "${DIR}/cluster.yaml" --kubeconfig "${DIR}/kubeconfig.yaml"
export KUBECONFIG=${DIR}/kubeconfig.yaml

# pod security policies
kubectl apply -f src/privileged-psp.yaml
kubectl apply -f src/baseline-psp.yaml
kubectl apply -f src/restricted-psp.yaml
kubectl apply -f src/cluster-roles.yaml
kubectl apply -f src/role-bindings.yaml

# install calico for network policies
kubectl apply -f https://docs.projectcalico.org/v3.8/manifests/calico.yaml
kubectl -n kube-system set env daemonset/calico-node FELIX_IGNORELOOSERPF=true

# wait till nodes are ready
ready=$(kubectl get node kind-control-plane -o json | jq -r '.status.conditions[] | select(.type == "Ready") | .status')
while [ "${ready}" != "True" ]; do
    echo "node not yet ready"
    sleep 1
    ready=$(kubectl get node kind-control-plane -o json | jq -r '.status.conditions[] | select(.type == "Ready") | .status')
done

# create namespaces
kubectl create namespace user1
kubectl create namespace user2

# create users
#1
rm -rf user1.crt user1.csr user1.key
openssl genrsa -out user1.key 2048
openssl req -new -key user1.key -out user1.csr -subj "/CN=user1/O=group1"
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: user1
spec:
  groups:
  - system:authenticated
  request: $(cat user1.csr | base64 | tr -d "\n")
  signerName: kubernetes.io/kube-apiserver-client
  usages:
  - client auth
EOF
kubectl certificate approve user1
# wait till certificate is created
certificate=$(kubectl get csr user1 -o json | jq -r '.status.certificate')
while [ "${certificate}" == "null" ]; do 
  echo "certificate not yet ready"
  sleep 1
  certificate=$(kubectl get csr user1 -o json | jq -r '.status.certificate')
done
echo "${certificate}" | base64 -d > user1.crt
kubectl config set-credentials user1 --client-key=user1.key --client-certificate=user1.crt --embed-certs=true
kubectl config set-context user1 --cluster=kind-kind --user=user1
#2
rm -rf user2.crt user2.csr user2.key
openssl genrsa -out user2.key 2048
openssl req -new -key user2.key -out user2.csr -subj "/CN=user2/O=group1"
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: user2
spec:
  groups:
  - system:authenticated
  request: $(cat user2.csr | base64 | tr -d "\n")
  signerName: kubernetes.io/kube-apiserver-client
  usages:
  - client auth
EOF
kubectl certificate approve user2
# wait till certificate is created
certificate=$(kubectl get csr user2 -o json | jq -r '.status.certificate')
while [ "${certificate}" == "null" ]; do 
  echo "certificate not yet ready"
  sleep 1
  certificate=$(kubectl get csr user2 -o json | jq -r '.status.certificate')
done
echo "${certificate}" | base64 -d  > user2.crt
kubectl config set-credentials user2 --client-key=user2.key --client-certificate=user2.crt --embed-certs=true
kubectl config set-context user2 --cluster=kind-kind --user=user2

# apply network policies
kubectl apply -f src/network-policy-1.yaml
kubectl apply -f src/network-policy-2.yaml

# apply cluster role
kubectl apply -f src/rbac-cr.yaml

# apply role bindings
kubectl create rolebinding -n user1 read-pods-1 --clusterrole=pod-reader --user=user1
kubectl create rolebinding -n user2 read-pods-2 --clusterrole=pod-reader --user=user2

# create deployments and expose them
kubectl apply -f src/deploy-nginx-1.yaml
kubectl apply -f src/deploy-nginx-2.yaml
kubectl expose deployment nginx-deployment-1 -n user1 --type=NodePort --name=nginx-service-1 --port=80
kubectl expose deployment nginx-deployment-2 -n user2 --type=NodePort --name=nginx-service-2 --port=80

# just for testing
kubectl config use-context user1
kubectl get pods -n user1
kubectl config use-context user2
kubectl get pods -n user2
kubectl config use-context kind-kind
kubectl get pods