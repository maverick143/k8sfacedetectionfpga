#!/bin/bash
# SSH into an instance in the k8s cluster in AWS
# Usage: ./ssh.sh <PRIVATE_IP_OF_INSTANCE>
set -eu -o pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $DIR

[ -n "${DEBUG:-}" ] && set -x
ARG=""
[ -n "${VERBOSE:-}" ] && ARG="-v"

KEY=../xu1.pem
REGION=us-east-1
COMMAND="${COMMAND:-ssh}"

exec ${COMMAND} \
  -o "IdentitiesOnly=yes" \
  -i ${KEY} \
  ${ARG} \
  -o "proxycommand ssh ${ARG} -W %h:%p -i ${KEY} ec2-user@$(cd terraform && terraform output bastion_public_ip)" \
  $@
