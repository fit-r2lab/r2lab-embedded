FROM ubuntu:latest

# Install necessary binaries for tutorials
RUN apt update -y && apt upgrade -y && apt install kmod iw iputils-ping openssh-client openssh-server bash netcat iproute2 net-tools tcpdump dnsutils netcat nano vim -y

# Setup Bash prompt to not get lost when in interactive mode
RUN echo "PS1='[CONTAINER] ${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '" | tee /root/.bashrc > /dev/null

#Setting up OpenSSH server
RUN sed -ri 's/^#?PermitRootLogin\s+.*/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN sed -ri 's/UsePAM yes/#UsePAM yes/g' /etc/ssh/sshd_config
RUN sed -i 's/#Port 22/Port 2222/g' /etc/ssh/sshd_config
RUN sed -i 's/#ListenAddress 0.0.0.0/ListenAddress 0.0.0.0/g' /etc/ssh/sshd_config
RUN echo "auth sufficient pam_permit.so" | tee -a /etc/pam.d/sshd >> /dev/null

RUN mkdir -p /run/sshd
RUN echo "PermitEmptyPasswords yes" | tee -a /etc/ssh/sshd_config >> /dev/null
RUN passwd -d root

RUN mkdir /root/.ssh

RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*


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

EXPOSE 2222

CMD ["/usr/sbin/sshd", "-D"]