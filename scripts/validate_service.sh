#!/bin/bash -xe
# This script will exit immediately if any command fails
# Log all commands and their output to a file
exec > >(tee /tmp/validate_service_log.txt) 2>&1

# Wait for 5 seconds to give the server time to start
sleep 5
# Use curl to check if the flask app is responding on its local port
curl -f http://127.0.0.1:5000/