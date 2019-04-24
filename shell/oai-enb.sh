#!/bin/bash

[ -z "$_sourced_nodes" ] && source $(dirname $(readlink -f $BASH_SOURCE))/nodes.sh

doc-nodes-sep "#################### For managing an OAI enodeb"

[ -z "$_sourced_oai_common" ] && source $(dirname $(readlink -f $BASH_SOURCE))/oai-common.sh

# WARNING WITH LATEST DEVELOP VERSION, -P OPTION CRASHES SYSTEMATICALLY
# set this to non-void to enable pcap saving with lte-softmodem -P
# warning, this seems to crash with recent versions
SAVE_PCAP=

OPENAIR_HOME=/root/openairinterface5g
build_dir=$OPENAIR_HOME/cmake_targets
up_run_dir=$build_dir/lte_build_oai
run_dir=$up_run_dir/build
lte_log="$run_dir/softmodem.log"
add-to-logs $lte_log
lte_pcap="$run_dir/softmodem.pcap"
[ -n "$SAVE_PCAP" ] && add-to-datas $lte_pcap
# the output of start-tcpdump-data
add-to-datas "/root/data-${oai_role}.pcap"

conf_dir=$OPENAIR_HOME/targets/PROJECTS/GENERIC-LTE-EPC/CONF
template=enb.band7.tm1.usrpb210.conf
#following template name corresponds to the latest buggy develop version
#template=enb.band7.tm1.50PRB.usrpb210.conf
#conf_rf_limesdr=$OPENAIR_HOME/targets/ARCH/LMSSDR/LimeSDR_above_1p8GHz.ini
conf_rf_limesdr=$OPENAIR_HOME/targets/ARCH/LMSSDR/LimeSDR_above_1p8GHz_1v4.ini
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
doc-nodes image "the entry point for nightly eNB image builds"
function image() {
    dumpvars
    base
    build usrp
    echo "image: build lte-softmodem for USRP"
    mv $run_dir $up_run_dir/build_usrp
    echo "image: build lte-softmodem for LimeSDR"
    build limesdr
    mv $run_dir $up_run_dir/build_limesdr
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

    # following should be useless
    echo "========== Running git clone for r2lab and openinterface5g"
    cd
    [ -d openairinterface5g ] || git clone https://gitlab.eurecom.fr/oai/openairinterface5g.git
    [ -d /root/r2lab-embedded ] || git clone https://github.com/fit-r2lab/r2lab-embedded.git
}


doc-nodes build "builds lte-softmodem for an oai image for USRP or for LimeSDR with option limesdr"
function build() {

    sdr="${1:-usrp}"; shift
    case $sdr in
	"usrp") SDR_DEV="USRP" ;;
	"limesdr") SDR_DEV="LMSSDR"; build-limesdr-env ;;
	*) echo "image: Error unknown sdr device $sdr"; return 1 ;;
    esac

    # following updates may be useful in case build is run in standalone
    git-pull-r2lab
    git-pull-oai

    cd $build_dir
    echo Building OAI5G - see $build_dir/build-oai5g.log
    build-oai5g $SDR_DEV >& build-oai5g.log

}


doc-nodes build-limesdr-env "builds the LimeSDR environment"
function build-limesdr-env() {

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

}


doc-nodes build-oai5g "builds lte-softmodem by default for USRP or for LimeSDR with option LMSSDR "
function build-oai5g() {

    SDR_DEV="${1:-USRP}"; shift

    cd $OPENAIR_HOME
    source oaienv
    source $HOME/.bashrc

    cd $build_dir

    #Run the build by default with oscillo function enabled (option -x). Use -d option to enable it when running.
    echo Building lte-softmodem for $SDR_DEV in $(pwd) - see 'build*log'
    run-in-log build-oai-external.log ./build_oai -I --eNB -x --install-system-files -w $SDR_DEV
    run-in-log build-oai-usrp.log ./build_oai -c -w $SDR_DEV -x --eNB

}

########################################
# end of image
########################################

# entry points for global orchestration
doc-nodes warm-enb "warm-enb 23 50 False: does init/configure with epc running on node 23, with NRB=50, without USB reset"
function warm-enb() {
    peer=$1; shift
    n_rb=$1; shift
    # pass exactly 'False' to skip usb-reset
    reset_usb=$1; shift
    oai_role=enb
    echo "warm-enb running with n_rb set to $n_rb"
    init
    stop
    status
    echo "warm-enb: configure eNB with EPC running on $peer"
    configure $peer $n_rb
    if node-has-b210; then
        # reset USB if required
        # note that the USB reset MUST be done at least once
        # after an image load
	if [ "$reset_usb" == "False" ]; then
	    echo "SKIPPING USB reset"
	else
	    echo "Resetting USB port of eNB node $peer"
	    usb-reset
	fi
        # Load firmware on the B210 device
	uhd_usrp_probe --init || {
            echo "WARNING: USRP B210 board could not be loaded - probably need a RESET"
            return 1
	}
    elif node-has-limesdr; then
	# Load firmware on the LimeSDR device
	echo "Run LimeUtil --update and reset the LimeSDR device to reconnect to"
	LimeUtil --update
	usb-reset # reset mandatory after a load
	sleep 10 # LimeSDR is slow to restart
    else
	echo "WARNING: Neither B210 nor LimeSDR device attached to the eNB node!"
	return 1
    fi
}

doc-nodes run-enb "run-enb True: does start with the oscillo option set"
function run-enb() {
    oscillo=$1; shift

    echo running tcpdump on the data interface
    start-tcpdump-data ${oai_role}
    if [ "$oscillo" == "True" ]; then
        echo "start eNB in foreground with oscillo function through X11"
	start -d
    else
        echo "start eNB in background"
	start
    fi
    status
    return 0
}


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
    id=$(echo $id | sed  's/^0*//')

    cd $conf_dir

    if node-has-limesdr; then
	# eNB with LimeSDR scenario
	# set the $run_dir directory to $up_run-dir/build_limesdr
	rm -f $up_run_dir/build; ln -s $up_run_dir/build_limesdr $up_run_dir/build

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
    elif node-has-b210; then
	# eNB with usrp B210 scenario
	# set the $run_dir directory to $up_run-dir/build_usrp
	rm -f $up_run_dir/build; ln -s $up_run_dir/build_usrp $up_run_dir/build
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
    else
	echo "WARNING: Neither B210 nor LimeSDR device attached to the eNB node!"
	return 1
    fi

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
    id=$(echo $id | sed  's/^0*//')
    oscillo=""
    if [ -n "$1" ]; then
	case $1 in
	    -d) oscillo="-d" ;;
	    *) echo "usage: start [-d]"; return 1 ;;
	esac
    fi

    cd $run_dir
    echo "In $(pwd); running lte-softmodem in background"
    command="./lte-softmodem -O $conf_dir/$config"
    if [ -n "$SAVE_PCAP" ]; then
            command="$command -P softmodem.pcap"
    fi
    if node-has-limesdr ; then
        command="$command --rf-config-file $conf_rf_limesdr"
    else
        command="$command --ulsch-max-errors 100"
    fi
    if [ -z "$oscillo" ]; then
        # without graphical mode: run in background
        DETACH=true
    else
        # with graphical mode, run in foreground otherwise
        # the ssh session closes and we cannot forward the X11 traffic
        DETACH=
        command="$command $oscillo"
    fi
    echo "Starting base station with command (DETACH=$DETACH)"
    echo "$command"
    if [ -n "$DETACH" ]; then
        $command >& $lte_log &
    else
        $command >& $lte_log
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
