FROM selenium/standalone-chrome-debug:latest
MAINTAINER babak.taraghi@aau.at

RUN sudo curl -sL https://deb.nodesource.com/setup_16.x | sudo bash -
RUN sudo apt-get update && sudo apt-get install -y nodejs python3-pip
RUN pip install selenium

WORKDIR /home/seluser/cadvise

COPY runPlayer.py .
RUN sudo chmod 755 ./runPlayer.py

COPY player ./player
COPY server.js .
COPY package.json .
COPY package-lock.json .

RUN sudo npm i && sudo npm i -g pm2
