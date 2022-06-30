#!/bin/bash

mkdir -p /home/ec2-user/dataset/live/

curl --silent --location https://rpm.nodesource.com/setup_16.x | sudo bash -
sudo yum -y install nodejs jq git &>/dev/null

git clone https://github.com/cd-athena/wondershaper.git /home/ec2-user/wondershaper

cd /home/ec2-user/ || exit 1
sudo npm i && sudo npm i -g pm2

exit 0
