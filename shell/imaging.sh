#!/bin/bash

source $(dirname $(readlink -f $BASH_SOURCE))/r2labutils.sh

create-doc-category imaging "tools for creating images"
augment-help-with imaging

########################################
# UBUNTU
########################################

# looks like dpkg -i $url won't work ..
# so this utility fetches a bunch of URLs and shoves them into dpkg
function -dpkg-from-urls() {
    urls="$@"
    debs=""
    for url in $urls; do
        echo ==================== fetching deb at url
        echo "$url"
	curl -O $url
	debs="$debs $(basename $url)"
    done
    
    if dpkg -i $debs; then
	rm $debs
	return 0
    else
	echo dpkg failed - preserving debs $debs
	return 1
    fi
}

function -dpkg-is-installed() {
    package="$1"
    if dpkg -l $package >& /dev/null; then
	echo package $package already installed
	return 0
    else
	return 1
    fi
}

####################
# started with this howto here:
# http://ubuntuhandbook.org/index.php/2016/07/install-linux-kernel-4-7-ubuntu-16-04/
# see also of course here for any new stuff:
# http://kernel.ubuntu.com/~kernel-ppa/mainline/v4.7/
# won't work with ubuntu-14 though
doc-imaging ubuntu-k47-lowlatency "install 4.7 lowlatency kernel"
function ubuntu-k47-lowlatency() {
    
    -dpkg-is-installed linux-image-4.7.0-040700-lowlatency && return
    
    urls="
http://kernel.ubuntu.com/~kernel-ppa/mainline/v4.7/linux-headers-4.7.0-040700_4.7.0-040700.201608021801_all.deb
http://kernel.ubuntu.com/~kernel-ppa/mainline/v4.7/linux-headers-4.7.0-040700-lowlatency_4.7.0-040700.201608021801_amd64.deb
http://kernel.ubuntu.com/~kernel-ppa/mainline/v4.7/linux-headers-4.7.0-040700-generic_4.7.0-040700.201608021801_amd64.deb
http://kernel.ubuntu.com/~kernel-ppa/mainline/v4.7/linux-image-4.7.0-040700-lowlatency_4.7.0-040700.201608021801_amd64.deb
"

    -dpkg-from-urls $urls
}

# this one is based on the mainstream kernel for 16.10/yikkety
# it works fine on top of both ubuntu 14 and ubuntu 16
function ubuntu-k48-lowlatency() {

    local k48_ver="4.8.0-59"
    local k48_sub="64"
    
    -dpkg-is-installed linux-image-${k48_ver}-lowlatency && return
    
    local k48_lon="${k48_ver}.${k48_sub}"

    urls="
http://fr.archive.ubuntu.com/ubuntu/pool/main/l/linux/linux-headers-${k48_ver}_${k48_lon}_all.deb
http://fr.archive.ubuntu.com/ubuntu/pool/main/l/linux/linux-headers-${k48_ver}-lowlatency_${k48_lon}_amd64.deb
http://fr.archive.ubuntu.com/ubuntu/pool/main/l/linux/linux-headers-${k48_ver}-generic_${k48_lon}_amd64.deb
http://fr.archive.ubuntu.com/ubuntu/pool/main/l/linux/linux-image-${k48_ver}-lowlatency_${k48_lon}_amd64.deb
"

    -dpkg-from-urls $urls

}

# this is to tweak the grub config so it boots off a newly-installed kernel
# it might turn out a little fragile over time, in the sense that "1>2" is
# incidentally the formula to use on a node that had a single kernel installed
# and then another one is installed on top
# 1>2 means second menu entry (a submenu), and third entry in there
# you can do a visual inspection as follows
# using a menu_specification of 0 would mean the first 'Ubuntu' option
# 1 refers to the 'submenu' below
# in which 2 refers to the third entry, i.e. 3.19.0-031900-lowlatency non-recovery
###
### root@localhost:/boot/grub# grep menuentry grub.cfg
### <snip>
### menuentry 'Ubuntu' --class ubuntu --class gnu-linux --class gnu --class os <blabla>
### submenu 'Advanced options for Ubuntu' $menuentry_id_option <blabla>
### 	menuentry 'Ubuntu, with Linux 4.2.0-27-generic' --class ubuntu --class gnu-linux --class gnu --class os <blabla>
### 	menuentry 'Ubuntu, with Linux 4.2.0-27-generic (recovery mode)' --class ubuntu --class gnu-linux --class gnu --class os <blabla>
### 	menuentry 'Ubuntu, with Linux 3.19.0-031900-lowlatency' --class ubuntu --class gnu-linux --class gnu --class os <blabla>
### 	menuentry 'Ubuntu, with Linux 3.19.0-031900-lowlatency (recovery mode)' --class ubuntu --class gnu-linux --class gnu --class os <blabla>
### menuentry 'Memory test (memtest86+)' {
### menuentry 'Memory test (memtest86+, serial console 115200)' {
### 
function ubuntu-grub-update() {
    menu_specification="$1"; shift
    [ -z "$menu_specification" ] && menu_specification="1>2"
    cd /etc/default
    sed -i -e "s|GRUB_DEFAULT=.*|GRUB_DEFAULT=\"$menu_specification\"|" grub
    update-grub
}

