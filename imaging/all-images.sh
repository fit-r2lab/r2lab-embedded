#/bin/bash

case $(hostname) in
    faraday*)
        gateway=localhost
        gitroot=/root/r2lab-embedded
    ;;
    *)
        gateway=inria_admin@faraday.inria.fr
        gitroot=$HOME/git/r2lab-embedded
    ;;
esac

# check that this directory exists
[ -d $gitroot ] || {
    echo "Could not locate your r2lab-embedded git repo - search for gitroot in the code"
    exit 1
}

###
bi=$(dirname $0)/build-image.py

# we don't need all these includes everywhere but it makes it easier
function bim () {
    command="$bi $gateway -p $gitroot/shell -i mosaic-common.sh -i nodes.sh -i r2labutils.sh"
    echo $command "$@"
    $command --silent "$@"
}

DATE=$(date +"%Y-%m-%d")

# when run with an arg : just print the command to run manually
[[ -n "$@" ]] && { bim --help; exit; }

####################
# one-shot : how we initialized the -v5-ntp images in the first place
# augment ubuntu-16.04 with ntp
#0# bim fit01 ubuntu-16.04-v4-node-env ubuntu-16.04-v5-ntp \
#0#   "imaging.sh ubuntu-setup-ntp" \
#0#   "nodes.sh gitup"

#0#  bim 6 ubuntu-14.04-v3-stamped ubuntu-14.04-v5-ntp \
#0#    "imaging.sh ubuntu-setup-ntp" \
#0#     "imaging.sh common-setup-node-ssh-key" \
#0#     "imaging.sh common-setup-user-env" \
#0#     "nodes.sh gitup"


cn_opts="
    -l /root/openair-cn/scripts/build-hss-deps.log
    -l /root/openair-cn/scripts/build-mme-deps.log
    -l /root/openair-cn/scripts/build-spgw-deps.log
    -b /root/openair-cn/build/mme/build/mme
    -b /root/openair-cn/build/spgw/build/spgw
"

enb_opts="
    -l /root/build-oai5g.log
    -l /root/openairinterface5g/cmake_targets/log/asn1c_install_log.txt
    -l /root/openairinterface5g/cmake_targets/build-oai-1.log
    -l /root/openairinterface5g/cmake_targets/build-oai-2.log
    -b /root/openairinterface5g/cmake_targets/lte_build_oai/build_usrp/lte-softmodem
    -b /root/openairinterface5g/cmake_targets/lte_build_oai/build_limesdr/lte-softmodem
"
ue_opts="
    -l /root/build-oai5g-ue.log
    -l /root/openairinterface5g/cmake_targets/log/asn1c_install_log.txt
    -l /root/openairinterface5g/cmake_targets/build-oai-ue-1.log
    -b /root/openairinterface5g/cmake_targets/lte_build_oai/build/lte-softmodem
"

gr_opts="
    -b /usr/bin/gnuradio-companion
    -b /usr/bin/uhd_find_devices
"

e3372_opts="
    -b /usr/sbin/usb_modeswitch
"


# following 2 are deprecated
gw_options="
    -l /root/openair-cn/SCRIPTS/build-hss-deps.log
    -l /root/openair-cn/SCRIPTS/build-mme-deps.log
    -l /root/openair-cn/SCRIPTS/build-spgw-deps.log
    -b /root/openair-cn/BUILD/MME/BUILD/mme
    -b /root/openair-cn/BUILD/SPGW/BUILD/spgw
"

enb_options="
    -l /root/openairinterface5g/cmake_targets/build-uhd.log
    -l /root/build-uhd-ettus.log -l /root/build-oai5g.log
    -l /root/openairinterface5g/cmake_targets/log/asn1c_install_log.txt
    -l /root/openairinterface5g/cmake_targets/build-oai-1.log
    -l /root/openairinterface5g/cmake_targets/build-oai-2.log
    -b uhd_find_devices
    -b /root/openairinterface5g/cmake_targets/lte_build_oai/build/lte-softmodem
"

function u16-ath-noreg() {
    bim 8 ubuntu-16.04 u16-ath-noreg-full-$DATE "nodes.sh git-pull-r2lab" "nodes.sh apt-upgrade-all" "imaging.sh ubuntu-atheros-noreg"
    bim 9 u16-ath-noreg-full-$DATE u16-ath-noreg-$DATE "imaging.sh clean-kernel-build"
}

