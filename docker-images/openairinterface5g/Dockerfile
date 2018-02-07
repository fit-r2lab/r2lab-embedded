FROM fitr2lab/ubuntu16:latest

# the above image already contains /root/r2lab-embedded

RUN mkdir /root/openair \
 && cd /root/openair \
 && git clone https://gitlab.eurecom.fr/oai/openairinterface5g.git 

# build-and-push.sh populates the docker build dir with all shell/* scripts
# it is more convenient this way as we use the versions from our own disk rather
# than the one that is committed in git
COPY * /root/openair/

WORKDIR /root/openair

# lots of small images while developing, a single one would do just fine
RUN ./oai-enb.sh dumpvars
RUN ./oai-enb.sh base
RUN ./oai-enb.sh build