# enb insists on running on 3.19
function ubuntu-k319-lowlatency() {

    # this recipe proposed by Rohit won't work for us
    # apt-get -y install linux-image-3.19.0-61-lowlatency linux-headers-3.19.0-61-lowlatency
    
    # let's go back to ours
    # XXX this however is not enough as it won't change the default kernel for grub
    -dpkg-is-installed linux-image-3.19.0-031900-lowlatency && return
    
    urls="
http://kernel.ubuntu.com/~kernel-ppa/mainline/v3.19-vivid/linux-headers-3.19.0-031900_3.19.0-031900.201504091832_all.deb
http://kernel.ubuntu.com/~kernel-ppa/mainline/v3.19-vivid/linux-headers-3.19.0-031900-generic_3.19.0-031900.201504091832_amd64.deb
http://kernel.ubuntu.com/~kernel-ppa/mainline/v3.19-vivid/linux-headers-3.19.0-031900-lowlatency_3.19.0-031900.201504091832_amd64.deb
http://kernel.ubuntu.com/~kernel-ppa/mainline/v3.19-vivid/linux-image-3.19.0-031900-lowlatency_3.19.0-031900.201504091832_amd64.deb
"

    -dpkg-from-urls $urls
    ubuntu-grub-update
}

function change-Kconfig-default () {
    kconfig=$1; shift
    config_name=$1; shift
    new_default=$1; shift
    # instruct sed to work on a range defined by 2 patterns
    sed "/config ${config_name}/,/config / s/default.*/default ${new_default}/"\
	--in-place=.debian $kconfig
}

# initially based on this article
# https://renaudcerrato.github.io/2016/05/30/build-your-homemade-router-part3/
# that patch seems to be useless though
# also based on this howto
# https://wiki.ubuntu.com/Kernel/BuildYourOwnKernel

# a space to rebuild kernels
kbuildroot=/root/kernel-build

doc-imaging ubuntu-atheros-noreg "allow the atheros driver to tweak regulatory domain - for vanilla ubuntu"
function ubuntu-atheros-noreg() {

    # create space
    mkdir -p $kbuildroot
    cd $kbuildroot

    # need to turn on the deb-src clauses in /etc/apt/sources.list
    sed -i -e 's,^# *deb-src,deb-src,' /etc/apt/sources.list
    apt-get -y update

    local VERSION=$(uname -r)
    # VERSION=4.4.0-21-generic
    local SHORT_VERSION=${VERSION%%-*}
    # SHORT_VERSION=4.4.0

    # get the stuff from ubuntu
    apt-get -y build-dep linux-image-${VERSION}
    apt-get -y source linux-image-${VERSION}

    cd linux-${SHORT_VERSION}

    # define EXTRAVERSION in main Makefile
    # this does not seem to make it in the running uname though...
    sed --in-place=.debian -e "s,^EXTRAVERSION.*,EXTRAVERSION = athnoreg," Makefile

    # change configuration
    change-Kconfig-default net/wireless/Kconfig CFG80211_CERTIFICATION_ONUS y
    change-Kconfig-default drivers/net/wireless/ath/Kconfig ATH_REG_DYNAMIC_USER_REG_HINTS y

    # apply patch
    # using the patch from our repo
    local patch_url=https://raw.githubusercontent.com/parmentelat/r2lab/public/infra/patches/ath-noreg.patch
    wget -O - $patch_url | patch -p1 -b
    
    debian/rules clean
    debian/rules binary-headers
    debian/rules binary-generic
    debian/rules binary-perarch

    # at that point we need to install the .deb packages
    cd $kbuildroot
    dpkg -i  linux-{headers,image}*${SHORT_VERSION}*.deb
    
    # the .deb are interesting in themselves, so we can shove this kernel in other
    # images; so, let's finish this step here so that
    # we can first save the full image even if it's huge
    cd 
    return
}

doc-imaging clean-kernel-build "clean up $kbuildroot after kernel building"
function clean-kernel-build () {
    
    # cleanup - it can be huge
    # typically this area is 14Gb large after ubuntu-atheros-noreg, and makes for a 6Gb+ image
    # which can be reduced down to 
    cd
    rm -rf $kbuildroot
}