function u16-48() {
    bim 1 ubuntu-16.04 u16.04 "imaging.sh new-common-setup" "imaging.sh update-os-packages" "nodes.sh git-pull-r2lab" "nodes.sh apt-upgrade-all"
    bim 2 u16.04 u16-lowlat48 "imaging.sh ubuntu-k48-lowlatency" "imaging.sh activate-lowlatency"
}

# all images used in openair demo
function oai() {
    bim $e3372_opts 3 u16.04 u16.04-e3372 "imaging.sh install-e3372"&
    bim $cn_opts 5 u16-lowlat48 u16.48-oai-cn "oai-gw.sh  image" &
    bim $enb_opts 6 u16-lowlat48 u16.48-oai-enb "oai-enb.sh image" &
    bim $ue_opts 7 u16-lowlat48 u16.48-oai-ue "oai-ue.sh image" &
}

# latest gnuradio built from source -- better to use lowlatency for uhd
function gnuradio() {
    bim $gr_opts 8 u16-lowlat48 u16.48-gnuradio "imaging.sh install-gnuradio" "nodes.sh enable-usrp-ethernet"
}

function all-oai() {
    u16-48
    oai
    gnuradio
}

#following deprecated
function old-u16-48() {
    bim 1 ubuntu-16.04 u16.04-$DATE "imaging.sh common-setup" "nodes.sh git-pull-r2lab" "nodes.sh apt-upgrade-all"
    bim 2 u16.04-$DATE u16-lowlat48-$DATE "imaging.sh ubuntu-k48-lowlatency" "imaging.sh activate-lowlatency"
    bim $e3372_opts 3 u16.04-$DATE u16.04-e3372 "imaging.sh install-e3372"
    bim $cn_opts 5 u16-lowlat48-$DATE u16.48-oai-cn "oai-gw.sh  image" &
    bim $enb_opts 6 u16-lowlat48-$DATE u16.48-oai-enb "oai-enb.sh image" &
    bim $ue_opts 7 u16-lowlat48-$DATE u16.48-oai-ue "oai-ue.sh image" &
    bim $gr_opts 8 u16-lowlat48-$DATE u16.48-gnuradio-3.7.10 "imaging.sh install-gnuradio" "nodes.sh enable-usrp-ethernet"&
}

function very-old-u16-48() {
    bim 2 ubuntu-16.04 u16.04-$DATE "nodes.sh apt-upgrade-all"
    bim 3 u16.04-$DATE u16-lowlat48-$DATE "imaging.sh ubuntu-k48-lowlatency"
    bim $gw_options  6 u16-lowlat48-$DATE u16.48-oai-gw-$DATE  "oai-gw.sh  image"
    bim $enb_options 7 u16-lowlat48-$DATE u16.48-oai-enb-$DATE "oai-enb.sh image uhd-oai"
}

#following deprecated
function u16-47() {
    #bim 1 ubuntu-16.04-v5-ntp == "imaging.sh common-setup-user-env"
    #bim 2 ubuntu-16.04-v5-ntp u16-lowlat47 "imaging.sh ubuntu-k47-lowlatency"
    bim $gw_options  3 u16-lowlat47 u16.47-oai-gw "oai-gw.sh image"
    bim $enb_options 5 u16-lowlat47 u16.47-oai-enb "oai-enb.sh image"
}

#following deprecated
function u14-48(){
    #bim 6 ubuntu-14.04-v5-ntp == "imaging.sh common-setup-user-env"
    #bim 7 ubuntu-14.04-v5-ntp u14-lowlat48 "imaging.sh ubuntu-k48-lowlatency"
    bim $gw_options  6 u14-lowlat48 u14.48-oai-gw "oai-gw.sh image"
    ###bim $enb_options 7 u14-lowlat48 u14.48-oai-enb "oai-enb.sh image"
}

