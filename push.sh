#!/bin/bash
# Push all local Docker images to AWS
set -e

docker_login=$(aws ecr get-login --no-include-email)
eval "$docker_login"

docker push 898843949075.dkr.ecr.us-east-1.amazonaws.com/camserver
docker push 898843949075.dkr.ecr.us-east-1.amazonaws.com/wsserver
docker push 898843949075.dkr.ecr.us-east-1.amazonaws.com/compose
docker push 898843949075.dkr.ecr.us-east-1.amazonaws.com/campublisher