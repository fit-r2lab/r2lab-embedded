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
doc-nodes configure "configure ran - expects CN id"
function configure() {
    local cn_id=$1; shift
    configure-radio-access-network $cn_id
}

doc-nodes configure-radio-access-network "tweaks e-nodeB config file"
function configure-radio-access-network() {
    local cn_id=$1; shift
    local r2lab_id=$(r2lab-id)

    -enable-snap-bins
    local enbconf=$(oai-ran.enb-conf-get)

    -sed-configurator $enbconf << EOF
s|mnc = [0-9]+;|mnc = 95;|
s|downlink_frequency\s*=.*;|downlink_frequency = 2660000000L|
s|\(mme_ip_address.*ipv4.*=\).*|\1 "192.168.2.${cn}";"|
s|ENB_INTERFACE_NAME_FOR_S1_MME.*=.*"[^"]*";|ENB_INTERFACE_NAME_FOR_S1_MME = "data";|
s|ENB_IPV4_ADDRESS_FOR_S1_MME.*=.*"[^"]*";|ENB_IPV4_ADDRESS_FOR_S1_MME = "192.168.2.${r2lab_id}/24";|
s|ENB_INTERFACE_NAME_FOR_S1U.*=.*"[^"]*";|ENB_INTERFACE_NAME_FOR_S1U = "data";|
s|ENB_IPV4_ADDRESS_FOR_S1U.*=.*"[^"]*";|ENB_IPV4_ADDRESS_FOR_S1U = "192.168.2.${r2lab_id}/24";|
s|ENB_IPV4_ADDRESS_FOR_X2C.*=.*"[^"]*";|ENB_IPV4_ADDRESS_FOR_X2C = "192.168.2.${r2lab_id}/24";|
EOF

}


###### running
doc-nodes start-graphical "Start e-nodeB with an X11 UI - requires ssh session with X11 forwarding"
function start-graphical() {
    local oscillo=$1; shift
    [ -z "$oscillo" ] && oscillo=false

    turn-on-data
    -enable-snap-bins
    case "$oscillo" in
        *alse)
            oai-ran.enb-start ;;
        *)
            echo "e-nodeB qith X11 graphical output not yet implemented"
            oai-ran.enb-start ;;
    esac
}

function start() {
    turn-on-data
    -enable-snap-bins
    oai-ran.enb-start
}

function stop() {
    -enable-snap-bins
    oai-ran.enb-stop
}

function status() {
    -enable-snap-bins
    oai-ran.enb-status
}

# this form allows to run with the -f option
function journal() {
    units="snap.oai-ran.enbd.service"
    jopts=""
    for unit in $units; do jopts="$jopts --unit $unit"; done
    journalctl $jopts "$@"
}

########################################
define-main "$0" "$BASH_SOURCE"
main "$@"
