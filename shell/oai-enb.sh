#!/bin/bash

source $(dirname $(readlink -f $BASH_SOURCE))/nodes.sh

doc-nodes-sep "#################### For managing an OAI enodeb"

source $(dirname $(readlink -f $BASH_SOURCE))/oai-common.sh

OPENAIR_HOME=/root/openairinterface5g
build_dir=$OPENAIR_HOME/cmake_targets
run_dir=$build_dir/lte_build_oai/build
lte_log="$run_dir/softmodem.log"
add-to-logs $lte_log
lte_pcap="$run_dir/softmodem.pcap"
add-to-datas $lte_pcap
conf_dir=$OPENAIR_HOME/targets/PROJECTS/GENERIC-LTE-EPC/CONF
template=enb.band7.tm1.usrpb210.conf
#following template name corresponds to the latest buggy develop version
#template=enb.band7.tm1.50PRB.usrpb210.conf
config=r2lab.conf
add-to-configs $conf_dir/$config


doc-nodes dumpvars "list environment variables"
function dumpvars() {
    echo "oai_role=${oai_role}"
    echo "oai_ifname=${oai_ifname}"
    echo "oai_realm=${oai_realm}"
    echo "run_dir=$run_dir"
    echo "conf_dir=$conf_dir"
    echo "template=$template"
    [[ -z "$@" ]] && return
    echo "_configs=\"$(get-configs)\""
    echo "_logs=\"$(get-logs)\""
    echo "_datas=\"$(get-datas)\""
    echo "_locks=\"$(get-locks)\""
}

####################
doc-nodes image "the entry point for nightly image builds"
function image() {
#    deps_arg="$1"; shift
    dumpvars
    base
#    deps "$deps_arg"
    build
}

####################
# would make sense to add more stuff in the base image - see the NEWS file
base_packages="git subversion libboost-all-dev libusb-1.0-0-dev python-mako doxygen python-docutils cmake build-essential libffi-dev texlive-base texlive-latex-base ghostscript gnuplot-x11 dh-apparmor graphviz gsfonts imagemagick-common  gdb ruby flex bison gfortran xterm mysql-common python-pip python-numpy qtcore4-l10n tcl tk xorg-sgml-doctools i7z
"

doc-nodes base "the script to install base software on top of a raw image" 
function base() {

    git-pull-r2lab
    git-pull-oai

    # apt-get requirements
    apt-get update
    apt-get install -y $base_packages

    git-ssl-turn-off-verification
    echo "========== Running git clone for r2lab and openinterface5g"
    cd
    # following should be useless
    [ -d openairinterface5g ] || git clone https://gitlab.eurecom.fr/oai/openairinterface5g.git
    [ -d /root/r2lab ] || git clone https://github.com/parmentelat/r2lab.git
}

doc-nodes build "builds oai5g for an oai image"
function build() {

    git-pull-r2lab
    git-pull-oai

    cd $build_dir
    echo Building OAI5G - see $build_dir/build-oai5g.log
    build-oai5g -x >& build-oai5g.log

}

doc-nodes build-oai5g "builds oai5g - run with -x for building with software oscilloscope" 
function build-oai5g() {

    oscillo=""
    if [ -n "$1" ]; then
	case $1 in
	    -x) oscillo="-x" ;;
	    *) echo "usage: build-oai5g [-x]"; return 1 ;;
	esac
    fi

    cd $OPENAIR_HOME
    source oaienv
    source $HOME/.bashrc

    cd $build_dir

    echo Building in $(pwd) - see 'build*log'
    run-in-log build-oai-1.log ./build_oai -I --eNB $oscillo --install-system-files -w USRP
    run-in-log build-oai-2.log ./build_oai -w USRP $oscillo -c --eNB

}

########################################
# end of image
########################################

# entry point for global orchestration
doc-nodes run-enb "run-enb 23: does init/configure/start with epc running on node 23"
function run-enb() {
    peer=$1; shift
    # pass exactly 'False' to skip usrp-reset
    reset_usrp=$1; shift
    oai_role=enb
    stop
    status
    echo "run-enb: configure $peer"
    configure $peer
    init
    if [ "$reset_usrp" == "False" ]; then
	echo "SKIPPING USRP reset"
    else
	usrp-reset
    fi
    start-tcpdump-data ${oai_role}
    start
    status
    return 0
}

