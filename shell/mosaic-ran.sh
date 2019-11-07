#!/bin/bash

_sourced_mosaic_ran=true

[ -z "$_sourced_nodes" ] && source $(dirname $(readlink -f $BASH_SOURCE))/nodes.sh

doc-nodes-sep "#################### For managing a mosaic enode-B"

[ -z "$_sourced_mosaic_common" ] && source $(dirname $(readlink -f $BASH_SOURCE))/mosaic-common.sh

### frontend:
# image: install stuff on top of a basic ubuntu image
# warm-up: make sure the USB is there, and similar
# configure: do at least once after restoring an image
#
# start: start services
# stop:
# status
#
# journal: wrapper around journalctl for the 3 bundled services
# config-dir: echo's the configuration directory
# inspect-config-changes: show everything changed from the snap configs

### to test locally (adjust slicename if needed)
# apssh -g inria_oai@faraday.inria.fr -t root@fit01 -i nodes.sh -i r2labutils.sh -i mosaic-common.sh -s mosaic-ran.sh image


mosaic_role="ran"
mosaic_long="radio access network"

add-filecommand-to-configs oai-ran.enb-conf-get

###### imaging
doc-nodes image "frontend for rebuilding this image"
function image() {
    dependencies-for-radio-access-network
    install-uhd-images
    install-radio-access-network
    mosaic-as-ran
}

function dependencies-for-radio-access-network() {
    git-pull-r2lab
    apt-get update
    apt-get install -y emacs
}

function install-uhd-images() {
    apt-get install -y uhd-host
    /usr/lib/uhd/utils/uhd_images_downloader.py >& /root/uhd_images_downloaded.log
}

function install-radio-access-network() {
    -snap-install oai-ran
    oai-ran.stop-all
}


###### configuring
# nrb business : see oai-enb.sh for details

doc-nodes config-dir "echo the location of the configuration dir"
function config-dir() {
    (cd /var/snap/oai-ran/current; pwd -P)
}

doc-nodes inspect-config-changes "show all changes done by configure"
function inspect-config-changes() {
    -inspect-config-changes $(config-dir);
}


doc-nodes configure "configure RAN, i.e. tweaks e-nodeB config file - see --help"
function configure() {
    local nrb=50
    local USAGE="Usage: $FUNCNAME [options] cn-id
  options:
    -b nrb: sets NRB - default is $nrb"
    OPTIND=1
    while getopts "b:" opt; do
        case $opt in
            b) nrb=$OPTARG;;
            *) echo -e "$USAGE"; return 1;;
        esac
    done
    shift $((OPTIND-1))

    [[ -z "$@" ]] && { echo -e "$USAGE"; return 1; }
    local cn_id=$1; shift
    [[ -n "$@" ]] && { echo -e "$USAGE"; return 1; }

    local r2lab_id=$(r2lab-id -s)
    local enbconf=$(oai-ran.enb-conf-get)

    echo "Configuring RAN on node $r2lab_id for CN on node $cn_id and nrb=$nrb"
    case $nrb in
	25) refSignalPower=-24; puSch10xSnr=100; puCch10xSnr=100;;
	50) refSignalPower=-27; puSch10xSnr=160; puCch10xSnr=160;;
        *) echo -e "Bad N_RB_DL value $nrb"; return 1;;
    esac

#s|max_rxgain\s*=.*;|max_rxgain = 125;| /* default value but generates too high I0 value */

    -sed-configurator $enbconf << EOF
