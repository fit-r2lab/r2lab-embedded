source $(dirname $(readlink -f $BASH_SOURCE))/nodes.sh

# this is included (i.e. source'd) from places that all have
# included nodes.sh
# so in this context we have done
# create-doc-category nodes
# and so doc-nodes and doc-nodes-sep are available

# nominally we'd like to use the data network
mosaic_realm="r2lab.fr"
mosaic_ifname=data
mosaic_subnet=2

mosaic_role="redefine-me"
mosaic_long="redefine-me"


function mosaic-as-cn() {
    git-pull-r2lab
    ln -sf /root/r2lab-embedded/shell/mosaic-cn.sh /etc/profile.d
}

function mosaic-as-ran() {
    git-pull-r2lab
    ln -sf /root/r2lab-embedded/shell/mosaic-ran.sh /etc/profile.d
}


# the options to use with snap for these packages
function -snap-install() {
    local package=$1; shift
    local command="snap install --channel=edge --devmode $package"
    echo "Installing: $command"
    $command
}

function -enable-snap-bins() {
    echo $PATH | grep -q /snap/bin || export PATH=$PATH:/snap/bin
}


###### helpers
# basic tool to ease patches; expects
# (*) on the command line the file to patch
# (*) on stdin a sed file to apply on that file
function -sed-configurator() {
    local target=$1; shift
    local original=$target.orig
    local stem=$(basename $target)
    local sedname=/tmp/$stem.$$.sed
    local tmptarget=/tmp/$stem.$$

    # store stdin in a file
    cat > $sedname

    # be explicit about backups
    [ -f $original ] || { echo "Backing up $target"; cp $target $original; }

    # compute new version; preserve modes
    cp $target $tmptarget
    # give an extension to -i so that it also works on mac for devel
    sed -f $sedname -i.4mac $tmptarget
    # change target only if needed
    cmp --silent $target $tmptarget || {
        echo "(Over)writing $target (through $sedname)"
        mv -f $tmptarget $target
    }
}

# convenient for debugging
doc-admin inspect-config-diffs "Show differences about modified config files"
function inspect-config-diffs() {
    for orig in *.orig; do
        local current=$(basename $orig .orig)
        echo ==================== $orig - $current
        diff $orig $current
    done
}
############################ xxx potentially old stuff - check if still relevant


####################
doc-nodes capture "expects one arg - capture logs and datas and configs under provided name, suffixed with -\$mosaic_role"
function capture() {
    local run_name="$1"; shift
    local role="$1"; shift
    [ -z "$role" ] && role="$mosaic_role"
    capture-all "${run_name}-${role}"
}

####################
# designed for interactive usage; tcpdump stops upon Control-C
doc-nodes tcpdump-sctp "interactive tcpdump of the SCTP traffic on interface ${mosaic_ifname}
                with one arg, stores into a .pcap"
function tcpdump-sctp() {
    local output="$1"; shift
    command="tcpdump -i ${mosaic_ifname} ip proto 132"
    [ -n "$output" ] && {
        local file="${output}-${mosaic_role}.pcap"
        echo "Capturing (unbuffered) into $file"
        command="$command -w $file -U"
    }
    echo Running $command
    $command
}

##########
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

doc-nodes node-has-limesdr "Check if a LimeSDR is attached to the node"
function node-has-limesdr() {
    ls /usr/local/bin/LimeUtil >& /dev/null || {
        echo "you need to install LimeUtil"; return 1;}
    [ -n "$(/usr/local/bin/LimeUtil --find)" ]
}

##########
doc-nodes-sep

########################################
define-main "$0" "$BASH_SOURCE"
main "$@"
