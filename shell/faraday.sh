unalias ls 2> /dev/null

########## pseudo docstrings
source $(dirname $(readlink -f $BASH_SOURCE))/r2labutils.sh

create-doc-category selection "commands that work on a selection of nodes"
augment-help-with selection
create-doc-category alt "other convenient user-oriented commands"
create-doc-category admin "admin-oriented commands"

#################### contextual data
function preplab () { hostname | grep -q bemol; }

control_dev=control

doc-admin igmp-watch "tcpdump igmp packets on the $control_dev interface"
function igmp-watch () {
    set -x
    tcpdump -i $control_dev igmp
    set +x
}

####################
#### some stuff is just too hard / too awkward in shell...
# py normalize fit 1 03 fit09
# py ranges 1-37-2 ~1-20-4
function py () {
    python3 - "$@" << EOF
import sys
def host_pxe(nodename):
    import subprocess
    try:
        dnsmasq = subprocess.check_output(['grep', nodename, '/etc/dnsmasq.d/testbed.conf'],
                                          universal_newlines=True)
        return dnsmasq.split(',')[1].replace(':', '-')
    except:
        pass
    try:
        arp = subprocess.check_output(['arp', nodename], universal_newlines=True)
        mac = arp.split('\n')[1].split()[2].replace(':', '-')
        return mac
    except:
        return ""

# XXX todo : apparently the first strategy here does not work as it should
def pxe_host(pxe):
    import subprocess
    bytes = pxe.split('-')
    if len(bytes) == 7:
        bytes = bytes[1:]
    mac = ':'.join(bytes)
    try:
        dnsmasq = subprocess.check_output(['grep', mac, '/etc/dnsmasq.d/testbed.conf'],
					  universal_newlines=True)
        fields = dnsmasq.strip().split(',')
        return "{} ({})".format(fields[2], fields[3])
    except:
        pass
    try:
        arp = subprocess.check_output(['arp', '-a'], universal_newlines=True)
        for line in arp.split('\n'):
            try:
                args = line.split(' ')
                if args[3] == mac:
                    return "{hn} ({ip})".format(hn=args[0], ip=args[1])
            except:
                continue
        return "unknown-MAC"
    except:
        return "unknown-MAC"

def _rangetoset(rngspec):
    "translate something like 1-12 into a set"
    if ',' in rngspec:
        result = set()
        for part in rngspec.split(','):
            result |= _rangetoset(part)
        return result
    if rngspec.count('-') == 0:
        return set( [ int(rngspec) ] )
    elif rngspec.count('-') == 1:
        low, high = [ int(x) for x in rngspec.split('-') ]
        step = 1
    elif rngspec.count('-') == 2:
        low, high, step = [ int(x) for x in rngspec.split('-') ]
    else:
        sys.stderr.write("rangetoset: {} not understood\n".format(rngspec))
        return set()
    return set(range(low, high + 1, step))

def _ranges(*rngspecs):
#    print('_ranges',rngspecs)
    numbers = set()
    for rngspec in rngspecs:
        if rngspec.startswith('~'):
            numbers -= _rangetoset(rngspec[1:])
        else:
            numbers |= _rangetoset(rngspec)
    return sorted(list(numbers))

def ranges (*rngspecs):
#    print('ranges', rngspecs)
    return " ".join( [ "{:02d}".format(arg) for arg in _ranges(*rngspecs) ] )

def _normalize (sep, *args):
#    print('normalize', args)
    constant = args[0]
    rngspecs = [ arg.replace(constant, "") for arg in args[1:] if arg ]
    return sep.join( [ "{}{:02d}".format(constant, arg) for arg in _ranges(*rngspecs) ] )

def normalize (*args):
    return _normalize(' ', *args)

def comma_normalize (*args):
    return _normalize(',', *args)

# normalize2 fit reboot 1-3 fit04 reboot05 ->
def normalize2 (*args):
#    print('normalize', args)
    constant = args[0]
    output = args[1]
    rngspecs = [ arg.replace(constant, "").replace(output, "") for arg in args[2:] if arg ]
    return " ".join( [ "{}{:02d}".format(output, arg) for arg in _ranges(*rngspecs) ] )

def main():
    _ = sys.argv.pop(0)
    command = sys.argv.pop(0)
    args = sys.argv
    function = globals()[command]
    print(function(*args))

main()
EOF
}

