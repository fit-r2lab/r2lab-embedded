#!/bin/bash

source $(dirname $(readlink -f $BASH_SOURCE))/nodes.sh

source $(dirname $(readlink -f $BASH_SOURCE))/oai-common.sh

COMMAND=$(basename "$BASH_SOURCE")

doc-nodes-sep "#################### commands for managing an OAI core-network"

### frontend:
# image: install stuff on top of a basic ubuntu image
# configure: do at least once after restoring an image
# start: start services
# stop:
# journal: wrapper around journalctl for the 3 bundled services

### to test locally (adjust slicename if needed)
# apssh -g inria_oai@faraday.inria.fr -t root@fit01 -i nodes.sh -i r2labutils.sh -i oai-common.sh -s oai-cn.sh image



###### imaging

doc-nodes image "frontend for rebuilding this image"
function image() {
    dependencies-for-core-network
    configure-grub-cstate
    install-core-network
}

doc-nodes dependencies-for-core-network "prepare ubuntu for core network"
function dependencies-for-core-network() {
    git-pull-r2lab
    # apt-get requirements
    apt-get update
    apt-get install -y emacs

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

    -sed-configurator /etc/modprobe.d/blacklist.conf << EOF
/blacklist intel_powerclamp/{q}
\$a"blacklist intel_powerclamp"
EOF
}

doc-nodes install-core-network "install oai-cn snap"
function install-core-network() {

    cd
    -snap-install oai-cn
    # need to stop stuff, not sure why it starts in the first place
    # problem here is, right after snap-installing it looks like
    # oai-cn.stop-all can't be found..
    -enable-snap-bins
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

    -enable-snap-bins
    local r2lab_id=$(r2lab-id)
    # not quite sure how this sohuld work
    # the conf-get commands return file paths
    # but that works only for the 3 main conf files
    local hss_conf=$(oai-cn.hss-conf-get)
    local snap_config_dir=$(dirname $hss_conf)

    cd $snap_config_dir

# xxx about /etc/hosts, that apparently gets
# modified by the snap install, and needs to be ironed out

    -sed-configurator acl.conf << EOF
s|^ALLOW_OLD_TLS.*|ALLOW_OLD_TLS *.r2lab.fr|g
EOF

    -sed-configurator hss_fd.conf << EOF
s|^Identity.*=.*|Identity = "fit${r2lab_id}.r2lab.fr";|
s|^Realm.*=.*|Realm = "r2lab.fr";|
EOF

    -sed-configurator mme_fd.conf << EOF
s|^Identity.*=.*|Identity = "fit${r2lab_id}.r2lab.fr";|
s|^Realm.*=.*|Realm = "r2lab.fr";|
EOF

    -sed-configurator hss.conf << EOF
s|^OPERATOR_key.*=.*|OPERATOR_key = "11111111111111111111111111111111";|
EOF

# s|VAR.*=.*"[^"]*";|VAR = "value";|
    -sed-configurator mme.conf << EOF
s|REALM.*=.*|REALM = "r2lab.fr";|
s|HSS_HOSTNAME.*=.*|HSS_HOSTNAME = "fit${r2lab_id}";|
s|MNC="[0-9]+"|MNC="95"|
s|MME_INTERFACE_NAME_FOR_S1_MME.*=.*"[^"]*";|MME_INTERFACE_NAME_FOR_S1_MME = "data";|
s|MME_IPV4_ADDRESS_FOR_S1_MME.*=.*"[^"]*";|MME_IPV4_ADDRESS_FOR_S1_MME = "192.168.2.${r2lab_id}/24";|
s|MME_IPV4_ADDRESS_FOR_S11_MME.*=.*"[^"]*";|MME_IPV4_ADDRESS_FOR_S11_MME = "127.0.2.1/8";|
s|SGW_IPV4_ADDRESS_FOR_S11.*=.*"[^"]*";|SGW_IPV4_ADDRESS_FOR_S11 = "127.0.3.1/8";|
EOF

    -sed-configurator spgw.conf << EOF
