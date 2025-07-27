#!/bin/bash
# Stop any old version of the app that might be running
pkill -f flask

# Go to the application directory
cd /home/ec2-user/app

# Start the new application in the background
nohup python3 -m flask run --host=0.0.0.0 &