doc-admin snap "create a snapshot of the r2lab chamber state"
function snap () {
  python3 /root/r2lab/nodes/snap.py "$@"
}

# normalization
# the intention is you can provide any type of inputs, and get the expected format
# norm 1 03 fit04 5-8 ~7 -> fit01 fit03 fit04 fit05 fit06 fit08
function norm () { py normalize fit "$@" ; }
# norm 1 03 fit04 -> fit01,fit03,fit04
function cnorm () { py comma_normalize fit "$@" ; }
# normreboot 1 03 fit04 reboot05 -> reboot01 reboot03 reboot04 reboot05
function normreboot () { py normalize2 fit reboot "$@" ; }

# set and/or show global NODES var
# nodes
# -> show NODES
# nodes 1 3 5
# -> set NODES to fit01 fit03 fit05 and display it too
function nodes () {
    [ -n "$1" ] && export NODES=$(rhubarbe nodes "$@")
    echo "export NODES=\"$NODES\""
    echo "export NBNODES=$(nbnodes)"
}
alias n=nodes
doc-selection nodes "(alias n) show or define currently selected nodes; eg nodes 1-10,12 13 ~5"


function nbnodes () {
    [ -n "$1" ] && nodes="$@" || nodes="$NODES"
    echo $(for node in $nodes; do echo $node; done | wc -l)
}

# add to global NODES
# nodes_add 4 12-15 fit33
function nodes-add () {
    export NODES="$(norm $NODES $@)"
    nodes
}
alias n+=nodes-add
doc-selection nodes-add "(alias n+) add nodes to current selection"
function nodes-sub () {
    local subspec
    local rngspec
    for rngspec in "$@"; do
	subspec="$subspec ~$rngspec"
    done
    export NODES="$(norm $NODES $subspec)"
    nodes
}
alias n-=nodes-sub
doc-selection nodes-sub "(alias n-) remove nodes from current selection"

# snapshot current set of nodes for later
# nodes-save foo
function nodes-save () {
    local name=$1; shift
    export NODES$name="$NODES"
    echo "Saved NODES$name=$NODES"
}
doc-alt nodes-save "name current selection"

# nodes-restore foo : goes back to what NODES was when you did nodes-save foo
function nodes-restore () {
    local name=$1; shift
    local preserved=NODES$name
    export NODES="${!preserved}"
    nodes
}
doc-alt nodes-restore "use previously named selection"

#preplab && export _all_nodes=38-42 || export _all_nodes=1-37
#preplab && export _all_nodes=4,38-41 || export _all_nodes=1-37

_all_nodes_cache=""
function _get_all_nodes () {
    [ -z "$_all_nodes_cache" ] && _all_nodes_cache="$(rhubarbe nodes -a)"
    echo $_all_nodes_cache
}

function all-nodes () { nodes $(_get_all_nodes); }
doc-selection all-nodes "select all available nodes"

# show-nodes-on : filter nodes that are on from args, or NODES if not provided
function show-nodes-on () {
    local nodes
    [ -n "$1" ] && nodes="$@" || nodes="$NODES"
    rhubarbe status $nodes | grep 'on' | cut -d: -f1 | sed -e s,reboot,fit,
}
doc-selection show-nodes-on "display only selected nodes that are ON - does not change selection"

function focus-nodes-on () {
    nodes $(show-nodes-on "$@")
}
doc-selection focus-nodes-on "restrict current selection to nodes that are ON"

alias fa="focus-nodes-on -a"
doc-selection "fa" "Select all nodes currently ON - i.e. focus-nodes-on -a"

### first things first
alias rleases="rhubarbe leases"
doc-selection rleases "display current leases (rhubarbe leases)"

#
alias all-off="rhubarbe bye"
alias rbye=all-off
doc-selection "switch off whole testbed"

alias ron="rhubarbe on"
alias on=ron
doc-selection "(r)on" "turn selected nodes on (rhubarbe on)"
alias roff="rhubarbe off"
alias off=roff
doc-selection "(r)off" "turn selected nodes off (rhubarbe off)"
alias rreset="rhubarbe reset"
alias reset=rreset
doc-selection "(r)reset" "reset selected nodes (rhubarbe reset)"

alias rstatus="rhubarbe status"
doc-selection "rstatus" "show status (on or off) selected nodes (rhubarbe status)"
alias st=rstatus
doc-selection "st" "like rstatus (status is a well-known command on ubuntu)"

