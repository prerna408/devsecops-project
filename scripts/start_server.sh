#!/bin/bash -xe
# This script will exit immediately if any command fails
# Log all commands and their output to a file
exec > >(tee /tmp/start_server_log.txt) 2>&1

echo "Running start_server.sh as ubuntu user"
cd /home/ubuntu/app
# Kill anything on port 5000, ignore error if nothing is running
fuser -k 5000/tcp || true
# Find flask and run it, logging to a separate app log
# Use python3 to run the flask module directly, which is more reliable for backgrounding
nohup python3 -m flask run --host=0.0.0.0 --port=5000 > /home/ubuntu/app/app.log 2>&1 &