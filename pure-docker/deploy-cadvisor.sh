#!/usr/bin/env bash
set -e
source ./replicas.sh

# Description: Publishes Prometheus metrics about Docker containers.
#
# Disk: none
# Network: 100mbps
# Liveness probe: none
# Ports exposed to other Sourcegraph services: 8080/TCP
# Ports exposed to the public internet: none
#
# Also add the following volume mount for container monitoring on MacOS:
#   --volume='/var/run/docker.sock:/var/run/docker.sock:ro'
#
# You may remove the --privileged flag to run with reduced privileges.
# `cadvisor` requires root privileges in order to display provisioning metrics.
# These metrics provide critical information to help you scale the Sourcegraph deployment.
# If you would like to bring your own infrastructure monitoring & alerting solution,
# you may want to remove the `cadvisor` container completely
sudo docker run --detach \
    --name=cadvisor \
    --network=sourcegraph \
    --restart=always \
    --cpus=1 \
    --memory=1g \
    --volume=/:/rootfs:ro \
    --volume=/var/run:/var/run:ro \
    --volume=/sys:/sys:ro \
    --volume=/var/lib/docker/:/var/lib/docker:ro \
    --volume=/dev/disk/:/dev/disk:ro \
    --privileged \
    --device=/dev/kmsg \
    index.docker.io/sourcegraph/cadvisor:3.42.2@sha256:56db7fe6777df020d03957b92a15f47ba23a7ab85ba5b3ff65dc5a8276d3b260 \
    --port=8080

echo "Deployed cadvisor"
