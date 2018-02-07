FROM coreapps/ubuntu16.04:latest

# the typical substrate to start from

USER root

RUN apt-get -y update \
 && apt-get -y upgrade \
 && apt-get -y install python3 python3-pip \
 && apt-get install -y git emacs24-nox \
 && pip3 install -U pip \
 && pip3 install asynciojobs apssh

RUN cd /root \
 && git clone https://github.com/fit-r2lab/r2lab-embedded.git