s|mnc\s*=\s*[0-9][0-9]*|mnc = 95|
s|downlink_frequency\s*=.*;|downlink_frequency = 2660000000L;|
s|N_RB_DL\s*=.*|N_RB_DL = ${nrb};|
s|tx_gain\s*=.*;|tx_gain = 100;|
s|rx_gain\s*=.*;|rx_gain = 125;|
s|pdsch_referenceSignalPower\s*=.*;|pdsch_referenceSignalPower = ${refSignalPower};|
s|pusch_p0_Nominal\s*=.*;|pusch_p0_Nominal = -90;|
s|pucch_p0_Nominal\s*=.*;|pucch_p0_Nominal = -96;|
s|puSch10xSnr\s*=.*;|puSch10xSnr = ${puSch10xSnr};|
s|puCch10xSnr\s*=.*;|puCch10xSnr = ${puCch10xSnr};|
s|max_rxgain\s*=.*;|max_rxgain = 120;|
s|\(mme_ip_address.*ipv4.*=\).*|\1 "192.168.${mosaic_subnet}.${cn_id}";|
s|ENB_INTERFACE_NAME_FOR_S1_MME.*=.*"[^"]*";|ENB_INTERFACE_NAME_FOR_S1_MME = "${mosaic_ifname}";|
s|ENB_IPV4_ADDRESS_FOR_S1_MME.*=.*"[^"]*";|ENB_IPV4_ADDRESS_FOR_S1_MME = "192.168.${mosaic_subnet}.${r2lab_id}/24";|
s|ENB_INTERFACE_NAME_FOR_S1U.*=.*"[^"]*";|ENB_INTERFACE_NAME_FOR_S1U = "${mosaic_ifname}";|
s|ENB_IPV4_ADDRESS_FOR_S1U.*=.*"[^"]*";|ENB_IPV4_ADDRESS_FOR_S1U = "192.168.${mosaic_subnet}.${r2lab_id}/24";|
s|ENB_IPV4_ADDRESS_FOR_X2C.*=.*"[^"]*";|ENB_IPV4_ADDRESS_FOR_X2C = "192.168.${mosaic_subnet}.${r2lab_id}/24";|
s|parallel_config\s*=.*;|parallel_config = "PARALLEL_SINGLE_THREAD";|
EOF

}


###### running

doc-nodes wait-usrp "Wait until a USRP is ready - optional timeout in seconds"
function wait-usrp() {
    timeout="$1"; shift
    [ -z "$timeout" ] && timeout=
    counter=1
    while true; do
        if uhd_find_devices >& /dev/null; then
            uhd_usrp_probe >& /dev/null && return 0
        fi
        counter=$(($counter + 1))
        [ -z "$timeout" ] && continue
        if [ "$counter" -ge $timeout ] ; then
            echo "Could not find a UHD device after $timeout seconds"
            return 1
        fi
    done
}

doc-nodes node-has-b210 "Check if a USRP B210 is attached to the node"
function node-has-b210() {
    type uhd_find_devices >& /dev/null || {
        echo "you need to install uhd_find_devices"; return 1;}
    uhd_find_devices 2>&1 | grep -q B210
}

doc-nodes node-has-b205 "Check if a USRP B205 is attached to the node"
function node-has-b205() {
    type uhd_find_devices >& /dev/null || {
	echo "you need to install uhd_find_devices"; return 1;}
    uhd_find_devices 2>&1 | grep -q B205
}

doc-nodes node-has-limesdr "Check if a LimeSDR is attached to the node"
function node-has-limesdr() {
    ls /usr/local/bin/LimeUtil >& /dev/null || {
        echo "you need to install LimeUtil"; return 1;}
    [ -n "$(/usr/local/bin/LimeUtil --find)" ]
}

