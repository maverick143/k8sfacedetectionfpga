#!/bin/bash
# Build all local Docker images
set -e

pushd camserver
docker build -t 898843949075.dkr.ecr.us-east-1.amazonaws.com/camserver .
popd

pushd wsserver
docker build -t 898843949075.dkr.ecr.us-east-1.amazonaws.com/wsserver .
popd

pushd campublisher
docker build -t 898843949075.dkr.ecr.us-east-1.amazonaws.com/campublisher .
popd

pushd compose
docker build -t 898843949075.dkr.ecr.us-east-1.amazonaws.com/compose .
popd