alias rinfo="rhubarbe info"
alias info=rinfo
doc-selection "(r)info" "get version info from selected nodes CMC (rhubarbe info)"

alias rwait="rhubarbe wait"
doc-selection rwait "wait for nodes to be reachable through ssh (rhubarbe wait)"
alias rw=rwait
doc-selection rw alias


alias rusrpon="rhubarbe usrpon"
alias uon=rusrpon
doc-selection "rusrpon|uon" "turn selected nodes usrpon (rhubarbe usrpon)"

alias rusrpoff="rhubarbe usrpoff"
alias uoff=rusrpoff
doc-selection "rusrpoff|uoff" "turn selected nodes usrpoff (rhubarbe usrpoff)"

alias rusrpstatus="rhubarbe usrpstatus"
alias ust=rusrpstatus
doc-selection "rusrpstatus|ust" "show status (usrpon or usrpoff) of selected nodes USRP (rhubarbe usrpstatus)"

alias rload="rhubarbe load"
doc-selection rload "load image (specify with -i) on selected nodes (rhubarbe load)"
alias rsave="rhubarbe save"
doc-selection rsave "save image from one node (rhubarbe save)"
alias rshare="rhubarbe share"
doc-selection rshare "share image with community (rhubarbe share)"

# sequential - and mostly obsolete
function smap () {
    [ -z "$1" ] && { echo "usage: $0 command [args] - sequential map command on $NODES"; return; }
    for node in $NODES; do
	echo ==================== $node
	ssh root@$node "$@"
    done
}

# parallel version thanks to apssh
function map () {
    [ -z "$1" ] && { echo "usage: map command - runs command on $NODES with apssh"; return; }
    apssh -l root -t "$NODES" "$@"
}
alias rmap=map
doc-selection map "parallel run an ssh command on all selected nodes"

alias rimages="rhubarbe images"
doc-selection rimages "display available images (rhubarbe images)"
alias rresolve="rhubarbe resolve"
alias res="rhubarbe resolve"
doc-selection "res|rresolve" "show which file would be picked when doing rload -i (rhubarbe resolve)"

alias load-fedora="rload -i fedora"
doc-selection load-fedora alias
alias load-ubuntu="rload -i ubuntu"
doc-selection load-ubuntu alias

# releases
# -> show fedora/debian releases for $NODES
# releases 12 14
# -> show fedora/debian releases for fit12 fit14 - does not change NODES
function releases () {
    map "cat /etc/lsb-release /etc/fedora-release /etc/gnuradio-release 2> /dev/null | grep -i release; gnuradio-config-info --version 2> /dev/null || echo NO GNURADIO"
}
doc-selection releases "to display current release (ubuntu or fedora + gnuradio)"

function images () {
    map tail -1 /etc/rhubarbe-image
}
doc-selection images "show image info from last line from /etc/rhubarbe-image"

function prefix () {
    local token="$1"; shift
    sed -e "s/^/$token/"
}
# utility; run curl
function -curl () {
    local mode="$1"; shift
    [ -n "$1" ] && nodes="$@" || nodes="$NODES"
    local node
    for node in $(normreboot $nodes); do
	curl --silent http://$node/$mode | prefix "$node:"
    done
}

# using curl - just in case - should not be used
function con () { -curl on "$@" ; }
doc-alt con "turn on node through its CMC - using curl"
function coff () { -curl off "$@" ; }
doc-alt coff "turn off node through its CMC - using curl"
function creset () { -curl reset "$@" ; }
doc-alt creset "reset node through its CMC - using curl"
alias cstatus="-curl status "$@" ; "
doc-alt cstatus "show node CMC status - using curl"
alias cinfo="-curl info "$@" ; "
doc-alt cinfo "show node CMC info - using curl"

####################
# reload these tools
alias reload="source /home/faraday/r2lab/infra/user-env/faraday.sh"
# git pull and then reload; not allowed to everybody
function refresh() {
    [ $(id -u) == 0 ] || { echo refresh must be run by root; return 1; }
    /home/faraday/r2lab/auto-update.sh
    chown -R faraday:faraday ~faraday/r2lab
    reload
}
doc-alt refresh "install latest version of these utilities"

####################
# faraday has p2p1@switches and bemol has eth1 - use control_dev
# spy on frisbee traffic
doc-admin tcpdump-frisbee "tcpdump on port 7000 on the control interface"
function tcpdump-frisbee () {
    [ -n "$1" ] && options="-c $1"
    set -x
    tcpdump $options -i $control_dev port 7000
    set +x
}

