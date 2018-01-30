# set of convenience tools to be used on the nodes
# 
# we start with oai-oriented utilities
# on these images, we have a symlink
# /root/.bash_aliases
# that point at
# /root/r2lab/infra/user-env/nodes.sh
# 
#

# use the micro doc-help tool
source $(dirname $(readlink -f $BASH_SOURCE))/r2labutils.sh

create-doc-category nodes "#################### commands available on each r2lab node"
augment-help-with nodes

####################
unalias ls 2> /dev/null

####helper to parse git-pull arguments
# repo_branch repo /root/r2lab       -> /root/r2lab
# repo_branch branch /root/r2lab     -> 
# repo_branch repo /root/r2lab@foo   -> /root/r2lab
# repo_branch branch /root/r2lab@foo -> foo
function split_repo_branch () {
    python3 - "$@" << EOF
import sys
what, tosplit=sys.argv[1:3]
i = {'repo' : 0, 'branch' : 1}[what]
try:
    print(tosplit.split('@')[int(i)])
except:
    print("")
EOF
    }
    
##########
function git-pull-r2lab() { -git-pull-repos /root/r2lab@public; }
doc-nodes git-pull-r2lab "updates /root/r2lab from git repo"

# branches MUST be specified
function -git-pull-repos() {
    local repo_branches="$@"
    local repo_branch
    for repo_branch in $repo_branches; do
	local repo=$(split_repo_branch repo $repo_branch)
	local branch=$(split_repo_branch branch $repo_branch)
	[ -d $repo ] || { echo "WARNING: cannot git pull in $repo - not found"; continue; }
	echo "========== Updating $repo for branch $branch"
	cd $repo
	# always undo any local change
	git reset --hard HEAD
	# fetch everything
	git fetch -a
	git checkout $branch
	git pull origin $branch
	cd - >& /dev/null
    done
}

# reload this file after a git-pull-r2lab
doc-nodes bashrc "reload ~/.bashrc"
function bashrc() { echo "Reloading ~/.bashrc"; source ~/.bashrc; }

# update and reload
doc-nodes refresh "git-pull-r2lab + bashrc"
function refresh() { git-pull-r2lab /root/r2lab; bashrc; }

doc-nodes rimage "Shows info on current image from last line in /etc/rhubarbe-image"
function rimage() { tail -1 /etc/rhubarbe-image | sed -e 's, node , built-on ,' -e 's, image , from-image ,' ; }

########## 
doc-nodes update-os-packages "runs the core OS package update (dnf or apt-get) to update to latest versions"
function update-os-packages () {
    if type -p dnf >& /dev/null; then
	update-dnf-packages
    elif type -p apt-get >& /dev/null; then
	update-apt-get-packages
    else
	echo update-core-os unknown package manager
    fi
}

function update-dnf-packages () {
    dnf -y update
    # don't clobber space with cached packages
    dnf clean all
}

# when debconf hangs, it's hard to get more details on where apt-get is stuck or failing
# hence the two tricks to get more details with
# * the DEBCONF_DEBUG variable
# * as well as storing output locally on the node to avoid any buffering over the (ap)ssh mechanism
function update-apt-get-packages () {
    # potentially useful commands when writing/troubleshooting this
    # debconf-get-selections | grep grub-pc
    # dpkg-reconfigure grub-pc
    apt install debconf-utils
    debconf-set-selections <<< 'grub-pc	grub-pc/install_devices	multiselect /dev/sda'
    debconf-set-selections <<< 'console-setup console-setup/charmap47 select UTF-8'
    # try to get more
    export DEBCONF_DEBUG=developer
    apt-get -y update
    apt-get -y upgrade > /root/.apt-get-upgrade.log
    apt-get -y clean
}

##########
doc-nodes init-ntp-clock "Sets date from ntp"
function init-ntp-clock() {
    if type ntpdate >& /dev/null; then
	echo "Running ntpdate rhubarbe-control"
	ntpdate rhubarbe-control
    else
	echo "ERROR: cannot init clock - ntpdate not found"
	return 1
    fi
}