#following deprecated
function u14-319(){
    #bim 1 ubuntu-14.04-v5-ntp u14-lowlat319 "imaging.sh ubuntu-k319-lowlatency"
    ###bim $gw_options  2 u14-lowlat48 u14.48-oai-gw "oai-gw.sh image"
    bim $enb_options 37 u14-lowlat319 u14.319-oai-enb-uhdoai "oai-enb.sh image uhd-oai"
    #bim $enb_options 36 u14-lowlat319 u14.319-oai-enb-uhdettus "oai-enb.sh image uhd-ettus"
}

function old-gnuradio(){
    bim 1 ubuntu-16.04-gnuradio-3.7.10.1-update3 ubuntu-16.04-gnuradio-3.7.10.1-update4 "nodes.sh git-pull-r2lab"
}

function update-root-bash() {
    bim 1 ubuntu-16.04-v5-ntp ubuntu-16.04-v6-user-env "imaging.sh common-setup" "nodes.sh git-pull-r2lab" &
    bim 2 ubuntu-14.04-v5-ntp ubuntu-14.04-v6-user-env "imaging.sh common-setup" "nodes.sh git-pull-r2lab" &
    bim 3 fedora-23-v4-ntp fedora-23-v6-user-env       "imaging.sh common-setup" "nodes.sh git-pull-r2lab" &
    bim 5 intelcsi-node-env intelcsi-v3-user-env       "imaging.sh common-setup" "nodes.sh git-pull-r2lab" &
    bim 6 ubuntu-16.04-gnuradio-3.7.10.1-update4    \
          ubuntu-16.04-gnuradio-3.7.10.1-v5-user-env   "imaging.sh common-setup" "nodes.sh git-pull-r2lab" &
}

# preserving the oai images for now
function redo-netnames() {
    bim 1  ubuntu-16.04 ubuntu-16.04-v10-wireless-names "imaging.sh network-names-udev" &
    bim 2  ubuntu-14.04 ubuntu-14.04-v10-wireless-names "imaging.sh network-names-udev" &
    bim 3  fedora-23    fedora-23-v10-wireless-names "imaging.sh network-names-udev" &
    bim 5  gnuradio     ubuntu-16.04-gnuradio-3.7.10.1-v10-wireless-names "imaging.sh network-names-udev" &
    bim 11 intelcsi     intelcsi-v10-wireless-names "imaging.sh network-names-udev" &
}

########## template
function template() {
    bim 1 ubuntu-16.04	ubuntu-16.04-vx-some-name			"imaging.sh some-function" &
    bim 2 ubuntu-14.04  ubuntu-14.04-vx-some-name			"imaging.sh some-function" &
    bim 3 fedora-23	fedora-23-vx-some-name				"imaging.sh some-function" &
    bim 5 gnuradio	ubuntu-16.04-gnuradio-3.7.10.1-vx-some-name	"imaging.sh some-function" &
    # these ones have a USRP
    bim 11 intelcsi	intelcsi-vx-some-name				"imaging.sh some-function" &
    # leave the OAI images for now, as we should redo them based on one of the above
}

function node-keys() {
    bim 1 ubuntu-16.04	ubuntu-16.04-v9-node-keys			"imaging.sh common-setup-node-ssh-key" &
    bim 2 ubuntu-14.04  ubuntu-14.04-v9-node-keys			"imaging.sh common-setup-node-ssh-key" &
    bim 3 fedora-23	fedora-23-v9-node-keys				"imaging.sh common-setup-node-ssh-key" &
    bim 5 gnuradio	ubuntu-16.04-gnuradio-3.7.10.1-v9-node-keys	"imaging.sh common-setup-node-ssh-key" &
    # these ones have a USRP
    bim 11 intelcsi	intelcsi-v9-node-keys				"imaging.sh common-setup-node-ssh-key" &
    # leave the OAI images for now, as we should redo them based on one of the above
}

function ubuntu-udev() {
#    bim 1  ubuntu-16.04 ubuntu-16.04-v8-wireless-names "imaging.sh ubuntu-udev" &
#    bim 2  ubuntu-14.04 ubuntu-14.04-v8-wireless-names "imaging.sh ubuntu-udev" &
#    bim 3  fedora-23    fedora-23-v8-wireless-names "imaging.sh ubuntu-udev" &
    bim 5  gnuradio     ubuntu-16.04-gnuradio-3.7.10.1-v8-wireless-names "imaging.sh ubuntu-udev" &
    bim 11 intelcsi     intelcsi-v8-wireless-names "imaging.sh ubuntu-udev" &
}

