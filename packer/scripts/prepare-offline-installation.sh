#!/bin/bash -e

# Preparations for offline installations:
#
# * Download debian packages into the local package cache
# * Pull required docker images
# * Download 3rd party files
# * Build Python modules
#

REGULAR_PACKAGES="
git
dnsmasq
mariadb-server
mariadb-client
python-mysqldb
keepalived
nginx-light
python-redis
redis-tools
redis-server
nfs-kernel-server
rpcbind
glusterfs-server
glusterfs-client
nfs-common
mytop
galera
percona-xtrabackup-24
socat
"

BACKPORTS_PACKAGES="
python-backports.ssl-match-hostname
python-docker
python-docopt
python-enum34
python-functools32
python-ipaddress
python-jsonschema
python-requests
python-texttable
"

DOCKER_IMAGES="
teamwire/backend:${BACKEND_RELEASE}
teamwire/web-screenshot-server:${BACKEND_RELEASE}
teamwire/notification-server:${BACKEND_RELEASE}
$(awk '{ gsub("\"",""); print $2; }' ~teamwire/platform/ansible/roles/docker/vars/main.yml)
$(awk '/^redis_container:/ { print $2 }' ~teamwire/platform/ansible/roles/redis/vars/main.yml)
"

CONSUL_VERSION=$(awk '/^consul_version:/ { print $2 }' ~teamwire/platform/ansible/roles/consul/vars/main.yml)
# File URL and SHA256 checksum separated by a semicolon
DOWNLOADS="
https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip;$(awk '/^consul_checksum:/ { print $2 }' ~teamwire/platform/ansible/roles/consul/vars/main.yml)
https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_web_ui.zip;$(awk '/^consul_ui_checksum:/ { print $2 }' ~teamwire/platform/ansible/roles/consul/vars/main.yml)
https://releases.hashicorp.com/consul-template/0.15.0/consul-template_0.15.0_linux_amd64.zip;b7561158d2074c3c68ff62ae6fc1eafe8db250894043382fb31f0c78150c513a
"

PYTHON_MODULES="
cached_property==1.2.0
docker_compose==1.8.1
docker-py==1.10.3
docker-pycreds==0.2.1
dockerpty==0.4.1
websocket_client==0.32.0
"

# Add additional repo signing keys
# Always perform this step, even if not preparing for offline installation - this spares us some firewall rules
echo "Step 1: Import additional repo signing keys"
echo "==========================================="
sudo apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 9DC858229FC7DD38854AE2D88D81803C0EBFCD88 # Docker
sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys cbcb082a1bb943db # MariaDB
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 8507EFA5 # Percona

if [ -z "$OFFLINE_INSTALLATION" ] ; then
	echo "Not preparing for offline installation."
	exit
fi

echo "Preparing for offline installation."

# This file will be checked by the Ansible scripts; if it exists,
# the apt cache will not be updated.
sudo touch /etc/offline_installation

echo "Step 2: Caching packages"
echo "========================"

# Add MariaDB and Percona repo
echo 'deb http://ftp.hosteurope.de/mirror/mariadb.org/repo/10.1/debian jessie main' | sudo tee -a /etc/apt/sources.list > /dev/null
echo 'deb http://repo.percona.com/apt jessie main' | sudo tee -a /etc/apt/sources.list > /dev/null
sudo apt-get update -q
sudo apt-get install -qyd $REGULAR_PACKAGES
sudo apt-get install -t jessie-backports -qyd $BACKPORTS_PACKAGES

echo "Step 3: Getting Docker containers"
echo "================================="
# We need to use sudo as the teamwire user is apparently not yet updated
sudo docker login -u "$DOCKERHUB_USERNAME" -p "$DOCKERHUB_PASSWORD"
for IMAGE in $DOCKER_IMAGES ; do
	sudo docker pull "${IMAGE}"
done
sudo rm -rf /root/.docker

cd ~/platform/ansible/group_vars
cp all.example all
sed -i -e 's/^\(version: \).*$/\1'"$BACKEND_RELEASE"'/' all

echo "Step 4: Downloading 3rd party software"
echo "======================================"
if [ ! -d /var/cache/downloads ] ; then
	sudo mkdir /var/cache/downloads
fi
for DOWNLOAD in $DOWNLOADS ; do
	# split line into URL and SHA256 checksum
	UC=(${DOWNLOAD//;/ })
	echo "Getting ${UC[0]}"
	wget -q "${UC[0]}"
	FILENAME="${UC[0]##*/}"
	if [ "${UC[1]}" != "$(sha256sum "${FILENAME}" | cut -d' ' -f1)" ] ; then
		echo "${FILENAME}: Checksum failure"
		exit 1
	fi
	sudo mv "$FILENAME" /var/cache/downloads
done

echo "Step 5: Building Python modules"
echo "======================================"
WHEEL_DIR="$(mktemp -d)"
sudo apt-get -y install python-pip python-wheel
for PYTHON_MODULE in $PYTHON_MODULES ; do
	pip wheel --wheel-dir "$WHEEL_DIR" --no-deps "$PYTHON_MODULE"
done
sudo apt-get -y remove python-pip python-wheel
sudo apt-get -y autoremove
sudo mv "$WHEEL_DIR" /var/cache/wheelhouse
