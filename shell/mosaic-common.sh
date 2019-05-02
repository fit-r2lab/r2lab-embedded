_sourced_mosaic_common=true

[ -z "$_sourced_nodes" ] && source $(dirname $(readlink -f $BASH_SOURCE))/nodes.sh

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
    -have-bashrc-source /etc/profile.d/mosaic-cn.sh _sourced_mosaic_cn
}

function mosaic-as-ran() {
    git-pull-r2lab
    ln -sf /root/r2lab-embedded/shell/mosaic-ran.sh /etc/profile.d
    -have-bashrc-source /etc/profile.d/mosaic-ran.sh _sourced_mosaic_ran
}

function mosaic-as-oai-ue() {
    git-pull-r2lab
    ln -sf /root/r2lab-embedded/shell/mosaic-oai-ue.sh /etc/profile.d
    -have-bashrc-source /etc/profile.d/mosaic-oai-ue.sh _sourced_mosaic_oai_ue
}


# the options to use with snap for these packages
function -snap-install() {
    local package=$1; shift
    local command="snap install --channel=edge --devmode $package"
    echo "Installing: $command"
    $command
    -have-bashrc-source /etc/profile.d/apps-bin-path.sh
    source /etc/profile.d/apps-bin-path.sh
}


############################ xxx potentially old stuff - check if still relevant


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
doc-nodes-sep

########################################
define-main "$0" "$BASH_SOURCE"
main "$@"
