#!/bin/bash

source $(dirname $(readlink -f $BASH_SOURCE))/nodes.sh

source $(dirname $(readlink -f $BASH_SOURCE))/mosaic-common.sh

COMMAND=$(basename "$BASH_SOURCE")

doc-nodes-sep "#################### commands for managing a MOSAIC core-network"

### frontend:
# image: install stuff on top of a basic ubuntu image
# configure: do at least once after restoring an image
# start: start services
# stop:
# journal: wrapper around journalctl for the 3 bundled services

### to test locally (adjust slicename if needed)
# apssh -g inria_oai@faraday.inria.fr -t root@fit01 -i nodes.sh -i r2labutils.sh -i mosaic-common.sh -s mosaic-cn.sh image


mosaic_role="cn"
mosaic_long="core network"


###### imaging

doc-nodes image "frontend for rebuilding this image"
function image() {
    dependencies-for-core-network
    configure-grub-cstate
    install-core-network
    mosaic-as-cn
}

doc-nodes dependencies-for-core-network "prepare ubuntu for core network"
function dependencies-for-core-network() {
    git-pull-r2lab
    # apt-get requirements
    apt-get update
    apt-get install -y emacs i7z

    echo "========== Installing mysql-server"
    debconf-set-selections <<< 'mysql-server mysql-server/root_password password linux'
    debconf-set-selections <<< 'mysql-server mysql-server/root_password_again password linux'
    apt-get install -y mysql-server

    # this might not be 100% necessary but can't hurt
    echo "========== Installing phpmyadmin - provide mysql-server password as linux and set password=admin"
    debconf-set-selections <<< 'phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2'
    debconf-set-selections <<< 'phpmyadmin phpmyadmin/dbconfig-install boolean true'
    # the one we used just above for mysql-server
    debconf-set-selections <<< 'phpmyadmin phpmyadmin/mysql/admin-pass password linux'
    # password for phpadmin itself
    debconf-set-selections <<< 'phpmyadmin phpmyadmin/mysql/app-pass password admin'
    debconf-set-selections <<< 'phpmyadmin phpmyadmin/app-password-confirm password admin'
    apt-get install -y phpmyadmin

}

doc-nodes configure-grub-cstate "tweak grub config and modprobe blacklist for cstates"
function configure-grub-cstate() {

    -sed-configurator /etc/default/grub << EOF
s|^GRUB_CMDLINE_LINUX_DEFAULT.*=.*|GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_pstate=disable processor.max_cstate=1 intel_idle.max_cstate=0 idle=poll"|
EOF

    # in the following, we need to backslash $ because otherwise it is
    # interpreted by bash as ${a}
    -sed-configurator /etc/modprobe.d/blacklist.conf << EOF
/^blacklist intel_powerclamp/{q}
\$ablacklist intel_powerclamp
EOF
}

doc-nodes install-core-network "install oai-cn snap"
function install-core-network() {

    cd
    -snap-install oai-cn
    # need to stop stuff, not sure why it starts in the first place
    # problem here is, right after snap-installing it looks like
    # oai-cn.stop-all can't be found..
    #-enable-snap-bins
    # just in case
    oai-cn.stop-all
}



###### configuring

doc-nodes configure "configure core network for r2lab"
function configure() {

    configure-core-network
    configure-r2lab-devices
    reinit-core-network
}

doc-nodes configure-core-network "configure hss, mme, spgw, and /etc/hosts"
function configure-core-network() {

    #-enable-snap-bins
    local r2lab_id=$(r2lab-id -s)
    local r2lab_ip=$(r2lab-ip -s)
    # not quite sure how this sohuld work
    # the conf-get commands return file paths
    # but that works only for the 3 main conf files
    local hss_conf=$(oai-cn.hss-conf-get)
    local snap_config_dir=$(dirname $hss_conf)

    cd $snap_config_dir

# xxx about /etc/hosts, that apparently gets
# modified by the snap install, and needs to be ironed out

    -sed-configurator acl.conf << EOF
s|^ALLOW_OLD_TLS.*|ALLOW_OLD_TLS *.${mosaic_realm}|g
EOF

    -sed-configurator hss_fd.conf << EOF
s|^Identity.*=.*|Identity = "fit${r2lab_id}.${mosaic_realm}";|
s|^Realm.*=.*|Realm = "${mosaic_realm}";|
EOF

    -sed-configurator mme_fd.conf << EOF
s|^Identity.*=.*|Identity = "fit${r2lab_id}.${mosaic_realm}";|
s|^Realm.*=.*|Realm = "${mosaic_realm}";|
s|^ConnectPeer.*|ConnectPeer= "fit${r2lab_id}.${mosaic_realm}" { ConnectTo = "192.168.${mosaic_subnet}.${r2lab_ip}"; No_SCTP ; No_IPv6; Prefer_TCP; No_TLS; port = 3868;  realm = "${mosaic_realm}";};|

EOF

    -sed-configurator hss.conf << EOF
s|^OPERATOR_key.*=.*|OPERATOR_key = "11111111111111111111111111111111";|
EOF

# s|VAR.*=.*"[^"]*";|VAR = "value";|
    -sed-configurator mme.conf << EOF
s|REALM.*=.*|REALM = "${mosaic_realm}";|
s|HSS_HOSTNAME.*=.*|HSS_HOSTNAME = "fit${r2lab_id}";|
s|MNC="[0-9][0-9]*"|MNC="95"|
s|MME_INTERFACE_NAME_FOR_S1_MME.*=.*"[^"]*";|MME_INTERFACE_NAME_FOR_S1_MME = "${mosaic_ifname}";|
s|MME_IPV4_ADDRESS_FOR_S1_MME.*=.*"[^"]*";|MME_IPV4_ADDRESS_FOR_S1_MME = "192.168.${mosaic_subnet}.${r2lab_ip}/24";|
s|MME_IPV4_ADDRESS_FOR_S11_MME.*=.*"[^"]*";|MME_IPV4_ADDRESS_FOR_S11_MME = "127.0.2.1/8";|
s|SGW_IPV4_ADDRESS_FOR_S11.*=.*"[^"]*";|SGW_IPV4_ADDRESS_FOR_S11 = "127.0.3.1/8";|
EOF

    -sed-configurator spgw.conf << EOF
