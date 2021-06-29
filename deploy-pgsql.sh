#!/usr/bin/env bash
set -e

# Description: PostgreSQL database for various data.
#
# Disk: 128GB / persistent SSD
# Network: 100mbps
# Liveness probe: 5432/TCP
# Ports exposed to other Sourcegraph services: 5432/TCP 9187/TCP
# Ports exposed to the public internet: none
#
VOLUME="$HOME/sourcegraph-docker/pgsql-disk"
./ensure-volume.sh $VOLUME 999
# README: Keep postgres-9.6 and the volume mount in customer-replica branch
docker run --detach \
    --name=pgsql \
    --network=sourcegraph \
    --restart=always \
    --cpus=4 \
    --memory=2g \
    -e PGDATA=/var/lib/postgresql/data/pgdata \
    -v $VOLUME:/var/lib/postgresql/data/ \
    index.docker.io/sourcegraph/postgres-12.6:3.29.1@sha256:2d8bbfc7d954beb7d300261dfa9ad54bc6087ac16252b6bc1dd33ffec800ae46

# Sourcegraph requires PostgreSQL 12+. Generally newer versions are better,
# but anything 12 and higher is supported.

echo "Deployed pgsql service"
