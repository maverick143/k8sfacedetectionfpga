#!/bin/bash
# Copies the dashboard access token to clipboard
secret_name=$(kubectl -n kube-system get secrets -o jsonpath='{range.items[*]}{.metadata.name}:{end}' | tr ":" "\n" | grep eks-admin)
kubectl -n kube-system get secret ${secret_name} -o jsonpath='{.data.token}' | base64 --decode | pbcopy