#!/usr/bin/env bash
# Startup script is only run ONCE when the instance is first launched
set -euxo pipefail
###############################################################################
# ACTION REQUIRED: REPLACE THE URL AND REVISION WITH YOUR DEPLOYMENT REPO INFO
###############################################################################
DEPLOY_SOURCEGRAPH_DOCKER_FORK_CLONE_URL='https://github.com/sourcegraph/delivery-tiger-docker-compose-test.git'
DEPLOY_SOURCEGRAPH_DOCKER_FORK_REVISION='m'
##################### NO CHANGES REQUIRED BELOW THIS LINE #####################
DEPLOY_SOURCEGRAPH_DOCKER_CHECKOUT='/home/ec2-user/deploy-sourcegraph-docker'
DOCKER_COMPOSE_VERSION='1.29.2'
DOCKER_DAEMON_CONFIG_FILE='/etc/docker/daemon.json'
DOCKER_DATA_ROOT='/mnt/docker-data'
EBS_VOLUME_DEVICE_NAME='/dev/sdb'
EBS_VOLUME_LABEL='sourcegraph'
# Install git
yum update -y
yum install git -y
# Clone the deployment repository
git clone "${DEPLOY_SOURCEGRAPH_DOCKER_FORK_CLONE_URL}" "${DEPLOY_SOURCEGRAPH_DOCKER_CHECKOUT}"
cd "${DEPLOY_SOURCEGRAPH_DOCKER_CHECKOUT}"
git checkout "${DEPLOY_SOURCEGRAPH_DOCKER_FORK_REVISION}"
# Format (if unformatted) and then mount the attached volume
device_fs=$(lsblk "${EBS_VOLUME_DEVICE_NAME}" --noheadings --output fsType)
if [ "${device_fs}" == "" ]; then
    mkfs -t xfs "${EBS_VOLUME_DEVICE_NAME}"
fi
xfs_admin -L "${EBS_VOLUME_LABEL}" "${EBS_VOLUME_DEVICE_NAME}"
mkdir -p "${DOCKER_DATA_ROOT}"
mount -L "${EBS_VOLUME_LABEL}" "${DOCKER_DATA_ROOT}"
# Mount data disk on reboots by linking disk label to data root path
echo "LABEL=${EBS_VOLUME_LABEL}  ${DOCKER_DATA_ROOT}  xfs  defaults,nofail  0  2" >>'/etc/fstab'
umount "${DOCKER_DATA_ROOT}"
mount -a
# Install, configure, and enable Docker
yum update -y
amazon-linux-extras install docker
systemctl enable --now docker
sed -i -e 's/1024/262144/g' /etc/sysconfig/docker
sed -i -e 's/4096/262144/g' /etc/sysconfig/docker
usermod -a -G docker ec2-user
# Install jq for scripting
yum install -y jq
## Initialize the config file with empty json if it doesn't exist
if [ ! -f "${DOCKER_DAEMON_CONFIG_FILE}" ]; then
    mkdir -p "$(dirname "${DOCKER_DAEMON_CONFIG_FILE}")"
    echo '{}' >"${DOCKER_DAEMON_CONFIG_FILE}"
fi
## Point Docker storage to mounted volume
tmp_config=$(mktemp)
trap "rm -f ${tmp_config}" EXIT
cat "${DOCKER_DAEMON_CONFIG_FILE}" | jq --arg DATA_ROOT "${DOCKER_DATA_ROOT}" '.["data-root"]=$DATA_ROOT' >"${tmp_config}"
cat "${tmp_config}" >"${DOCKER_DAEMON_CONFIG_FILE}"
# Restart Docker daemon to pick up new changes
systemctl restart --now docker
# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
curl -L "https://raw.githubusercontent.com/docker/compose/${DOCKER_COMPOSE_VERSION}/contrib/completion/bash/docker-compose" -o /etc/bash_completion.d/docker-compose
# Start Sourcegraph with Docker Compose
cd "${DEPLOY_SOURCEGRAPH_DOCKER_CHECKOUT}"/docker-compose
docker-compose up -d --remove-orphans
# Add cron job to root to run docker-compose up at reboot to pick up new changes if available
DOCKER_UP_ON_REBOOT="/usr/local/bin/docker-compose -f ${DEPLOY_SOURCEGRAPH_DOCKER_CHECKOUT}/docker-compose/docker-compose.yaml up -d"
echo "@reboot ${DOCKER_UP_ON_REBOOT}" | crontab -
