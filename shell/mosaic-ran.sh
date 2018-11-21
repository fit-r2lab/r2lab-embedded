#!/bin/bash

source $(dirname $(readlink -f $BASH_SOURCE))/nodes.sh

doc-nodes-sep "#################### For managing a mosaic enode-B"

source $(dirname $(readlink -f $BASH_SOURCE))/mosaic-common.sh

### frontend:
# image: install stuff on top of a basic ubuntu image
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
    install-radio-access-network
    mosaic-as-ran
}

function dependencies-for-radio-access-network() {
    git-pull-r2lab
    apt-get update
    apt-get install -y emacs
    apt-get install -y uhd-host
    /usr/lib/uhd/utils/uhd_images_downloader.py
}

function install-radio-access-network() {
    -snap-install oai-ran
    # just in case
    -enable-snap-bins
    oai-ran.stop-all
}


###### configuring
doc-nodes configure "configure RAN, i.e. tweaks e-nodeB config file - expects 1 arg: CN-id"
function configure() {
    local cn_id=$1; shift
    [ -n "$cn_id" ] || { echo Usage: $FUNCNAME CN-id; return 1; }

    local r2lab_id=$(r2lab-id)

    -enable-snap-bins
    local enbconf=$(oai-ran.enb-conf-get)

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
doc-nodes start "Start RAN a.k.a. e-nodeB; option -x means graphical (requires X11-enabled ssh session); option -n means avoid resetting USB"
function start() {
    local USAGE="$Usage: FUNCNAME [options]
  options:
    -x: start in graphical mode (or -o for compat)
    -n: don't reset USB"

    local graphical=""
    local reset="true"

    while getopts ":rxo" opt; do
        case $opt in
            x|o)
                graphical=true;;
            n)
                reset="";;
            *)
                echo "USAGE"; return 1;;
        esac
    done

    -enable-snap-bins

    turn-on-data
    [ -n "$reset" ] && { echo "Resetting USB"; usb-reset; }
    if [ -n "$graphical" ]; then
        echo "e-nodeB with X11 graphical output not yet implemented - running in background instead for now"
        oai-ran.enb-start
    else
        oai-ran.enb-start
    fi
}

doc-nodes status "Stop RAN service(s)"
function stop() {
    -enable-snap-bins
    oai-ran.enb-stop
}

doc-nodes status "Displays status of RAN service(s)"
function status() {
    -enable-snap-bins
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