s|SGW_IPV4_ADDRESS_FOR_S11.*=.*"[^"]*";|SGW_IPV4_ADDRESS_FOR_S11 = "127.0.3.1/8";|
s|SGW_INTERFACE_NAME_FOR_S1U_S12_S4_UP.*=.*"[^"]*";|SGW_INTERFACE_NAME_FOR_S1U_S12_S4_UP = "data";|
s|SGW_IPV4_ADDRESS_FOR_S1U_S12_S4_UP.*=.*"[^"]*";|SGW_IPV4_ADDRESS_FOR_S1U_S12_S4_UP = "192.168.2.${r2lab_id}/24";|
s|PGW_INTERFACE_NAME_FOR_SGI.*=.*"[^"]*";|PGW_INTERFACE_NAME_FOR_SGI = "control";|
s|PGW_MASQUERADE_SGI.*=.*"[^"]*";|PGW_MASQUERADE_SGI = "yes";|
s|DEFAULT_DNS_IPV4_ADDRESS.*=.*"[^"]*";|DEFAULT_DNS_IPV4_ADDRESS = "138.96.0.10";|
s|DEFAULT_DNS_SEC_IPV4_ADDRESS.*=.*"[^"]*";|DEFAULT_DNS_SEC_IPV4_ADDRESS = "138.96.0.11";|
EOF

    -sed-configurator /etc/hosts << EOF
s|fit.*hss|fit${r2lab_id}.r2lab.fr fit${r2lab_id} hss|
s|fit.*mme|fit${r2lab_id}.r2lab.fr fit${r2lab_id} mme|
EOF

}

doc-nodes configure-r2lab-devices "Enter R2lab local SIM's into HSS database"
function configure-r2lab-devices() {
    -enable-snap-bins
    oai-cn.hss-add-user 208950000000002 8BAF473F2F8FD09487CCCBD7097C6862 20 7 # SIM 02, Nexus 5
    oai-cn.hss-add-user 208950000000003 8BAF473F2F8FD09487CCCBD7097C6862 20 7 # SIM 03, OAI UE on fit06
    oai-cn.hss-add-user 208950000000004 8BAF473F2F8FD09487CCCBD7097C6862 20 7 # SIM 04, Moto E2 4G
    oai-cn.hss-add-user 208950000000005 8BAF473F2F8FD09487CCCBD7097C6862 20 7 # SIM 05, Huawei 3372 LTE on fit26
    oai-cn.hss-add-user 208950000000007 8BAF473F2F8FD09487CCCBD7097C6862 20 7 # SIM 07, Huawei 3372 LTE on fit02
}

doc-nodes reinit-core-network "Required to have configuration changes taken into account"
function reinit-core-network() {
    -enable-snap-bins
    oai-cn.hss-init
    oai-cn.mme-init
    oai-cn.spgw-init
}



###### running
function start() {
    -enable-snap-bins
    oai-cn.start-all
}

function stop() {
    -enable-snap-bins
    oai-cn.stop-all
}

function journal() {
    units="snap.oai-cn.hssd.service snap.oai-cn.mmed.service snap.oai-cn.spgwd.service"
    jopts=""
    for unit in $units; do jopts="$jopts --unit $unit"; done
    journalctl $jopts "$@"
}

###### helpers
# basic tool to ease patches; expects
# (*) on the command line the file to patch
# (*) on stdin a sed file to apply on that file
function -sed-configurator() {
    local target=$1; shift
    local original=$target.orig
    local stem=$(basename $target)
    local sedname=/tmp/$stem.$$.sed
    local tmptarget=/tmp/$stem.$$

    # store stdin in a file
    cat > $sedname

    # be explicit about backups
    [ -f $original ] || { echo "Backing up $target"; cp $target $original; }

    # compute new version; preserve modes
    cp $target $tmptarget
    # give an extension to -i so that it also works on mac for devel
    sed -f $sedname -i.4mac $tmptarget
    # change target only if needed
    cmp --silent $target $tmptarget || {
        echo "(Over)writing $target (through $sedname)"
        mv -f $tmptarget $target
    }
}

# the options to use with snap for these packages
function -snap-install() {
    local package=$1; shift
    local command="snap install --channel=edge --devmode $package"
    echo "Installing: $command"
    $command
}

function -enable-snap-bins() {
    echo $PATH | grep -q /snap/bin || export PATH=$PATH:/snap/bin
}

########################################
define-main "$0" "$BASH_SOURCE"
main "$@"
