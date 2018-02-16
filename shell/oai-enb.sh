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
conf_rf_limesdr=$OPENAIR_HOME/targets/ARCH/LMSSDR/LimeSDR_above_1p8GHz.ini
#following template name corresponds to the latest buggy develop version
#template=enb.band7.tm1.50PRB.usrpb210.conf
config=r2lab.conf
add-to-configs $conf_dir/$config
add-to-configs $conf_rf_limesdr

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
base_packages="git subversion libboost-all-dev libusb-1.0-0-dev python-mako doxygen python-docutils cmake build-essential libffi-dev texlive-base texlive-latex-base ghostscript gnuplot-x11 dh-apparmor graphviz gsfonts imagemagick-common  gdb ruby flex bison gfortran xterm mysql-common python-pip python-numpy qtcore4-l10n tcl tk xorg-sgml-doctools i7z g++ libpython-dev swig libsqlite3-dev libi2c-dev libwxgtk3.0-dev freeglut3-dev
"

doc-nodes base "the script to install base software on top of a raw image" 
function base() {

    git-pull-r2lab
    git-pull-oai

    # apt-get requirements
    apt-get update
    apt-get install -y $base_packages

    git-ssl-turn-off-verification

    # Build the LimeSDR environment
    # 1- Install SoapySDR
    echo "========== Install SoapySDR for LimeSDR"
    cd
    git clone https://github.com/pothosware/SoapySDR.git
    cd SoapySDR
    git pull origin master
    mkdir -p build 
    cd build
    cmake ..
    make -j4
    make install
    ldconfig 
    # 2- Install LimeSuite
    echo "========== Install LimeSuite for LimeSDR"
    cd
    git clone https://github.com/myriadrf/LimeSuite.git
    cd LimeSuite
    mkdir -p build 
    cd build
    cmake ..
    make -j4
    make install
    ldconfig
    cd ../udev-rules/
    chmod u+x install.sh
    ./install.sh 

    # following should be useless
    echo "========== Running git clone for r2lab and openinterface5g"
    cd
    [ -d openairinterface5g ] || git clone https://gitlab.eurecom.fr/oai/openairinterface5g.git
    [ -d /root/r2lab-embedded ] || git clone git@github.com:fit-r2lab/r2lab-embedded.git
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
    # old build from OAI, new one from Open Cell
    # run-in-log build-oai-1.log ./build_oai -I --eNB $oscillo --install-system-files -w USRP
    # run-in-log build-oai-2.log ./build_oai -w USRP $oscillo -c --eNB
    run-in-log build-oai-external.log ./build_oai -I --eNB $oscillo --install-system-files -w USRP
    run-in-log build-oai-limesdr.log ./build_oai -c -w LMSSDR $oscillo --eNB
    mv $run_dir/lte-softmodem $run_dir/lte-softmodem-limesdr
    run-in-log build-oai-usrp.log ./build_oai -c -w USRP $oscillo --eNB

}

########################################
# end of image
########################################

# entry point for global orchestration
doc-nodes run-enb "run-enb 23 50: does init/configure/start with epc running on node 23 and NRB=50"
function run-enb() {
    peer=$1; shift
    n_rb=$1; shift
    # pass exactly 'False' to skip usb-reset
    reset_usb=$1; shift
    oai_role=enb
    echo "run-enb args with limesdr: $limesdr and n_rb: $n_rb"
    stop
    status
    echo "run-enb: configure $peer"
    configure $peer $n_rb
    init
    if [ "$reset_usb" == "False" ]; then
	echo "SKIPPING USB reset"
    else
	usb-reset
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

    # pass peer id on the command line, or define it with define-peer
    # second argument may be NRB set by default to 25
    gw_id=$1; shift
    # if n_rb not specified as 2nd argument to configure, set it to 25 by default
    n_rb="${1:-25}"; shift
    [ -z "$n_rb" ] && { echo "configure-enb: NRB defined - exiting"; return; }
    [ -z "$gw_id" ] && gw_id=$(get-peer)
    [ -z "$gw_id" ] && { echo "configure-enb: no peer defined - exiting"; return; }
    echo "ENB: Using gateway (EPC) on $gw_id"
    gw_id=$(echo $gw_id | sed  's/^0*//')
    id=$(r2lab-id)
    fitid=fit$id
    id=$(echo $id | sed  's/^0*//')
    case $id in
	9|34) limesdr=true;;
	16|23) limesdr=false;;
	*) "ERROR in configure_enb: Cannot run eNB on $fitid node"; return ;;
    esac

    cd $conf_dir

    if [ "$limesdr" = true ]; then
	# Configure the LimeSDR device
	echo "LimeUtil --update"
	LimeUtil --update 
	if [ "$n_rb" -eq 25 ]; then
	    tx_gain=7
	    rx_gain=116
	    pdsch_referenceSignalPower=-34
	elif [ "$n_rb" -eq 50 ]; then
	    tx_gain=20
	    rx_gain=116
	    pdsch_referenceSignalPower=-35
        else
	    echo "ERROR in configure_enb: NRB=$n_rb with LimeSDR"
	    return
	fi
    else
	# We use default USRP B210 at eNB
	if [ "$n_rb" -eq 25 ]; then
            tx_gain=90
            rx_gain=125
            pdsch_referenceSignalPower=-24
        elif [ "$n_rb" -eq 50 ]; then
            tx_gain=90
            rx_gain=120
            pdsch_referenceSignalPower=-27
        else
            echo "ERROR in configure_enb: NRB=$n_rb with USRP B210"
	    return
        fi
    fi
    

# Following setup should be used for the latest develop version
# choosing 50 for old develop version double the uplink but with no downlink..
#
#s|N_RB_DL[ 	]*=.*|N_RB_DL = 50;|

    cat <<EOF > oai-enb.sed
s|pdsch_referenceSignalPower[ 	]*=.*|pdsch_referenceSignalPower = ${pdsch_referenceSignalPower};|
s|mobile_network_code[ 	]*=.*|mobile_network_code = "95";|
s|downlink_frequency[ 	]*=.*|downlink_frequency = 2660000000L;|
s|N_RB_DL[ 	]*=.*|N_RB_DL = ${n_rb};|
s|tx_gain[ 	]*=.*|tx_gain = ${tx_gain};|
s|rx_gain[ 	]*=.*|rx_gain = ${rx_gain};|
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
doc-nodes start "starts lte-softmodem with usrp or limesdr depending on fit node - run with -d to turn on soft oscilloscope" 
function start() {

    id=$(r2lab-id)
    fitid=fit$id
    id=$(echo $id | sed  's/^0*//')
    case $id in
	9|34) limesdr=true;;
	16|23) limesdr=false;;
	*) "ERROR in start: Cannot run eNB on $fitid node"; exit 1;;
    esac

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
    if [ $limesdr = true ] ; then
	echo "./lte-softmodem-limesdr -P softmodem.pcap -O $conf_dir/$config $oscillo --rf-config-file $conf_rf_limesdr >& $lte_log &"
	./lte-softmodem-limesdr -P softmodem.pcap -O $conf_dir/$config $oscillo --rf-config-file $conf_rf_limesdr >& $lte_log &
    else
	echo "./lte-softmodem -P softmodem.pcap --ulsch-max-errors 100 -O $conf_dir/$config $oscillo >& $lte_log &"
	./lte-softmodem -P softmodem.pcap --ulsch-max-errors 100 -O $conf_dir/$config $oscillo >& $lte_log &
    fi
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
