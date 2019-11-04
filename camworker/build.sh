#!/bin/bash
# Build the camworker image on an FPGA instance

set -euo pipefail

[[ ${DEBUG:-} ]] && set -x

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# IP of FPGA node to build on
BUILDER=$1
BUILD_DIR=$DIR/build/camworker_builder

cd $DIR

function scp() {
  COMMAND=scp $DIR/../k8s/ssh.sh $@
}

function ssh() {
  $DIR/../k8s/ssh.sh ubuntu@$BUILDER -- $@
}

rm -Rf dist/*
rm -Rf build/*
pipenv run python setup.py bdist_wheel
mkdir -p $BUILD_DIR
cp dist/*.whl $BUILD_DIR
cp -R docker/* $BUILD_DIR

scp -rp $BUILD_DIR "ubuntu@$BUILDER:/tmp/"
ssh "cd /tmp/$(basename $BUILD_DIR) && docker build -t 898843949075.dkr.ecr.us-east-1.amazonaws.com/camworker ."

docker_login=$(aws ecr get-login --no-include-email)
ssh $docker_login
ssh docker push 898843949075.dkr.ecr.us-east-1.amazonaws.com/camworker