####################
# prepare a node to boot on the standard pxe image - or another variant
# *) 2 special forms are
# -nextboot list
# -nextboot clean
# *) otherwise when invoked with
# -nextboot foo 32-34
# this script creates a symlink to /tftpboot/pxelinux.cfg/foo
function -nextboot () {
    local command="$1"; shift
    [ -n "$1" ] && nodes="$@" || nodes="$NODES"
    local node
    for node in $(norm $nodes); do
	local pxe=/tftpboot/pxelinux.cfg/"01-"$(py host_pxe $node)
	echo -n ABOUT $node " "
	case $command in
	    list)
		if [ -h $pxe ]; then
		    stat -c '%N' $pxe
		elif [ -f $pxe ]; then
		    ls -l $symlink
		else
		    echo no symlink found
		fi
		;;
	    clean)
		[ -f $pxe ] && { rm -f $pxe; echo CLEARED; } || echo absent
                ;;
            *) # specify config name as argument (e.g. the default is omf-6)
		dest=/tftpboot/pxelinux.cfg/$command
		[ -f $dest ] || { echo INVALID $dest - skipped; return; }
		[ -f $pxe ] && echo -n overwriting " "
		ln -sf $dest $pxe
		echo done
		;;
	esac
    done
}

alias nextboot-list="-nextboot list"
doc-admin nextboot-list "display pxelinux symlink, if found"
alias nextboot-clean="-nextboot clean"
doc-admin nextboot-clean "remove any pxelinux symlink for selected nodes"
alias nextboot-frisbee="-nextboot pxefrisbee"
doc-admin nextboot-frisbee "create pxelinux symlink so that node reboots on the pxefrisbee image"
alias nextboot-vivid="-nextboot pxevivid"
doc-admin nextboot-vivid "create pxelinux symlink so that node reboots on the vivid image - temporary"
alias nextboot-mini="-nextboot pxemini"
doc-admin nextboot-mini "create pxelinux symlink so that node reboots on the mini image - temporary"

# for double checking only
function nextboot-ll () {
    ls -l /tftpboot/pxelinux.cfg/
}
doc-admin nextboot-ll "use ll to list all pxelinux.cfg contents - for doublechecking"

# list pending next boot config files
# -nextboot list or -nextboot clean
function -nextboot-all () {
    local command=$1; shift
    local hex="[0-9a-f]"
    local byte="$hex$hex"
    local pattern=$byte
    local i
    for i in $(seq 6); do pattern=$pattern-$byte; done
    local symlink
    for symlink in $(ls /tftpboot/pxelinux.cfg/$pattern 2> /dev/null); do
	local name=$(basename $symlink)
	local hostname=$(py pxe_host $name)
	echo -n ABOUT $hostname " "
	case $command in
	    list*)
		[ -h $symlink ] && stat -c '%N' $symlink || ls -l $symlink ;;
	    clean*)
		echo ABOUT $hostname: clearing $symlink; rm -f $symlink ;;
	esac
    done
}

function nextboot-listall () { -nextboot-all list; }
doc-alt nextboot-listall "list all pxelinux symlinks"
function nextboot-cleanall () { -nextboot-all clean; }
doc-alt nextboot-cleanall "remove all pxelinux symlinks"

####################
# ss 5 -> ssh fit05
# tn -> telnet fit04
#
function -do-first () {
    local command="$1"; shift
    local node
    if [ -n "$1" ] ; then
	node=$(norm $1)
    else
	[ -z "$NODES" ] && { echo you need to set at least one node; return 1; }
	node=$(echo $NODES | awk '{print $1;}')
    fi
    echo "Running $command $node"
    $command -l root $node
}

doc-selection ssh1n "Enter first selected node using ssh\n\t\tWARNING: arg if present is taken as a node, not a command"
alias ssh1n="-do-first ssh"

doc-selection ssh1nx "Same as ssh1n but with ssh -X"
alias ssh1nx="-do-first 'ssh -X'"

doc-admin tln1n "Enter first selected node using telnet - ditto"
alias tln1n="-do-first telnet"

doc-selection s "alias for ssh1n"
alias s="ssh1n"
doc-selection sx "alias for ssh1nx"
alias sx="ssh1x"

####################
# look at logs
alias logs-dns="tail -f /var/log/dnsmasqfit.log"
doc-admin logs-dns alias