doc-nodes warm-up "Prepare SDR board (b210 or lime) for running an enb - see --help"
function warm-up() {
    local USAGE="Usage: $FUNCNAME [-u]
  options:
    -u: causes the USB to be reset"

    local reset=""
    OPTIND=1
    while getopts "u" opt -u; do
        case $opt in
            u) reset=true ;;
            *) echo -e "$USAGE"; return 1;;
        esac
    done
    shift $((OPTIND-1))

    [[ -n "$@" ]] && { echo -e "$USAGE"; return 1; }

    # that's the best moment to do that
    echo "Checking interface is up : $(turn-on-data)"
    echo "Increase data interface's MTU: $(increase-data-mtu)"

    # stopping enb service in case of a lingering instance
    echo -n "ENB service ... "
    echo -n "stopping ... "
    stop > /dev/null
    echo -n "status ... "
    status
    echo

    echo -n "Warming up RAN ... "
    # focusing on b210 for this first version
    if [ -n "$reset" ]; then
        echo -n "USB off (reset requested) ... "
        usb-off >& /dev/null
    fi
    # this is required b/c otherwise node-has-b210 won't find anything
    echo -n "USB on ... "
    usb-on >& /dev/null
    delay=3
    echo -n "Sleeping $delay "
    sleep $delay
    echo Done
    echo ""

    if node-has-b210; then
        if [ -z "$reset" ]; then
            echo "B210 left alone (reset not requested)"
        else
            uhd_find_devices >& /dev/null
            echo "Loading b200 image..."
            # this was an attempt at becoming ahead of ourselves
            # by pre-loading the right OAI image at this earlier point
            # it's not clear that it is helping, as enb seems to
            # unconditionnally load the same stuff again, no matter what
            uhd_image_loader --args="type=b200" \
             --fw-path /snap/oai-ran/current/uhd_images/usrp_b200_fw.hex \
             --fpga-path /snap/oai-ran/current/uhd_images/usrp_b200_fpga.bin || {
                echo "WARNING: USRP B210 board could not be loaded - probably need a RESET"
                return 1
    	    }
            echo "B210 ready"
        fi
    elif node-has-b205; then
	if [ -z "$reset" ]; then
	    echo "B205 left alone (reset not requested)"
	else
	    uhd_find_devices >& /dev/null
	    echo "Loading b205 image..."
            # this was an attempt at becoming ahead of ourselves
            # by pre-loading the right OAI image at this earlier point
            # it's not clear that it is helping, as enb seems to
            # unconditionnally load the same stuff again, no matter what
	    uhd_image_loader --args="type=b200" \
		--fw-path /snap/oai-ran/current/uhd_images/usrp_b200_fw.hex \
		--fpga-path /snap/oai-ran/current/uhd_images/usrp_b205mini_fpga.bin || {
		echo "WARNING: USRP B205 board could not be loaded - probably need a RESET"
		return 1
	    }
	    echo "B205 ready"
	fi
    elif node-has-limesdr; then
	    # Load firmware on the LimeSDR device
	    echo "Running LimeUtil --update"
	    LimeUtil --update
        [ -n "$reset" ] && { echo Resetting USB; usb-reset; } || echo "SKIPPING USB reset"
    else
	    echo "WARNING: Neither B210 nor LimeSDR device attached to the eNB node!"
	    return 1
    fi
}

doc-nodes start "Start RAN a.k.a. e-nodeB; option -x means graphical - requires X11-enabled ssh session"
function start() {
    local USAGE="Usage: $FUNCNAME [options]
  options:
    -x: start in graphical mode (or -o for compat)"

    local graphical=""
    local tracer=""
    local enb_opt=""

    OPTIND=1
    while getopts "Txo" opt; do
        case $opt in
            x|o)
                graphical=true;;
	    T)
		tracer=true;;
            *)
                echo -e "$USAGE"; return 1;;
        esac
    done
    shift $((OPTIND-1))

    [[ -n "$@" ]] && { echo -e "$USAGE"; return 1; }
    echo "Checking interface is up : $(turn-on-data)"

    echo "Show r2lab conf before running the eNB"
    oai-ran.enb-conf-show

    if [ -n "$graphical" ]; then
        echo "e-nodeB with X11 graphical output not yet implemented - running in background instead for now"
        enb_opt+=""
    fi
    if [ -n "$tracer" ]; then
        echo "run eNB with tracer option"
        enb_opt+=" --T_stdout 0"
    fi
    oai-ran.enb-start $enb_opt
}

doc-nodes stop "Stop RAN service(s)"
function stop() {
    oai-ran.enb-stop
}

doc-nodes status "Displays status of RAN service(s)"
function status() {
    oai-ran.enb-status
}

doc-nodes journal "Wrapper around journalctl about RAN service(s) - use with -f to follow up"
function journal() {
    units="snap.oai-ran.enbd.service"
    jopts=""
    for unit in $units; do jopts="$jopts --unit $unit"; done
    journalctl $jopts "$@"
}

add-command-to-logs 'journalctl --unit=snap.oai-ran.enbd.service -b'

doc-nodes configure-directory "cd into configuration directory for RAN service(s)"
function configure-directory() {
    local conf_dir=$(dirname $(oai-ran.enb-conf-get))
    cd $conf_dir
}

########################################
define-main "$0" "$BASH_SOURCE"
main "$@"
