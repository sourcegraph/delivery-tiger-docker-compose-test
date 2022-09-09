#!/usr/bin/env bash
set -euxo pipefail
###############################################################################
# ACTION REQUIRED: REPLACE THE URL AND REVISION WITH YOUR DEPLOYMENT REPO INFO
###############################################################################
DEPLOY_SOURCEGRAPH_DOCKER_FORK_CLONE_URL='https://github.com/sourcegraph/delivery-tiger-docker-compose-test.git'
DEPLOY_SOURCEGRAPH_DOCKER_FORK_REVISION='tier0-azure'
###############################################################################
# STARTUP SCRIPT FOR AN AWS DOCKER COMPOSE INSTANCE
# NO CHANGES REQUIRED FROM THIS POINT ONWARD
###############################################################################
# Define variables
DEPLOY_SOURCEGRAPH_DOCKER_CHECKOUT='/root/deploy-sourcegraph-docker'
DOCKER_DATA_ROOT='/mnt/docker-data'
DOCKER_COMPOSE_VERSION='1.29.2'
DOCKER_DAEMON_CONFIG_FILE='/etc/docker/daemon.json'
PERSISTENT_DISK_DEVICE_NAME='/dev/sdb'
PERSISTENT_DISK_LABEL='sourcegraph'
# Install git
sudo apt-get update -y
sudo apt-get install -y git
# Clone the deployment repository
git clone "${DEPLOY_SOURCEGRAPH_DOCKER_FORK_CLONE_URL}" "${DEPLOY_SOURCEGRAPH_DOCKER_CHECKOUT}"
cd "${DEPLOY_SOURCEGRAPH_DOCKER_CHECKOUT}"
git checkout "${DEPLOY_SOURCEGRAPH_DOCKER_FORK_REVISION}"
# Format (if unformatted) and mount persistent disk for docker instance data
device_fs=$(sudo lsblk "${PERSISTENT_DISK_DEVICE_NAME}" --noheadings --output fsType)
if [ "${device_fs}" == "" ]; then
    sudo mkfs.ext4 -m 0 -E lazy_itable_init=0,lazy_journal_init=0,discard "${PERSISTENT_DISK_DEVICE_NAME}"
    sudo e2label "${PERSISTENT_DISK_DEVICE_NAME}" "${PERSISTENT_DISK_LABEL}"
fi
sudo mkdir -p "${DOCKER_DATA_ROOT}"
sudo mount -o discard,defaults "${PERSISTENT_DISK_DEVICE_NAME}" "${DOCKER_DATA_ROOT}"
# Mount data disk on reboots by linking disk label to data root path
sudo echo "LABEL=${PERSISTENT_DISK_LABEL}  ${DOCKER_DATA_ROOT}  ext4  discard,defaults,nofail  0  2" | sudo tee -a /etc/fstab
umount "${DOCKER_DATA_ROOT}"
mount -a
# Install Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo apt-get update -y
sudo apt-get install -y software-properties-common
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
sudo apt-get update -y
apt-cache policy docker-ce
apt-get install -y docker-ce docker-ce-cli containerd.io
# Install jq for scripting
sudo apt-get update -y
sudo apt-get install -y jq
## Initialize the config file with empty json if it doesn't exist
if [ ! -f "${DOCKER_DAEMON_CONFIG_FILE}" ]; then # Edit Docker storage directory to mounted volume
    mkdir -p $(dirname "${DOCKER_DAEMON_CONFIG_FILE}")
    echo '{}' >"${DOCKER_DAEMON_CONFIG_FILE}"
fi
## Point Docker's 'data-root' to the mounted disk
tmp_config=$(mktemp)
trap "rm -f ${tmp_config}" EXIT
sudo cat "${DOCKER_DAEMON_CONFIG_FILE}" | sudo jq --arg DATA_ROOT "${DOCKER_DATA_ROOT}" '.["data-root"]=$DATA_ROOT' >"${tmp_config}"
sudo cat "${tmp_config}" >"${DOCKER_DAEMON_CONFIG_FILE}"
## Enable Docker at startup
sudo systemctl enable docker
# Restart Docker daemon to pick up new changes
sudo systemctl restart --now docker
# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
curl -L "https://raw.githubusercontent.com/docker/compose/${DOCKER_COMPOSE_VERSION}/contrib/completion/bash/docker-compose" -o /etc/bash_completion.d/docker-compose
# Run Sourcegraph
cd "${DEPLOY_SOURCEGRAPH_DOCKER_CHECKOUT}"/docker-compose
docker-compose up -d --remove-orphans
SOURCEGRAPH_ON_REBOOT="/usr/local/bin/docker-compose -f /home/ec2-user/deploy-sourcegraph-docker/docker-compose/docker-compose.yaml up -d"
(
    crontab -u ec2-user -l
    echo "@reboot ${SOURCEGRAPH_ON_REBOOT}"
) | crontab -u ec2-user -