doc-imaging ubuntu-setup-ntp "install and start ntp"
function ubuntu-setup-ntp () {
    apt-get -y install ntp ntpdate
    # let's not tweak ntp.conf, use DHCP instead
    # see faraday:/etc/dnsmasq.conf
    systemctl restart ntp || service ntp start
    # I have no idea how to do this on systemctl-less ubuntus
    # hopefully the dpkg install will do it
    systemctl enable ntp || echo "systemctl-less ubuntus : not supported"
}

doc-imaging "ubuntu-setup-ssh: tweaks sshd_config, remove dummy r2lab user, remove root password, restart ssh"
function ubuntu-setup-ssh () {

####################
# expected result is this
# root@r2lab:/etc/ssh# grep -v '^#' /etc/ssh/sshd_config | egrep -i 'Root|Password|PAM'
# PermitRootLogin yes
# PermitEmptyPasswords yes
# PasswordAuthentication yes
# UsePAM no

    # tweak sshd_config
    sed -i.utilities \
	-e 's,^#\?PermitRootLogin.*,PermitRootLogin yes,' \
	-e 's,^#\?PermitEmptyPasswords.*,PermitEmptyPasswords yes,' \
	-e 's,^#\?PasswordAuthentication.*,PasswordAuthentication yes,' \
	-e 's,^#\?UsePAM.*,UsePAM no,' \
	/etc/ssh/sshd_config

    # remove dummy user
    userdel --remove ubuntu

    # remove root password
    passwd --delete root
    
    # restart ssh
    echo "Restarting sshd"
    type systemctl >& /dev/null \
	&& systemctl restart sshd \
        || service ssh restart
    cat << EOF
You should now be able to ssh as root without a password
CHECK IT NOW before you quit this session
EOF
}


doc-imaging "ubuntu-base: remove /etc/hostname, install base packages"
function ubuntu-base () {
    ###
    rm /etc/hostname

    packages="
rsync git make gcc emacs24-nox
iw ethtool tcpdump wireshark bridge-utils
"

    apt-get -y update
    apt-get -y install $packages
}


doc-imaging "ubuntu-interfaces: overwrite /etc/network/interfaces"
function ubuntu-interfaces () {
    cat > /etc/network/interfaces <<EOF
source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# the control network interface - required
auto control
iface control inet dhcp

# the data network interface - optional
#auto data
iface data inet dhcp
EOF

}


doc-imaging "ubuntu-dev: add udev rules for canonical interface names"
function network-names-udev () {
####################
# udev
#
# see insightful doc in
# http://reactivated.net/writing_udev_rules.html 
#
# on ubuntu, to see data about a given device (udevinfo not available)
# udevadm info -q all -n /sys/class/net/p2p1
#  -- or --     (more simply)
# udevadm info /sys/class/net/p2p1
#  -- or --
# udevadm info --attribute-walk /sys/class/net/wlp1s0
# 
# create new udev rules for device names - hopefully fine on both distros ?
# 
# p2p1 = control = igb = enp3s0
# eth0 = data = e1000e = enp0s25

cat > /etc/udev/rules.d/70-persistent-net.rules <<EOF
# kernel name would be enp3s0
SUBSYSTEM=="net", ACTION=="add", DRIVERS=="igb", NAME="control"
# kernel name would be enp0s25
SUBSYSTEM=="net", ACTION=="add", DRIVERS=="e1000e", NAME="data"
EOF

# extra rules for fedora and wireless devices
# might work on ubuntu as well
# but was not used when doing the ubuntu15.04 image in the first place
# Nov. 18 2016
# I add ATTR{type}=="1" to distinguish between the real interface
# and mon0, like in 'iw dev intel interface add mon0 type monitor'
# which otherwise ends up in rename<xx> and everything is screwed up
cat > /etc/udev/rules.d/70-persistent-wireless.rules <<EOF
# this is the card connected through the PCI adapter
KERNELS=="0000:00:01.0", ATTR{type}=="1", ACTION=="add", NAME="intel"
# and this is the one in the second miniPCI slot
KERNELS=="0000:04:00.0", ATTR{type}=="1", ACTION=="add", NAME="atheros"
EOF

}

doc-imaging activate-lowlatency "activate low-latency functionality"
function activate-lowlatency() {

    echo "========== Setting up cpufrequtils"
    apt-get install -y cpufrequtils i7z
    echo 'GOVERNOR="performance"' > /etc/default/cpufrequtils
    update-rc.d ondemand disable
    /etc/init.d/cpufrequtils restart
    # xxx turning off hyperthreading
    sed -i -e 's|GRUB_CMDLINE_LINUX_DEFAULT.*|GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_pstate=disable processor.max_cstate=1 intel_idle.max_cstate=0 idle=poll"|' /etc/default/grub
    update-grub
    echo 'blacklist intel_powerclamp' >> /etc/modprobe.d/blacklist.conf
}


