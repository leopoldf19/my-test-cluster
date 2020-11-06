#!/bin/bash

# clean up
kubectl delete -f src/test-pod.yaml -n user1
kubectl delete -f src/test-service.yaml -n user1

kubectl delete -f src/test-pod.yaml -n user2
kubectl delete -f src/test-service.yaml -n user2

# pods and services for testing
kubectl config use-context user1
kubectl apply -f src/test-pod.yaml -n user1
kubectl apply -f src/test-service.yaml -n user1

kubectl config use-context user2
kubectl apply -f src/test-pod.yaml -n user2
kubectl apply -f src/test-service.yaml -n user2

kubectl config use-context kind-kind