# the output of start-tcpdump-data
add-to-datas "/root/data-${oai_role}.pcap"

####################
doc-nodes init "initializes clock after NTP, and tweaks MTU's"
function init() {

    git-pull-r2lab   # calls to git-pull-oai should be explicit from the caller if desired
    # clock
    init-ntp-clock
    # data interface if relevant
    [ "$oai_ifname" == data ] && echo Checking interface is up : $(turn-on-data)
#    echo "========== turning on offload negociations on ${oai_ifname}"
#    offload-on ${oai_ifname}
    echo "========== setting mtu to 9000 on interface ${oai_ifname}"
## To check if following is still useful today with new GTP
    ip link set dev ${oai_ifname} mtu 9000
}

####################
doc-nodes configure "configure function (requires define-peer)"
function configure() {
    configure-enb "$@"
}


doc-nodes configure-enb "configure eNodeB (requires define-peer)"
function configure-enb() {

    # pass peer id on the command line, or define it it with define-peer
    gw_id=$1; shift
    [ -z "$gw_id" ] && gw_id=$(get-peer)
    [ -z "$gw_id" ] && { echo "configure-enb: no peer defined - exiting"; return; }
    echo "ENB: Using gateway (EPC) on $gw_id"
    gw_id=$(echo $gw_id | sed  's/^0*//')
    id=$(r2lab-id)
    fitid=fit$id
    id=$(echo $id | sed  's/^0*//')
    cd $conf_dir


# Following setup should be used for the latest develop version
# choosing 50 for old devlop version double the uplink but with no downlink..
#
#s|N_RB_DL[ 	]*=.*|N_RB_DL = 50;|

    cat <<EOF > oai-enb.sed
s|pdsch_referenceSignalPower[ 	]*=.*|pdsch_referenceSignalPower = -24;|
s|mobile_network_code[ 	]*=.*|mobile_network_code = "95";|
s|downlink_frequency[ 	]*=.*|downlink_frequency = 2660000000L;|
s|N_RB_DL[ 	]*=.*|N_RB_DL = 25;|
s|rx_gain[ 	]*=.*|rx_gain = 125;|
s|pusch_p0_Nominal[ 	]*=.*|pusch_p0_Nominal = -90;|
s|pucch_p0_Nominal[ 	]*=.*|pucch_p0_Nominal = -96;|
s|mme_ip_address[ 	]*=.*|mme_ip_address = ( { ipv4 = "192.168.${oai_subnet}.$gw_id";|
s|ENB_INTERFACE_NAME_FOR_S1_MME[ 	]*=.*|ENB_INTERFACE_NAME_FOR_S1_MME = "${oai_ifname}";|
s|ENB_INTERFACE_NAME_FOR_S1U[ 	]*=.*|ENB_INTERFACE_NAME_FOR_S1U = "${oai_ifname}";|
s|ENB_IPV4_ADDRESS_FOR_S1_MME[ 	]*=.*|ENB_IPV4_ADDRESS_FOR_S1_MME = "192.168.${oai_subnet}.$id/24";|
s|ENB_IPV4_ADDRESS_FOR_S1U[ 	]*=.*|ENB_IPV4_ADDRESS_FOR_S1U = "192.168.${oai_subnet}.$id/24";|
EOF

    echo in $(pwd)
    sed -f oai-enb.sed < $template > $config
    echo "Overwrote $config in $(pwd)"
    cd - >& /dev/null
}

####################
doc-nodes start "starts lte-softmodem - run with -d to turn on soft oscilloscope" 
function start() {

    oscillo=""
    if [ -n "$1" ]; then
	case $1 in
	    -d) oscillo="-d" ;;
	    *) echo "usage: start [-d]"; return 1 ;;
	esac
    fi

    cd $run_dir
    echo "In $(pwd)"
    echo "Running lte-softmodem in background"
    ./lte-softmodem -P softmodem.pcap --ulsch-max-errors 100 -O $conf_dir/$config $oscillo >& $lte_log &
    cd - >& /dev/null
}

doc-nodes status "displays the status of the softmodem-related processes"
doc-nodes stop "stops the softmodem-related processes"

function -list-processes() {
    pids="$(pgrep lte-softmodem)"
    echo $pids
}

########################################
define-main "$0" "$BASH_SOURCE"
main "$@"