doc-imaging install-e3372 "install E3372 functionality"
function install-e3372() {

    apt-get update
    apt-get install -y usb-modeswitch
    apt-get install -y firefox  # can be useful to handle Huawei web interface config
    
    echo "========== add /etc/usb_modeswitch.conf file"
    cat > /etc/usb_modeswitch.conf <<EOF
#######################################################
# Huawei E353 (3.se)
#
# Contributor: Ulf Eklund

DefaultVendor= 0x12d1
DefaultProduct=0x1f01

TargetVendor=  0x12d1
TargetProduct= 0x14dc

MessageContent="55534243123456780000000000000a11062000000000000100000000000000"

# Driver is cdc_ether
NoDriverLoading=1
EOF

    # add the network interface for the Huawei E3372 LTE USB stick
    echo "========== add E3372 network interface configuration to /etc/network/interfaces"
    echo "# the Huawei E3372 LTE network interface - optional" >> /etc/network/interfaces
    echo "#auto enx0c5b8f279a64" >> /etc/network/interfaces
    echo "iface enx0c5b8f279a64 inet dhcp" >> /etc/network/interfaces
}


doc-imaging install-gnuradio "install gnuradio package with uhd"
function install-gnuradio() {
    apt-get update 
    apt-get -y install libuhd-dev libuhd003 uhd-host gnuradio 
}


########################################
# FEDORA
########################################
doc-imaging fedora-base "minimal packages"
function fedora-base() {
    rm /etc/hostname
    packages=" rsync git make gcc emacs-nox wireshark"
    dnf -y install $packages
}

doc-imaging fedora-setup-ntp "installs ntp"
function fedora-setup-ntp() {
    dnf -y install ntp
    systemctl enable ntpd
    systemctl start ntpd
}

# most likely there are much smarter ways to do that..
doc-imaging fedora-ifcfg "overwrite /etc/sysconfig/networks-scripts"
function fedora-ifcfg() {
    echo WARNING fedora-interfaces might be brittle
    cd /etc/sysconfig/network-scripts
    for renaming in enp3s0:control enp0s25:data; do
	oldname=$(cut -d: -f1 <<< $renaming)
	newname=$(cut -d: -f2 <<< $renaming)
	oldfile=ifcfg-$oldname
	newfile=ifcfg-$newname
	if [ -f $oldfile ]; then
	    echo Creating $newfile to replace $oldfile
	    sed -e "s,$oldname,$newname,g" $oldfile > $newfile
	    rm $oldfile
	else
	    echo Could not find file $oldfile in $(pwd)
	fi
    done
}

########################################
# common
########################################
doc-imaging "common-setup-r2lab-repo: set up /root/r2lab"
function common-setup-r2lab-repo () {
    type -p git 2> /dev/null || { echo "git not installed - cannot proceed"; return; }
    cd /root
    [ -d r2lab ] || git clone https://github.com/parmentelat/r2lab.git
    cd /root/r2lab
    git pull
}

doc-imaging "common-setup-user-env: add infra/user-env/nodes.sh to /etc/profile.d and /root/.bash*"
function common-setup-root-bash () {
    cd /etc/profile.d
    ln -sf /root/r2lab/infra/user-env/nodes.sh .
    cd /root
    ln -sf /etc/profile.d/nodes.sh .bash_profile
    ln -sf /etc/profile.d/nodes.sh .bashrc
    # to make sure to undo previous versions that were wrong in creating this
    rm -f /root/r2lab/infra/r2labutils.sh
    
}

doc-imaging "common-setup-node-ssh-key: install standard R2lab key as the ssh node's key"
function common-setup-node-ssh-key () {
    [ -d /root/r2lab ] || { echo /root/r2lab/ not found - exiting; return; }
    cd /root/r2lab
    git pull
    [ -d /root/r2lab/rhubarbe-images/keys ] || {
	echo "Cannot find standard R2lab node keys - cannot proceed"; return;
    }
    rsync -av /root/r2lab/rhubarbe-images/keys/ /etc/ssh/
    chown -R root:root /etc/ssh/*key*
    chmod 600 /etc/ssh/*key
    chmod 644 /etc/ssh/*key.pub
}

# all-in-one
function common-setup() {
    common-setup-r2lab-repo
    common-setup-root-bash
    common-setup-node-ssh-key
}

########################################
define-main "$0" "$BASH_SOURCE"
main "$@"
