#!/bin/bash

_sourced_mosaic_oai_ue=true

[ -z "$_sourced_nodes" ] && source $(dirname $(readlink -f $BASH_SOURCE))/nodes.sh

doc-nodes-sep "#################### For managing a Mosaic snap for OAI UE"

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
# apssh -g mosaic_oai@faraday.inria.fr -t root@fit01 -i nodes.sh -i r2labutils.sh -i mosaic-common.sh -s mosaic-oai-ue.sh image


mosaic_role="oai-ue"
mosaic_long="OAI User Equipment"

add-filecommand-to-configs oai-ue.usim-get
add-filecommand-to-configs oai-ue.ue-cmd-get

###### imaging
doc-nodes image "frontend for rebuilding this image"
function image() {
    dependencies-for-oai-ue
    install-uhd-images
    install-oai-ue
    mosaic-as-oai-ue
}

function dependencies-for-oai-ue() {
    git-pull-r2lab
    apt-get update
    apt-get install -y libelf-dev emacs
}

function install-uhd-images() {
    apt-get install -y uhd-host
    /usr/lib/uhd/utils/uhd_images_downloader.py >& /root/uhd_images_downloaded.log
}

function install-oai-ue() {
    -snap-install oai-ue
    oai-ue.ue-stop
    # Compile the OAI UE_IP module
    local conf_dir=$(dirname $(oai-ue.ue-conf-get))
    conf_dir=$(echo ${conf_dir//var/root})
    echo "compiling OAI UE_IP in ${conf_dir}/ue_ip"
    cd ${conf_dir}/ue_ip; pwd; make; ./oip add ./ue_ip.ko; cd -
}


###### configuring
# nrb business : see oai-enb.sh for details

doc-nodes config-dir "echo the location of the configuration dir"
function config-dir() {
    (cd /var/snap/oai-ue/current; pwd -P)
}

doc-nodes inspect-config-changes "show all changes done by configure"
function inspect-config-changes() {
    -inspect-config-changes $(config-dir);
}


doc-nodes configure "configure oai-ue, i.e. tweaks OAI UE config file - see --help"
function configure() {
    local nrb=50
    local rxgain=110
    local txgain=15
    local maxpower=0
    local USAGE="Usage: $FUNCNAME [options]
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
    [[ -n "$@" ]] && { echo -e "$USAGE"; return 1; }

    local r2lab_id=$(r2lab-id -s)
    local ue_args_cmd=$(oai-ue.ue-cmd-get)
    local usim_conf=$(oai-ue.usim-get)

    case $r2lab_id in
        06) msin="0000000003";
            case $nrb in
                  25) rxgain=125; txgain=1; maxpower=-6;;
                  50) rxgain=127; txgain=1; maxpower=-6;;
                  *) echo -e "ERROR: Bad N_RB value $nrb"; return 1;;
            esac;;
        08) msin="0000000008";
            case $nrb in
                  25) rxgain=125; txgain=1; maxpower=-6;;
                  50) rxgain=127; txgain=1; maxpower=-6;;
                  *) echo -e "ERROR: Bad N_RB value $nrb"; return 1;;
            esac;;
        19) msin="0000000006";
            case $nrb in
                25) rxgain=95; txgain=9; maxpower=-14;;
                50) rxgain=98; txgain=8; maxpower=-13;; # to be tuned...
                *) echo -e "ERROR: Bad N_RB value $nrb"; return 1;;
            esac;;
        *) echo -e "ERROR: OAI UE cannot run on node fit$r2lab_id"; return 1;;
    esac

    -sed-configurator $usim_conf <<EOF
s|MNC="93";|MNC="95";|
s|MSIN=.*|MSIN="${msin}";|
s|OPC=.*|OPC="8E27B6AF0E692E750F32667A3B14605D";|
s|HPLMN=.*|HPLMN= "20895";|
s|"20893"|"20895"|
EOF

    echo " -C 2660000000 -r $nrb --ue-scan-carrier --ue-rxgain $rxgain --ue-txgain $txgain --ue-max-power $maxpower" > $ue_args_cmd

    echo "Configuring UE on fit$r2lab_id for nrb=$nrb"
    echo "will run oai-ue with following args: "
    cat $ue_args_cmd

    echo "generate usim"
    oai-ue.usim-gen
    echo "Set up the OAI UE IP interface"
    oai-ue.oip

    echo "will run OAI UE with following args"
    cat $ue_args_cmd
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

doc-nodes warm-up "Prepare SDR board (b210 or lime) for running an OAI UE - see --help"
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

    # stopping OAI UE service in case of a lingering instance
    echo -n "OAI UE service ... "
    echo -n "stopping ... "
    stop > /dev/null
    echo -n "status ... "
    status
    echo

    echo -n "Warming up OAI UE... "
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
             --fw-path /snap/oai-ue/current/uhd_images/usrp_b200_fw.hex \
             --fpga-path /snap/oai-ue/current/uhd_images/usrp_b200_fpga.bin || {
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
             --fw-path /snap/oai-ue/current/uhd_images/usrp_b200_fw.hex \
             --fpga-path /snap/oai-ue/current/uhd_images/usrp_b205mini_fpga.bin || {
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

doc-nodes start "Start OAI UE"
function start() {
    local USAGE="Usage: $FUNCNAME"

    [[ -n "$@" ]] && { echo -e "$USAGE"; return 1; }
    echo "Checking interface is up : $(turn-on-data)"

    echo "Show OAI USIM conf"
    oai-ue.usim-show
    echo -n "Running oai-ue "
    oai-ue.ue-cmd-show

    oai-ue.ue-start
}

doc-nodes stop "Stop OAI UE service(s)"
function stop() {
    oai-ue.ue-stop
}

doc-nodes status "Displays status of OAI UE service(s)"
function status() {
    oai-ue.ue-status
}

doc-nodes journal "Wrapper around journalctl about OAI UE service(s) - use with -f to follow up"
function journal() {
    units="snap.oai-ue.ued.service"
    jopts=""
    for unit in $units; do jopts="$jopts --unit $unit"; done
    journalctl $jopts "$@"
}

add-command-to-logs 'journalctl --unit=snap.oai-ue.ued.service -b'


doc-nodes configure-directory "cd into configuration directory for UE service(s)"
function configure-directory() {
    local conf_dir=$(dirname $(oai-ue.ue-conf-get))
    cd $conf_dir
}

########################################
define-main "$0" "$BASH_SOURCE"
main "$@"
