#!/bin/bash

source $(dirname $(readlink -f $BASH_SOURCE))/nodes.sh

doc-nodes-sep "#################### For managing an OAI UE"

source $(dirname $(readlink -f $BASH_SOURCE))/oai-common.sh

OPENAIR_DIR=/root/openairinterface5g
run_dir=$OPENAIR_DIR/targets/bin 
build_dir=$OPENAIR_DIR/cmake_targets
tools_dir=$OPENAIR_DIR/cmake_targets/tools/
lte_log="$run_dir/softmodem-ue.log"
add-to-logs $lte_log
lte_pcap="$run_dir/softmodem-ue.pcap"
add-to-datas $lte_pcap
conf_dir=$OPENAIR_DIR/openair3/NAS/TOOLS
template=ue_eurecom_test_sfr.conf
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
base_packages="git subversion libboost-all-dev libusb-1.0-0-dev python-mako doxygen python-docutils cmake build-essential libffi-dev
texlive-base texlive-latex-base ghostscript gnuplot-x11 dh-apparmor graphviz gsfonts imagemagick-common 
 gdb ruby flex bison gfortran xterm mysql-common python-pip python-numpy qtcore4-l10n tcl tk xorg-sgml-doctools
"

doc-nodes base "the script to install base software on top of a raw image" 
function base() {

    git-pull-r2lab
    git-pull-oai

    # apt-get requirements
    apt-get update
    apt-get install -y $base_packages

    # 
    git-ssl-turn-off-verification

    echo "========== Running git clone for r2lab and openinterface5g"
    cd

    [ -d openairinterface5g ] || git clone https://gitlab.eurecom.fr/oai/openairinterface5g.git
    [ -d /root/r2lab ] || git clone https://github.com/parmentelat/r2lab.git

}

doc-nodes build "builds oai5g for an oai image"
function build() {

    git-pull-r2lab
    git-pull-oai

    cd
    echo Building OAI5G - see $HOME/build-oai5g-ue.log
    build-oai5g -x >& build-oai5g-ue.log
}

doc-nodes build-oai5g "builds oai5g UE - run with -x for building with software oscilloscope" 
function build-oai5g() {

    oscillo=""
    if [ -n "$1" ]; then
	case $1 in
	    -x) oscillo="-x" ;;
	    *) echo "usage: build-oai5g [-x]"; return 1 ;;
	esac
    fi

    # Set OAI environment variables
    cd $OPENAIR_DIR
    source oaienv

    source $HOME/.bashrc

# following is no more required as init_nas_s1 is part of openairinterface5g
#    cd $run_dir
#    # Retrieve init_nas_s1 script from following URL
#    wget https://gitlab.eurecom.fr/oai/openairinterface5g/wikis/HowToConnectOAIENBWithOAIUEWithS1Interface/init_nas_s1
#
#    # Modify the OPENAIR_DIR variable to /root/openairinterface5g in this file
#    cat <<EOF > init_nas_s1.sed
#s|OPENAIR_DIR=.*|OPENAIR_DIR=/root/openairinterface5g|
#EOF
#    sed -i -f init_nas_s1.sed init_nas_s1
#    echo "Set OPENAIR_DIR variable in init_nas_s1 in $(pwd)"

    # make following script runnable
    chmod a+x $tools_dir/init_nas_s1

    cd $build_dir

    # Set LINUX and PDCP_USE_NETLINK variables in CMakeLists.txt
    cat <<EOF > cmakelists.sed
s|add_boolean_option(LINUX                   False.*|add_boolean_option(LINUX                   True "used in weird memcpy() in pdcp.c ???")|
s|add_boolean_option(PDCP_USE_NETLINK            False.*|add_boolean_option(PDCP_USE_NETLINK            True "For eNB, PDCP communicate with a NETLINK socket if connected to network driver, else could use a RT-FIFO")|
EOF
    sed -i -f cmakelists.sed CMakeLists.txt
    echo "Set LINUX and PDCP_USE_NETLINK variables in CMakeLists.txt at $(pwd)"

    echo Building in $(pwd) - see 'build*log'
    run-in-log build-oai-ue-1.log ./build_oai -I --eNB $oscillo --install-system-files -w USRP

}

########################################
# end of image
########################################

# entry point for global orchestration
# There is no need of configure since there is no peer
doc-nodes run-oai "run-oai: does init/start"
function run-oai() {
    oai_role=ue
    stop
    status
    init
    start-tcpdump-data ${oai_role}
    start
    status
    return 0
}

# the output of start-tcpdump-data
add-to-datas "/root/data-${oai_role}.pcap"

####################
doc-nodes init "initializes clock after NTP"
function init() {

    git-pull-r2lab   # calls to git-pull-oai should be explicit from the caller if desired
    # clock
    init-ntp-clock
    # data interface if relevant
#    [ "$oai_ifname" == data ] && echo Checking interface is up : $(turn-on-data)
#    echo "========== turning on offload negociations on ${oai_ifname}"
#    offload-on ${oai_ifname}
#    echo "========== setting mtu to 9000 on interface ${oai_ifname}"
## To check if following is still useful today with new GTP
#    ip link set dev ${oai_ifname} mtu 9000
}

####################
function configure() {
    configure-ue "$@"
}
doc-nodes configure "function"

function configure-ue() {

    # pass peer id on the command line, or define it with define-peer
    # gw_id=$1; shift

    echo "in UE configuration"

    git-pull-r2lab   # calls to git-pull-oai should be explicit from the caller if desired
    cd $conf_dir

    cat <<EOF > oai-ue.sed
s|MNC="93";|MNC="95";|
s|MSIN=.*|MSIN="0000000003";|
s|OPC=.*|OPC="8E27B6AF0E692E750F32667A3B14605D";|
s|HPLMN=.*|HPLMN= "20893";|
s|"20893"|"20895"|
EOF
    echo in $(pwd)
    sed -i -f oai-ue.sed $template 
    echo "Adapt $template to R2lab in $(pwd)"
    
    # Set OAI environment variables
    cd $OPENAIR_DIR
    source oaienv
    cd - >& /dev/null

    source $HOME/.bashrc

    # then build
    cd $build_dir
    run-in-log build-oai-ue-2.log ./build_oai -w USRP -x -c --UE

    # load the ue_ip module and sets up IP for the UE
    $tools_dir/init_nas_s1 UE
}
doc-nodes configure-ue "configure UE (no need of define-peer but later maybe add fake SIM number)"

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

    cd - >& /dev/null
    cd $run_dir
    echo "in $(pwd)"
    echo "Running lte-softmodem UE mode in background see logs at $lte_ue_log"
    ./lte-softmodem.Rel14 -U -C2660000000 -r25 --ue-scan-carrier --ue-txgain 100 --ue-rxgain 120 $oscillo >& $lte_log &
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
