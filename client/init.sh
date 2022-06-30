#!/bin/bash

sudo yum -y install docker jq git &>/dev/null

sudo service docker start
sudo git clone https://github.com/cd-athena/wondershaper.git /home/ec2-user/wondershaper

sudo docker pull babakt/lll-cadvise-client:latest &>/dev/null
sudo docker run --rm -d --name "lll-cadvise-client" -p 5900:5900 -v /dev/shm:/dev/shm babakt/lll-cadvise-client:latest

sudo docker cp /home/ec2-user/config.json "lll-cadvise-client:/home/seluser/cadvise/config.json"
sudo docker exec -d "lll-cadvise-client" sudo pm2 start server.js

exit 0
