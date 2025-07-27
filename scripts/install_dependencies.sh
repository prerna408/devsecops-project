#!/bin/bash -xe
# This script will exit immediately if any command fails
# Log all commands and their output to a file
exec > >(tee /tmp/install_dependencies_log.txt) 2>&1

echo "Running install_dependencies.sh as root"
cd /home/ubuntu/app
chown -R ubuntu:ubuntu /home/ubuntu/app
chmod +x scripts/*.sh
/usr/bin/pip3 install -r requirements.txt