# talk to switches
function sw-c007 () { ssh switch-c007; }
function sw-data () { ssh switch-data; }
function sw-reboot () { ssh switch-reboot; }
function sw-control () { ssh switch-control; }
function ping-switches () { for i in c007 data reboot control; do pnv switch-$i; done ; }
alias sw=ping-switches
doc-admin sw "ping all 4 faraday switches"

##########
function chmod-private-key () {
    chmod 600 ~/.ssh/id_rsa
}
doc-alt chmod-private-key "Chmod private key so that ssh won't complain anymore"

##########
alias images-repo="cd /var/lib/rhubarbe-images/"
doc-admin images-repo alias

####################
ADMIN=inria_r2lab.admin

alias admin-account="su - $ADMIN"
doc-admin admin-account alias

alias jou-monitor="jou -f monitor"
doc-admin jou-monitor alias
alias log-monitor="tail -f /var/log/monitor.log"
doc-admin log-monitor alias

alias jou-accounts="jou -f accountsmanager"
doc-admin jou-accounts alias

alias jou-faraday="jou -f monitor accountsmanager"
doc-admin jou-faraday alias

####################
alias rhubarbe-update='pip3 install --upgrade rhubarbe; rhubarbe version'
doc-admin rhubarbe-update alias

########## check nodes info
doc-admin info "get info from CMC"
function info () { rhubarbe info "$@"; }

##########
# utility to untar a bunch of tgz files as obtained typically
# from logs captured by the oai logs-tgz utility
function un-tgz() {
    if [[ -z "$@" ]]; then
	echo "usage $0 tgz..files"
	return
    fi
    local t
    for t in "$@"; do
	b=$(basename $t .tgz)
	echo Unwrapping $t in $b
	mkdir $b
	tar -C $b -xzf  $t
    done
}

########## connect to the phone gateway
# the private key for macphone is in inventory/macphone
function -macphone() {
    macphoneid=$1; shift
    ssh -o StrictHostKeyChecking=no -i /home/faraday/r2lab/inventory/macphone tester@macphone${i} "$@"
}

doc-alt macphone1 "ssh-enter phone gateway 'macphone1' as user 'tester'"
function macphone1() { -macphone 1 "$@"; }
# for legacy; somehow it seems to be important that it is a function
# otherwise the oai-scenario has been reported to fail
function macphone() { -macphone 1 "$@"; }
doc-alt macphone2 "ssh-enter phone gateway 'macphone2' as user 'tester'"
function macphone2() { -macphone 2 "$@"; }


doc-selection-sep "See also help-alt for other commands"

########################################
doc-admin nightly "run nightly routine | nightly -N all | nightly -N <nodes> -e <email result> -a <avoid nodes>"
function nightly () {
  read -p "run nightly? (y/n)" CONT
  if [ "$CONT" = "y" ]; then
    python /root/r2lab/nightly/nightly.py "$@"
  fi
}

doc-admin inspect "check the status of a default domain list and some other customized services"
function inspect () {
  python3 /root/r2lab/infra/inspect/inspect.py "$@"
}

doc-admin maintenance "update a json file which contains information about nodes maintenance | maitenance -i|r <node> -m <the message>"
function maintenance () {
  python3 /root/r2lab/nodes/maintenance.py "$@"
}

# info is already used for the CMC verb
doc-admin information "to be completed"
function information () {
  python3 /root/r2lab/nodes/information.py "$@"
}

doc-admin table "to be completed"
function table () {
  python3 /root/r2lab/nodes/table.py "$@"
}

doc-admin publish "to be completed"
function publish () {
  /root/r2lab/infra/scripts/sync-nightly-results-at-r2lab.sh
  echo 'INFO: send info to r2lab website and updating...'
  ssh root@r2lab.inria.fr /root/r2lab/infra/scripts/restart-website.sh
  echo 'INFO: updated in r2lab!'
}

# refresh is all about /home/faraday/r2lab (that is readable by all)
# when using the nodes/ utilities we need to git pull in /root/r2lab
doc-admin refresh-root "git pull in /root/r2lab"
function refresh-root() {
    (cd /root/r2lab; git pull)
}

########################################
doc-alt all-off "Switch off everything"
function all-off() {
    rhubarbe usrpoff -a
    sleep 1
    rhubarbe off -a
    macphone phone-off
}

########################################
define-main "$0" "$BASH_SOURCE"
main "$@"
