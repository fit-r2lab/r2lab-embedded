FROM ubuntu:latest

ENV TZ=Europe/Paris
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Install necessary binaries for tutorials
RUN apt update -y \
 && apt upgrade -y \
 && apt install iputils-ping openssh-client openssh-server bash netcat iproute2 net-tools tcpdump dnsutils netcat nano vim python3 python3-pip git emacs-nox network-manager -y

RUN pip3 install -U pip && pip3 install asynciojobs apssh

RUN git clone https://github.com/fit-r2lab/r2lab-embedded.git /root/r2lab-embedded

RUN rm /root/.bashrc
RUN ln -s /root/r2lab-embedded/shell/nodes.sh /root/.bashrc

RUN ln -s /root/r2lab-embedded/shell/nodes.sh /etc/profile.d/nodes.sh

RUN ln -s /root/r2lab-embedded/shell/nodes.sh /root/.bash_profile

# Setup Bash prompt to not get lost when in interactive mode
RUN echo "PS1='[CONTAINER]${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '" | tee -a /root/.bashrc > /dev/null