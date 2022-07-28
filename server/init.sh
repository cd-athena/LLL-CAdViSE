#!/bin/bash

mkdir -p /home/ec2-user/dataset/live/

curl --silent --location https://rpm.nodesource.com/setup_16.x | sudo bash -
sudo yum -y install nodejs jq git gcc72 gcc72-c++ python38 python38-pip python38-devel &>/dev/null

git clone --depth 1 --single-branch --branch master https://github.com/cd-athena/wondershaper.git /home/ec2-user/wondershaper
git clone --depth 1 --single-branch --branch master https://github.com/itu-p1203/itu-p1203.git /home/ec2-user/p1203

cd /home/ec2-user/ || exit 1
sudo npm i && sudo npm i -g pm2
sudo ln -s /home/ec2-user/node_modules/ffmpeg-static/ffmpeg /bin/ffmpeg
sudo ln -s /home/ec2-user/node_modules/ffprobe-static/bin/linux/x64/ffprobe /bin/ffprobe
sudo pip-3.8 install Cython ./p1203/

exit 0