doc-nodes apt-upgrade-all "refresh all packages with apt-get"
function apt-upgrade-all() {
    apt-get -y update
    # for grub-pc
    debconf-set-selections <<< 'grub-pc	grub-pc/install_devices_disks_changed multiselect /dev/sda'
    debconf-set-selections <<< 'grub-pc	grub-pc/install_devices	multiselect /dev/sda'
    apt-get -y upgrade
    # turn off automatic updates
    apt-get -y purge unattended-upgrades

}
##########
doc-nodes-sep

# so, to build a hostname you would use r2lab-id
# BUT
# to build an IP address you need to remove leading 0s
# it actually only triggers for 08 and 09, somehow
#
# dataip="data$(r2lab-id)"
#
# ipaddr_mask=10.0.0.$(r2lab-ip)/24
#
doc-nodes r2lab-id "returns id in the range 01-37; adjusts hostname if needed"
function r2lab-id() {
    # when hostname is correctly set, e.g. fit16
    local fitid=$(hostname)
    local id=$(sed -e s,fit,, <<< $fitid)
    local origin="from hostname"
    if [ "$fitid" == "$id" ]; then
	# sample output
	#inet 192.168.3.16/24 brd 192.168.3.255 scope global control
	id=$(ip addr show control | \
		    grep 'inet '| \
		    awk '{print $2;}' | \
		    cut -d/ -f1 | \
		    cut -d. -f4)
	fitid=fit$id
	origin="from ip addr show"
	echo "Forcing hostname to be $fitid" >&2-
	hostname $fitid
    fi
    echo "Using id=$id and fitid=$fitid - $origin" >&2-
    echo $id
}

doc-nodes r2lab-ip "same as r2lab-id, but returns a single digit on nodes 1-9 - useful for buidling IP addresses"
function r2lab-ip() { r2lab-id | sed -e 's,^0,,'; }

doc-nodes turn-on-data "turn up the data interface; returns the interface name (should be data)"
# should maybe better use wait-for-interface-on-driver e1000e
data_ifnames="data"
# can be used with ifname=$(turn-on-data)
function turn-on-data() {
    local ifname
    for ifname in $data_ifnames; do
	ip addr sh dev $ifname >& /dev/null && {
	    ip link show $ifname | grep -q UP || {
		echo "turn-on-data: data network on interface" $ifname >&2-
		ifup $ifname >&2-
	    }
	    echo $ifname
	    break
	}
    done
}

doc-nodes list-interfaces "list the current status of all interfaces"
function list-interfaces () {
    set +x
    local f
    for f in /sys/class/net/*; do
	local dev=$(basename $f)
	local driver=$(readlink $f/device/driver/module)
	[ -n "$driver" ] && driver=$(basename $driver)
	local addr=$(cat $f/address)
	local operstate=$(cat $f/operstate)
	local flags=$(cat $f/flags)
	printf "%10s [%s]: %10s flags=%6s (%s)\n" "$dev" "$addr" "$driver" "$flags" "$operstate"
    done
}

# we can only list the ones that are turned on, unless the ifnames are
# provided on the command line
doc-nodes list-wireless "list currently available wireless interfaces"
function list-wireless () {
    local ifnames
    if [[ -n "$@" ]]; then
	ifnames="$@"
    else
	ifnames=""
	local w
	for w in $(ls -d /sys/class/net/*/wireless 2> /dev/null); do
	    ifnames="$ifnames $(basename $(dirname $w))"
	done
    fi
    local ifname
    for ifname in $ifnames; do
	iw dev $ifname info
	iw dev $ifname link
    done
}

doc-nodes turn-off-wireless "rmmod both wireless drivers from the kernel"
function turn-off-wireless() {
    local driver
    for driver in iwlwifi ath9k; do
	local _found=$(find-interface-by-driver $driver)
	if [ -n "$_found" ]; then
	    >&2 echo "turn-off-wireless: shutting down device $_found"
	    ip link set down dev $_found
	else
	    >&2 echo "turn-off-wireless: driver $driver not used";
	fi
	lsmod | grep -q "^${driver} " && {
	    >&2 echo "turn-off-wireless: removing driver $driver"
	    modprobe -q -r $driver
	}
    done
}

doc-nodes details-on-interface "gives extensive details on one interface"
function details-on-interface () {
    local dev=$1; shift
    echo ==================== ip addr sh $dev
    ip addr sh $dev
    echo ==================== ip link sh $dev
    ip link sh $dev
    echo ==================== iwconfig $dev
    iwconfig $dev
    echo ==================== iw dev $dev info
    iw dev $dev info
}    

