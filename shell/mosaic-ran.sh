#!/bin/bash

source $(dirname $(readlink -f $BASH_SOURCE))/nodes.sh

doc-nodes-sep "#################### For managing a mosaic enode-B"

source $(dirname $(readlink -f $BASH_SOURCE))/mosaic-common.sh

### frontend:
# image: install stuff on top of a basic ubuntu image
# warm-up: make sure the USB is there, and similar
# configure: do at least once after restoring an image
# start: start services
# stop:
# journal: wrapper around journalctl for the 3 bundled services

### to test locally (adjust slicename if needed)
# apssh -g inria_oai@faraday.inria.fr -t root@fit01 -i nodes.sh -i r2labutils.sh -i mosaic-common.sh -s mosaic-ran.sh image


mosaic_role="ran"
mosaic_long="radio access network"


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
doc-nodes configure "configure RAN, i.e. tweaks e-nodeB config file - see --help"
function configure() {
    local nrb=50
    local USAGE="Usage: $FUNCNAME [options] cn-id
  options:
    -b nrb: sets NRB - default is $nrb (not yet implemented)"
    while getopts ":b" opt; do
        case $opt in
            b) nrb=$OPTARG;;
            *) echo -e "$USAGE"; return 1;;
        esac
    done
    shift $((OPTIND-1))

    [[ -z "$@" ]] && { echo -e "$USAGE"; return 1; }
    local cn_id=$1; shift
    [[ -n "$@" ]] && { echo -e "$USAGE"; return 1; }

    local r2lab_id=$(r2lab-id)
    local enbconf=$(oai-ran.enb-conf-get)

    echo "Configuring RAN on node $r2lab_id for CN on node $cn_id and nrb=$nrb"

    -sed-configurator $enbconf << EOF
s|mnc = [0-9]+;|mnc = 95;|
s|downlink_frequency\s*=.*;|downlink_frequency = 2660000000L;|
s|\(mme_ip_address.*ipv4.*=\).*|\1 "192.168.${mosaic_subnet}.${cn_id}";|
s|ENB_INTERFACE_NAME_FOR_S1_MME.*=.*"[^"]*";|ENB_INTERFACE_NAME_FOR_S1_MME = "${mosaic_ifname}";|
s|ENB_IPV4_ADDRESS_FOR_S1_MME.*=.*"[^"]*";|ENB_IPV4_ADDRESS_FOR_S1_MME = "192.168.${mosaic_subnet}.${r2lab_id}/24";|
s|ENB_INTERFACE_NAME_FOR_S1U.*=.*"[^"]*";|ENB_INTERFACE_NAME_FOR_S1U = "${mosaic_ifname}";|
s|ENB_IPV4_ADDRESS_FOR_S1U.*=.*"[^"]*";|ENB_IPV4_ADDRESS_FOR_S1U = "192.168.${mosaic_subnet}.${r2lab_id}/24";|
s|ENB_IPV4_ADDRESS_FOR_X2C.*=.*"[^"]*";|ENB_IPV4_ADDRESS_FOR_X2C = "192.168.${mosaic_subnet}.${r2lab_id}/24";|
EOF

}


###### running

doc-nodes warm-up "warm-ran: prepares enb - see --help"
function warm-up() {
    local USAGE="Usage: $FUNCNAME [-r]
  options:
    -r: causes the USB to be reset"

    local reset=true
    while getopts ":n" opt; do
        case "$opt" in
            r) reset="" ;;
            *) echo -e "$USAGE"; return 1;;
        esac
    done

    [[ -n "$@" ]] && { echo -e "$USAGE"; return 1; }

    echo "Warming up RAN, doing USB=$reset"
    stop
    status
    if node-has-b210; then
        # reset USB if required
        # note that the USB reset MUST be done at least once
        # after an image load
        [ -n "$reset" ] && { echo Resetting USB; usb-reset; sleep 5; } || echo "SKIPPING USB reset"
        # Load firmware on the B210 device
	    uhd_usrp_probe --init || {
            echo "WARNING: USRP B210 board could not be loaded - probably need a RESET"
            return 1
	    }
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

    while getopts ":xo" opt; do
        case $opt in
            x|o)
                graphical=true;;
            *)
                echo -e "$USAGE"; return 1;;
        esac
    done

    [[ -n "$@" ]] && { echo -e "$USAGE"; return 1; }
    turn-on-data
    if [ -n "$graphical" ]; then
        echo "e-nodeB with X11 graphical output not yet implemented - running in background instead for now"
        oai-ran.enb-start
    else
        oai-ran.enb-start
    fi
}

doc-nodes status "Stop RAN service(s)"
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

doc-nodes "cd into configuration directory for RAN service(s)"
function configure-directory() {
    local conf_dir=$(dirname $(oai-ran.enb-conf-get))
    cd $conf_dir
}

########################################
define-main "$0" "$BASH_SOURCE"
main "$@"