# preserving the oai images for now
# also stay away from node 4 that is prone to mishaps
function  update-v11() {
    # update OS packages on vanilla images only
    bim 1 ubuntu-16.04-v10-wireless-names \
	ubuntu-16.04-v11-os-update	"nodes.sh git-pull-r2lab" "nodes.sh update-os-packages" &
    bim 2 ubuntu-14.04-v10-wireless-names \
	ubuntu-14.04-v11-os-update	"nodes.sh git-pull-r2lab" "nodes.sh update-os-packages" &
    bim 3 fedora-23-v10-wireless-names \
	fedora-23-v11-os-update		"nodes.sh git-pull-r2lab" "nodes.sh update-os-packages" &
    bim 5 intelcsi-v10-wireless-names \
	intelcsi-v11-os-update		"nodes.sh git-pull-r2lab" "nodes.sh update-os-packages" &
    bim 6 ubuntu-16.04-gnuradio-3.7.10.1-v10-wireless-names \
          gnuradio-v11-os-update	"nodes.sh git-pull-r2lab" "nodes.sh update-os-packages" &
}

function f27-new-layout() {
    bim 4 fedora-27 \
        fedora-27-new-layout "imaging.sh new-common-setup" "imaging.sh update-os-packages"
}

function f27-docker() {
    bim 5 fedora-27-new-layout \
        fedora-27-docker "imaging.sh fedora-setup-docker"
}

function ubuntu-new-layout() {
    bim 6 u16.04-2017-10-26 \
        u16.04-new-layout "imaging.sh new-common-setup" "imaging.sh update-os-packages"
}

function ubuntu-docker() {
    bim 7 u16.04-new-layout \
        u16.04-docker "imaging.sh ubuntu-setup-docker"
}

# mosaic-cn requires the gtp module that comes only with kernels >= 4.8
# one way to go there is with Ubuntu's lts kernel rollout scheme
# https://wiki.ubuntu.com/Kernel/RollingLTSEnablementStack
mosaic_base1=u16.04-lts
mosaic_base2=u16.04-lts-update

# we need to do this in 2 steps so that the node reboots
# on the right kernel after we move to lts
function mosaic-base() {
    bim 21 u16.04 u16.04-lts \
        "imaging.sh u16-optin-lts-kernel" \
        "imaging.sh new-common-setup-root-bash2"
    bim 22 u16.04-lts u16.04-lts-update \
	"nodes.sh git-pull-r2lab" \
        "nodes.sh apt-upgrade-all"
}

function mosaic-cn() {
    bim 23 u16.04-lts-update mosaic-cn "mosaic-cn.sh image"
}

function mosaic-ran() {
    # ditto, there is a need to reboot after activate-lowlatency
    bim 24 u16.04-lts-update mosaic-ran-base \
        "imaging.sh activate-lowlatency"
    bim 25 mosaic-ran-base mosaic-ran \
        "mosaic-ran.sh image"
    bim 26 mosaic-ran-base mosaic-ue \
        "mosaic-oai-ue.sh image"
}

function u18-04.2() {
    bim 36 u18.04 u18.04-$DATE-tmp \
        "nodes.sh git-pull-r2lab" "nodes.sh apt-upgrade-all" 
    bim 37 u18.04-$DATE-tmp u18.04-$DATE \
        "imaging.sh clean-kernel-build"
}

function centos-8() {
    bim 37 centos-8-ssh centos-8-r2lab \
        "imaging.sh fedora-base" \
        "imaging.sh fedora-setup-ntp" \
        "imaging.sh network-names-udev" \
        "imaging.sh centos-8-ifcfg" \
        "imaging.sh new-common-setup"
}

function fedora-31() {
    bim 36 fedora-31-ssh fedora-31-r2lab \
        "imaging.sh fedora-base" \
        "imaging.sh fedora-setup-ntp" \
        "imaging.sh network-names-udev" \
        "imaging.sh fedora-31-ifcfg" \
        "imaging.sh new-common-setup"
}

####################
# xxx this clearly should be specified on the command line some day

centos-8 &
fedora-31 &
wait %1 %2