doc-nodes find-interface-by-driver "returns first interface bound to given driver"
function find-interface-by-driver () {
    set +x
    local search_driver=$1; shift
    local f
    for f in /sys/class/net/*; do
	local _if=$(basename $f)
	local driver=$(readlink $f/device/driver/module)
	[ -n "$driver" ] && driver=$(basename $driver)
	if [ "$driver" == "$search_driver" ]; then
	    echo $_if
	    return
	fi
    done
}

# wait for one interface to show up using this driver
# prints interface name on stdout
doc-nodes wait-for-interface-on-driver "locates and waits for device bound to provided driver, returns its name"
function wait-for-interface-on-driver() {
    local driver=$1; shift

    # artificially pause for one second
    # this is because when used right after a modprobe, we have seen situations
    # where we catch a name before udev has had the time to trigger and rename the interface
    # should not be a big deal hopefully
    sleep 1
    
    while true; do
	# use the first device that runs on iwlwifi
	local _found=$(find-interface-by-driver $driver)
	if [ -n "$_found" ]; then
	    >&2 echo Using device $_found
	    echo $_found
	    return
	else
	    >&2 echo "Waiting for some interface to run on driver $driver"; sleep 1
	fi
    done
}

doc-nodes wait-for-device "wait for device to be up or down; example: wait-for-device data up"
function wait-for-device () {
    set +x
    local dev=$1; shift
    local wait_state="$1"; shift
    
    while true; do
	local f=/sys/class/net/$dev
	local operstate=$(cat $f/operstate 2> /dev/null)
	if [ "$operstate" == "$wait_state" ]; then
	    2>& echo Device $dev is $wait_state
	    break
	else
	    >&2 echo "Device $dev is $operstate - waiting 1s"; sleep 1
	fi
    done
}

doc-nodes-sep

##########
# the utility to select which function the oai alias should point to
# in most cases, we just want oai to be an alias to e.g.
# /root/r2lab/infra/user-env/oai-gw.sh
# except that while developping we use the version in /tmp
# if present

# the place where the standard (git) scripts are located
oai_scripts=$(dirname $(readlink -f "$BASH_SOURCE"))
#echo oai_scripts=$oai_scripts

# the mess with /tmp is so that scripts can get tested before they are committed
# it can be dangerous though, as nodes.sh is also loaded at login-time, so beware..

function oai-as() {
    # oai_role should be gw or epc or hss or enb
    export oai_role=$1; shift
    local candidates="/tmp $oai_scripts"
    local candidate=""
    local script=""
    for candidate in $candidates; do
	local path=$candidate/oai-${oai_role}.sh
	[ -f $path ] && { script=$path; break; }
    done
    [ -n "$script" ] || { echo "Cannot locate oai-${oai_role}.sh" >&2-; return; }
    source $path
}

doc-nodes oai-as-gw "load additional functions for dealing with an OAI gateway"
function oai-as-gw() { oai-as gw; }

doc-nodes oai-as-hss "defines the 'oai' command for a HSS-only oai box, and related env. vars"
function oai-as-hss() { oai-as hss; }

doc-nodes oai-as-epc "defines the 'oai' command for an EPC-only oai box, and related env. vars"
function oai-as-epc() { oai-as epc; }

doc-nodes oai-as-enb "defines the 'oai' command for an oai eNodeB, and related env. vars"
function oai-as-enb() { oai-as enb; }

doc-nodes oai-as-ue "defines the 'oai' command for an oai UE, and related env. vars"
function oai-as-ue() { oai-as ue; }

doc-nodes-sep

# this will define add-to-logs and get-logs and grep-logs and tail-logs
create-file-category log
# other similar categories
create-file-category data
create-file-category config
create-file-category lock


doc-nodes ls-logs     "list (using ls) the log files defined with add-to-logs"
doc-nodes grep-logs   "run grep on logs, e.g grep-logs -i open"
doc-nodes ls-configs  "lists config files declared with add-to-configs"
doc-nodes ls-datas    "you got the idea; you have also grep-configs and similar combinations"

doc-nodes capture-all "captures logs and datas and configs in a tgz"
function capture-all() {
    local output=$1; shift
    echo "++++++++++++++++++++++++++++++++++++++++"
    echo "capture-all: output = $output"
    [ -z "$output" ] && { echo usage: capture-all output; return; }
    local allfiles="$(ls-logs) $(ls-configs) $(ls-datas)"
    local outpath=$HOME/$output.tgz
    tar -czf $outpath $allfiles
    echo "Captured in $outpath the following files:"
    ls -l $allfiles
    echo "++++++++++++++++++++++++++++++++++++++++"
}    

doc-nodes-sep

peer_id_file=/root/peer.id
doc-nodes define-peer "defines the id of a peer - stores it in $peer_id_file; e.g. define-peer 16"
# define-peer allows you to store the identity of the node being used as a gateway
# example: define-peer 03
# this is stored in file $peer_id_file
# it is required by some setups that need to know where to reach another service
function define-peer() {
    id="$1"; shift
    id=$(printf %02d $id)
    [ -n "$id" ] && echo $id > $peer_id_file
    echo "peer now defined as : " $(cat $peer_id_file)
}

doc-nodes get-peer "retrieve the value defined with define-peer"
function get-peer() {
    if [ ! -f $peer_id_file ]; then
	echo "ERROR: you need to run define-peer first" >&2-
    else
	echo $(cat $peer_id_file)
    fi
}

#################### debugging
doc-nodes dump-dmesg "run dmesg every second and stores into /root/dmesg/dmesg-hh-mm-ss"
function dump-dmesg() {
    mkdir -p /root/dmesg
    while true; do
	dmesg > /root/dmesg/dmesg-$(date +"%H-%M-%S")
	echo -n "."
	sleep 1
    done	 
}    

doc-nodes unbuf-var-log-syslog "reconfigures rsyslog to write in /var/sys/syslog unbuffered on ubuntu"
function unbuf-var-log-syslog() {
    # 
    local conf=/etc/rsyslog.d/50-default.conf
    sed --in-place -e s,-/var/log/syslog,/var/log/syslog, $conf
    service rsyslog restart
    echo "Writing to /var/log/syslog is now unbeffered"
}

#################### tcpdump
# 2 commands to start and stop tcpdump on the data interface
# output is in /root/data-<name>.pcap
# with <name> provided as a first argument (defaults to r2lab-id)
# it is desirable to set a different name on each host, so that when collected
# data gets merged into a single file tree they don't overlap each other

# Usage -start-tcpdump data|control some-distinctive-name tcpdump-arg..s
function -start-tcpdump() {
    local interface="$1"; shift
    local name="$1"; shift
    [ -z "$name" ] && name=$(r2lab-id)
    cd 
    local pcap="${interface}-${name}.pcap"
    local pidfile="tcpdump-${interface}.pid"
    local command="tcpdump -n -U -w $pcap -i ${interface}" "$@"
    echo "${interface} traffic tcpdump'ed into $pcap with command:"
    echo "$command"
    nohup $command >& /dev/null < /dev/null &
    local pid=$!
    ps $pid
    echo $pid > $pidfile
}
    
# Usage -stop-tcpdump data|control some-distinctive-name
function -stop-tcpdump() {
    local interface="$1"; shift
    local name="$1"; shift
    [ -z "$name" ] && name=$(r2lab-id)
    cd
    local pcap="${interface}-${name}.pcap"
    local pidfile="tcpdump-${interface}.pid"
    if [ ! -f $pidfile ]; then
	echo "Could not spot tcpdump pid from $pidfile - exiting"
    else
	local pid=$(cat $pidfile)
	echo "Killing tcpdump pid $pid"
	kill $pid
	rm $pidfile
    fi
}

doc-nodes start-tcpdump-data "Start recording pcap data about traffic on the data interface"
function start-tcpdump-data() { -start-tcpdump data "$@"; }
doc-nodes stop-tcpdump-data "Stop recording pcap data about SCTP traffic"
function stop-tcpdump-data() { -stop-tcpdump data "$@"; }

####################
# keep it in here just in case but this hack is no longer needed
#doc-nodes demo "set ups nodes for the skype demo - based on their id"
function demo() {
    case $(r2lab-id) in
	38)
	    oai-as-hss
	    define-peer 39
	    ;; # for preplab
	39)
	    oai-as-epc
	    define-peer 38
	    ;; # for preplab
	03)
	    oai-as-epc
	    define-peer 04
	    ;;
	04)
            oai-as-hss
            define-peer 03
            ;;
	16)
	    oai-as-enb
	    define-peer 03
	    ;;
	23)
	    oai-as-enb
	    define-peer 03
	    ;;
    esac
    echo "========== Demo setup on node $(r2lab-id)"
    echo "running as a ${oai_role}"
    echo "config uses peer=$(get-peer)"
    echo "using interface ${oai_ifname} on subnet ${oai_subnet}"
}

# long names are tcp-segmentation-offload udp-fragmentation-offload
# generic-segmentation-offload generic-receive-offload
# plus, udp-fragmentation-offload is fixed on our nodes
doc-nodes "offload-(on|off)" "turn on or off various offload features on specified wired interface" 
function offload-off () { -offload off "$@"; }
function offload-on () { -offload on "$@"; }

function -offload () {
    local mode="$1"; shift
    local ifname=$1; shift
    for feature in tso gso gro ; do
	local command="ethtool -K $ifname $feature $mode"
	echo $command
	$command
    done
}

doc-nodes enable-nat-data "Makes the data interface NAT-enabled to reach the outside world"
function enable-nat-data() {
    local id=$(r2lab-id)
    ip route add default via 192.168.2.100 dev data table 200
    ip rule add from 192.168.2.2/24 table 200 priority 200
}

####################

doc-nodes enable-usrp-ethernet "Configure the data network interface for USRP2 or N210 and rename it usrp"
function enable-usrp-ethernet() {
    ifconfig data down 2>/dev/null
    ip link set data name usrp
    ifconfig usrp 192.168.10.1 netmask 255.255.255.0 broadcast 192.168.10.255
    ifconfig usrp up
}

doc-nodes usb-reset "Reset the USB port where the external device (USRP2/N210/e3372) is attached"
function usb-reset() {
    local id=$(r2lab-id)
    # WARNING this might not work on a node that
    # is not in its nominal location,
    # like if node 42 sits in slot 4
    local cmc="192.168.1.$id"
    echo "Turning off USRP # $id"
    curl http://$cmc/usrpoff
    sleep 1
    echo "Turning on USRP # $id"
    curl http://$cmc/usrpon
}


doc-nodes usrp-reset "Reset the USRP attached to this node" 
function usrp-reset () { usb-reset; } 


doc-nodes e3372-reset "Reset the LTE Huawei E3372 attached to this node"
function e3372-reset() {
    # The node should have a USB LTE Huawei E3372 attached and have an ubuntu-huawei image

    usrp-reset
    sleep 1
    usb_modeswitch -v 12d1 -p 1f01 -M '55534243123456780000000000000011062000000101000100000000000000'
    ifup enx0c5b8f279a64
}



##############################
# xxx could use a -interactive wrapper to display command
# and then ask for user's confirmation

downlink_freq="--freq=2.56G"
uplink_freq="--freq=2.68G"

function -scramble() {
    local link="$1"; shift
    local force="$1"; shift
    
    local command="uhd_siggen --gaussian"
    case "$link" in
	up*)
	    command="$command $uplink_freq" ;;
	down*)
	    command="$command $downlink_freq" ;;
    esac
    command="$command $force"

    echo "About to run command:"
    echo $command
    echo -n "OK ? (Ctrl-C to abort) "
    read _
    $command
}

doc-nodes 'scramble-*' "shortcuts for scrambling the skype demo; use -blast to use max. gain"
function scramble-downlink() { -scramble downlink "-g 70"; }
function scramble-downlink-mid() { -scramble downlink "-g 80"; }
function scramble-downlink-blast() { -scramble downlink "-g 90"; }
function scramble-uplink() { -scramble uplink "-g 70"; }
function scramble-uplink-mid() { -scramble uplink "-g 80"; }
function scramble-uplink-blast() { -scramble uplink "-g 90"; }

doc-nodes watch-uplink "Run uhd_fft on band7 uplink"
function watch-uplink() {
    local command="uhd_fft $uplink_freq -s 25M"
    echo $command
    $command
}

doc-nodes watch-downlink "Run uhd_fft on band7 downlink"
function watch-downlink() {
    local command="uhd_fft $downlink_freq -s 25M"
    echo $command
    $command
}
########################################
define-main "$0" "$BASH_SOURCE"
main "$@"