s|SGW_IPV4_ADDRESS_FOR_S11.*=.*"[^"]*";|SGW_IPV4_ADDRESS_FOR_S11 = "127.0.3.1/8";|
s|SGW_INTERFACE_NAME_FOR_S1U_S12_S4_UP.*=.*"[^"]*";|SGW_INTERFACE_NAME_FOR_S1U_S12_S4_UP = "${mosaic_ifname}";|
s|SGW_IPV4_ADDRESS_FOR_S1U_S12_S4_UP.*=.*"[^"]*";|SGW_IPV4_ADDRESS_FOR_S1U_S12_S4_UP = "192.168.${mosaic_subnet}.${r2lab_ip}/24";|
s|PGW_INTERFACE_NAME_FOR_SGI.*=.*"[^"]*";|PGW_INTERFACE_NAME_FOR_SGI = "control";|
s|PGW_MASQUERADE_SGI.*=.*"[^"]*";|PGW_MASQUERADE_SGI = "yes";|
s|DEFAULT_DNS_IPV4_ADDRESS.*=.*"[^"]*";|DEFAULT_DNS_IPV4_ADDRESS = "138.96.0.10";|
s|DEFAULT_DNS_SEC_IPV4_ADDRESS.*=.*"[^"]*";|DEFAULT_DNS_SEC_IPV4_ADDRESS = "138.96.0.11";|
EOF

    -sed-configurator /etc/hosts << EOF
s|fit.*hss|fit${r2lab_id}.${mosaic_realm} fit${r2lab_id} hss|
s|fit.*mme|fit${r2lab_id}.${mosaic_realm} fit${r2lab_id} mme|
EOF

# this one is for convenience, avoiding journald to broadcast stuff on wall
    -sed-configurator /etc/systemd/journald.conf << EOF
s|.*ForwardToWall=.*|ForwardToWall=no|
EOF
    systemctl restart systemd-journald

}

doc-nodes configure-r2lab-devices "Enter R2lab local SIM's into HSS database"
function configure-r2lab-devices() {
    #-enable-snap-bins
    oai-cn.hss-add-user 208950000000002 8BAF473F2F8FD09487CCCBD7097C6862 20 7 # SIM 02, Nexus 5 - phone 1
    oai-cn.hss-add-user 208950000000003 8BAF473F2F8FD09487CCCBD7097C6862 20 7 # SIM 03, OAI UE on fit06
    oai-cn.hss-add-user 208950000000004 8BAF473F2F8FD09487CCCBD7097C6862 20 7 # SIM 04, Moto E2 4G - phone 2
    oai-cn.hss-add-user 208950000000005 8BAF473F2F8FD09487CCCBD7097C6862 20 7 # SIM 05, Huawei 3372 LTE on fit26
    oai-cn.hss-add-user 208950000000007 8BAF473F2F8FD09487CCCBD7097C6862 20 7 # SIM 07, Huawei 3372 LTE on fit02
}

doc-nodes reinit-core-network "Required to have configuration changes taken into account"
function reinit-core-network() {
    #-enable-snap-bins
    oai-cn.hss-init
    oai-cn.mme-init
    oai-cn.spgw-init
}



###### running
doc-nodes start "Start all CN services"
function start() {
    echo "Checking interface is up : $(turn-on-data)"
    #-enable-snap-bins
    oai-cn.start-all
}

doc-nodes stop "Stop all CN services"
function stop() {
    #-enable-snap-bins
    oai-cn.stop-all
}

doc-nodes status "Displays status of all CN services"
function status() {
    #-enable-snap-bins
    oai-cn.status-all
}

doc-nodes journal "Wrapper around journalctl about all CN services - use with -f to follow up"
function journal() {
    units="snap.oai-cn.hssd.service snap.oai-cn.mmed.service snap.oai-cn.spgwd.service"
    jopts=""
    for unit in $units; do jopts="$jopts --unit $unit"; done
    journalctl $jopts "$@"
}

doc-nodes "cd into configuration directory for CN service"
function configure-directory() {
    local conf_dir=$(dirname $(oai-cn.hss-conf-get))
    cd $conf_dir
}


########################################
define-main "$0" "$BASH_SOURCE"
main "$@"
