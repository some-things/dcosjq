#!/bin/bash

read -r -p "Target cluster DC/OS version: " DCOS_VERSION
read -r -p "Target cluster URL (https://<cluster-url>): " MASTER_IP

curl -s https://downloads.dcos.io/binaries/cli/linux/x86-64/dcos-$(echo $DCOS_VERSION | cut -d '.' -f -2)/dcos -o dcos
mv dcos /usr/local/bin
chmod +x /usr/local/bin/dcos
dcos cluster setup $MASTER_IP
dcos node