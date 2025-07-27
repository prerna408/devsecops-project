#!/bin/bash

# This script is run by the CodeDeploy agent on the EC2 instance

# Navigate to the application directory
cd /home/ec2-user/app

# Kill any process that's already running on port 5000 to avoid conflicts
# Use fuser to be more reliable than pkill
fuser -k 5000/tcp

# Start the Flask application in the background.
# CRITICAL: Use the full path to the flask executable installed by pip3
# Log stdout and stderr to a file for easier debugging
nohup /usr/local/bin/flask run --host=0.0.0.0 --port=5000 > /home/ec2-user/app/app.log 2>&1 &