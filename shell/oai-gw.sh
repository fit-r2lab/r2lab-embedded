#!/bin/bash

source $(dirname $(readlink -f $BASH_SOURCE))/nodes.sh

source $(dirname $(readlink -f $BASH_SOURCE))/oai-common.sh

COMMAND=$(basename "$BASH_SOURCE")
case $COMMAND in
    *oai-gw*)
	runs_epc=true; runs_hss=true; oai_role=epc ;;
    *oai-hss*)
	runs_epc=;     runs_hss=true; oai_role=hss ;;
    *oai-epc*)
	runs_epc=true; runs_hss=    ; oai_role=epc ;;
    *)
	echo OOPS ;;
esac
    
doc-nodes-sep "#################### commands for managing an OAI gateway"

####################
run_dir=/root/openair-cn/scripts
[ -n "$runs_hss" ] && {
    log_hss=$run_dir/hss.log
    add-to-logs $log_hss
    template_dir=/root/openair-cn/etc/
    conf_dir=/usr/local/etc/oai
    add-to-configs $conf_dir/hss.conf
    add-to-configs $conf_dir/freeDiameter/hss_fd.conf
}
[ -n "$runs_epc" ] && {
    log_mme=$run_dir/mme.log; add-to-logs $log_mme
    out_mme=$run_dir/mme.out; add-to-logs $out_mme
    log_spgw=$run_dir/spgw.log; add-to-logs $log_spgw
    out_spgw=$run_dir/spgw.out; add-to-logs $out_spgw
    template_dir=/root/openair-cn/etc/
    conf_dir=/usr/local/etc/oai
    add-to-configs $conf_dir/mme.conf
    add-to-configs $conf_dir/freeDiameter/mme_fd.conf
    add-to-configs $conf_dir/spgw.conf
    add-to-datas /etc/hosts
}

doc-nodes dumpvars "list environment variables"
function dumpvars() {
    echo "oai_role=${oai_role}"
    echo "oai_ifname=${oai_ifname}"
    echo "runs_hss=$runs_hss"
    echo "runs_epc=$runs_epc"
    echo "run_dir=$run_dir"
    echo "template_dir=$template_dir"
    echo "conf_dir=$conf_dir"
    [[ -z "$@" ]] && return
    echo "_configs=\"$(get-configs)\""
    echo "_logs=\"$(get-logs)\""
    echo "_datas=\"$(get-datas)\""
    echo "_locks=\"$(get-locks)\""
}

####################
doc-nodes image "the entry point for nightly image builds"
function image() {
    dumpvars
    base
    deps
    build
}

#####
# would make sense to add more stuff in the base image - see the NEWS file
base_packages="git subversion cmake build-essential gdb"

doc-nodes base "the script to install base software on top of a raw u16 low-latency image"
function base() {


    git-pull-r2lab
    git-pull-oai
    # apt-get requirements
    apt-get update
    apt-get install -y $base_packages

    # use debconf-get-selections | grep mysql-server
    # to see the available settings
    # this requires
    # apt-get install -y debconf-utils

    echo "========== Installing mysql-server"
    debconf-set-selections <<< 'mysql-server mysql-server/root_password password linux'
    debconf-set-selections <<< 'mysql-server mysql-server/root_password_again password linux'
    apt-get install -y mysql-server

    echo "========== Installing phpmyadmin - provide mysql-server password as linux and set password=admin"
    debconf-set-selections <<< 'phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2' 
    debconf-set-selections <<< 'phpmyadmin phpmyadmin/dbconfig-install boolean true' 
    # the one we used just above for mysql-server
    debconf-set-selections <<< 'phpmyadmin phpmyadmin/mysql/admin-pass password linux'
    # password for phpadmin itself
    debconf-set-selections <<< 'phpmyadmin phpmyadmin/mysql/app-pass password admin' 
    debconf-set-selections <<< 'phpmyadmin phpmyadmin/app-password-confirm password admin' 
    apt-get install -y phpmyadmin

    echo "========== Running git clone for openair-cn and r2lab .."
    git-ssl-turn-off-verification
    cd
    [ -d openair-cn ] || git clone https://gitlab.eurecom.fr/oai/openair-cn.git
    # this is probably useless, but well
    [ -d r2lab ] || git clone https://github.com/parmentelat/r2lab.git

##   Following is now useless as it is done in the u16 low-latency image and it requires a reboot to be active
#    echo "========== Setting up cpufrequtils"
#    apt-get install -y cpufrequtils
#    echo 'GOVERNOR="performance"' > /etc/default/cpufrequtils
#    update-rc.d ondemand disable
#    /etc/init.d/cpufrequtils restart
#    # this seems to be purely informative ?
#    cd
#    cpufreq-info > cpufreq.info

}

doc-nodes deps "builds hss and epc and installs dependencies" 
function deps() {
    
    git-pull-r2lab
    git-pull-oai
    cd $run_dir
    echo "========== Building HSS"
    run-in-log  build-hss-deps.log ./build_hss -c -i -F
    echo "========== Building EPC"
    run-in-log build-mme-deps.log ./build_mme -c -i -f
    run-in-log build-spgw-deps.log ./build_spgw -c -i -f
    # building the kernel module : deferred to the init step
    # it looks like it won't run fine at that early stage
}

#################### build
function build() {
    build-hss
    build-epc
}
doc-nodes build "function"

function build-hss() {
    cd $run_dir
    run-in-log build-hss-remote.log ./build_hss --clean
}

function build-epc() {
    echo "========== Rebuilding mme"
    # option --debug is in the doc but not in the code
    run-in-log build-mme.log ./build_mme --clean
    
    echo "========== Rebuilding spgw"
    run-in-log build-spgw.log ./build_spgw --clean
}    

########################################
# end of image
########################################

function run-all() {
    oai_role=$1; shift
    peer=$1; shift
    stop
    status
    init
    configure $peer
    start-tcpdump-data ${oai_role}
    start
    status
    return 0
}

# the output of start-tcpdump-data
add-to-datas "/root/data-${oai_role}.pcap"

doc-nodes run-hss "run-hss 12: does init/configure/start with epc running on node 12"
function run-hss() { run-all hss "$@"; }

doc-nodes run-epc "run-epc 12: does init/configure/start with hss running on node 12"
function run-epc() { run-all epc "$@"; }

doc-nodes init "sync clock from NTP, checks /etc/hosts, and tweaks MTU's"
function init() {

    git-pull-r2lab   # calls to git-pull-oai should be explicit from the caller if desired
    # clock
    init-ntp-clock
    # data interface if relevant
    [ "$oai_ifname" == data ] && echo Checking interface is up : $(turn-on-data)
    for interface in data control; do
	echo "========== setting mtu to 9000 on interface $interface"
	ip link set dev $interface mtu 9000
#	echo "========== turning on offload negociations on $interface"
#	offload-on $interface
    done
    # TO BE VERIFIED WITH LIONEL IF GTP MODULE LOADING SHOULD BE MANUAL OR DONE WITHIN THE BUILD
    # for now, do it manually...
    modprobe gtp

    enable-nat-data
}

#################### configure
function clean-hosts() {
    sed --in-place '/fit/d' /etc/hosts
    sed --in-place '/hss/d' /etc/hosts
}

doc-nodes check-etc-hosts "adjusts /etc/hosts; run with hss as first arg to define hss"
function check-etc-hosts() {
    hss_id=$1; shift
    [ -z "$hss_id" ] && { echo "check-etc-hosts requires hss-id - exiting" ; return ; }
    echo "========== Checking /etc/hosts"
    clean-hosts

    id=$(r2lab-id)
    fitid=fit$id
    id=$(echo $id | sed  's/^0*//')
    hss_id=$(echo $hss_id | sed  's/^0*//')

    if [ -n "$runs_hss" -a -n "$runs_epc" ]; then
	# box runs both services
	echo "127.0.1.1 $fitid.${oai_realm} $fitid hss.${oai_realm} hss" >> /etc/hosts
    elif [ -n "$runs_hss" ]; then
	# HSS only
	echo "127.0.1.1 $fitid.${oai_realm} $fitid" >> /etc/hosts
	echo "192.168.${oai_subnet}.${id} hss.${oai_realm} hss" >> /etc/hosts
    else
	[ -z "$hss_id" ] && { echo "ERROR: no peer defined"; return; }
	echo "Using HSS on $hss_id"
	echo "127.0.1.1 $fitid.${oai_realm} $fitid" >> /etc/hosts
	echo "192.168.${oai_subnet}.${hss_id} hss.${oai_realm} hss" >> /etc/hosts
    fi
}
	
    
function configure() {
    configure-hss "$@"
    configure-epc "$@"
}
doc-nodes configure function

function configure-epc() {

    [ -n "$runs_epc" ] || { echo not running epc - skipping ; return; }

    # pass peer id on the command line, or define it it with define-peer
    hss_id=$1; shift
    [ -z "$hss_id" ] && hss_id=$(get-peer)
    [ -z "$h
ss_id" ] && { echo "configure-enb: no peer defined - exiting"; return; }
    # ensure nodes functions are known
    hss_id=$(echo -n "0"${hss_id}|tail -c 2)
    echo "EPC: Using  HSS on $hss_id"

    check-etc-hosts $hss_id
    
    hss_id=$(echo $hss_id | sed  's/^0*//')
    mkdir -p /usr/local/etc/oai/freeDiameter
    local id=$(r2lab-id)
    echo "**debug** before id = $id"
    local fitid=fit$id
    id=$(echo $id | sed  's/^0*//')
    local localip="192.168.${oai_subnet}.${id}/24"
    local hssip="192.168.${oai_subnet}.${hss_id}"
    echo "**debug** after id = $id and hssip = $hssip"

    cd $template_dir

    cat > mme-r2lab.sed <<EOF
s|RUN_MODE.*=.*|RUN_MODE = "OTHER";|
s|REALM.*=.*|REALM = "${oai_realm}";|
s|.*YOUR GUMMEI CONFIG HERE|{MCC="208" ; MNC="95"; MME_GID="4" ; MME_CODE="1"; }|
s|MME_INTERFACE_NAME_FOR_S1_MME.*=.*|MME_INTERFACE_NAME_FOR_S1_MME = "${oai_ifname}";|
s|MME_IPV4_ADDRESS_FOR_S1_MME.*=.*|MME_IPV4_ADDRESS_FOR_S1_MME = "${localip}";|
s|MME_INTERFACE_NAME_FOR_S11_MME.*=.*|MME_INTERFACE_NAME_FOR_S11_MME = "lo";|
s|MME_IPV4_ADDRESS_FOR_S11_MME.*=.*|MME_IPV4_ADDRESS_FOR_S11_MME = "127.0.2.1/8";|
s|SGW_IPV4_ADDRESS_FOR_S11.*=.*|SGW_IPV4_ADDRESS_FOR_S11 = "127.0.3.1/8";|
s|"CONSOLE"|"${out_mme}"|
/MNC="93".*},/d
s|MNC="93"|MNC="95"|
EOF
    echo "(Over)writing $conf_dir/mme.conf"
    sed -f mme-r2lab.sed < mme.conf > $conf_dir/mme.conf
    # remove the extra TAC entries

    cat > mme_fd-r2lab.sed <<EOF
s|Identity.*=.*|Identity="${fitid}.${oai_realm}";|
s|Realm.*=.*|Realm="${oai_realm}";|
s|ConnectTo = "127.0.0.1"|ConnectTo = "${hssip}"|
s|openair4G.eur|r2lab.fr|g
EOF
    echo "(Over)writing $conf_dir/freeDiameter/mme_fd.conf"
    sed -f mme_fd-r2lab.sed < mme_fd.conf > $conf_dir/freeDiameter/mme_fd.conf
    
    cat > spgw-r2lab.sed <<EOF
s|SGW_INTERFACE_NAME_FOR_S11.*=.*|SGW_INTERFACE_NAME_FOR_S11 = "lo";|
s|SGW_IPV4_ADDRESS_FOR_S11.*=.*|SGW_IPV4_ADDRESS_FOR_S11 = "127.0.3.1/8";|
s|SGW_INTERFACE_NAME_FOR_S1U_S12_S4_UP.*=.*|SGW_INTERFACE_NAME_FOR_S1U_S12_S4_UP = "${oai_ifname}";|
s|SGW_IPV4_ADDRESS_FOR_S1U_S12_S4_UP.*=.*|SGW_IPV4_ADDRESS_FOR_S1U_S12_S4_UP = "${localip}";|
s|OUTPUT.*=.*|OUTPUT = "${out_spgw}";|
s|PGW_INTERFACE_NAME_FOR_SGI.*=.*|PGW_INTERFACE_NAME_FOR_SGI = "control";|
s|PGW_IPV4_ADDRESS_FOR_SGI.*=.*|PGW_IPV4_ADDRESS_FOR_SGI = "192.168.3.${id}/24";|
s|DEFAULT_DNS_IPV4_ADDRESS.*=.*|DEFAULT_DNS_IPV4_ADDRESS = "138.96.0.10";|
s|DEFAULT_DNS_SEC_IPV4_ADDRESS.*=.*|DEFAULT_DNS_SEC_IPV4_ADDRESS = "138.96.0.11";|
s|PGW_MASQUERADE_SGI.*=.*|PGW_MASQUERADE_SGI = "yes";|
s|192.188.0.0/24|192.168.10.0/24|g
s|192.188.1.0/24|192.168.11.0/24|g
EOF
    echo "(Over)writing $conf_dir/spgw.conf"
    sed -f spgw-r2lab.sed < spgw.conf > $conf_dir/spgw.conf

    cd $run_dir
    echo "===== generating certificates"
    ./check_mme_s6a_certificate /usr/local/etc/oai/freeDiameter ${fitid}.${oai_realm}

}

function configure-hss() {

    [ -n "$runs_hss" ] || { echo not running hss - skipping ; return; }

    # pass peer id on the command line, or define it it with define-peer
    epcid=$1; shift
    [ -z "$epcid" ] && epcid=$(get-peer)
    [ -z "$epcid" ] && { echo "configure-enb: no peer defined - exiting"; return; }
    epcid=$(echo -n "0"${epcid}|tail -c 2)
    echo "HSS: Using EPC on $epcid"

    mkdir -p /usr/local/etc/oai/freeDiameter
    local id=$(r2lab-id)
    local fitid=fit$id
    id=$(echo $id | sed  's/^0*//')
    local localip="192.168.${oai_subnet}.${id}/24"

    if [ -n "$runs_epc" ]; then
        # box runs both services                                                                                                      
	echo "/etc/hosts already configured"
    else
	clean-hosts
	echo "127.0.1.1 $fitid.${oai_realm} $fitid" >> /etc/hosts
	echo "192.168.${oai_subnet}.${id} hss.${oai_realm} hss" >> /etc/hosts
    fi

    cd $template_dir

    cat > hss-r2lab.sed <<EOF
s|@MYSQL_user@|root|
s|@MYSQL_pass@|linux|
s|OPERATOR_key.*|OPERATOR_key = "11111111111111111111111111111111";|
EOF
    echo "(Over)writing $conf_dir/hss.conf"
    sed -f hss-r2lab.sed < hss.conf > $conf_dir/hss.conf

    cat > hss_fd-r2lab.sed <<EOF
s|openair4G.eur|${oai_realm}|
EOF

    echo "(Over)writing $conf_dir/freeDiameter/hss_fd.conf"
    sed -f hss_fd-r2lab.sed < hss_fd.conf > $conf_dir/freeDiameter/hss_fd.conf
    echo "(Over)writing $conf_dir/freeDiameter/acl.conf"
    sed -f hss_fd-r2lab.sed < acl.conf > $conf_dir/freeDiameter/acl.conf

    cd $run_dir
    echo "===== generating certificates"
    ./check_hss_s6a_certificate /usr/local/etc/oai/freeDiameter hss.${oai_realm}

    echo "===== populating DB"
    # xxx ???
    ./hss_db_create localhost root linux hssadmin admin oai_db
    ./hss_db_import localhost root linux oai_db ../src/oai_hss/db/oai_db.sql
#    ./hss_db_import localhost root linux oai_db ../SRC/OAI_HSS/db/oai_db.sql
    populate-hss-db "$epcid"
}

# not declared in available since it's called by configure
function populate-hss-db() {

    epc_id=$1; shift
    [ -z "$epc_id" ] && { echo "check-etc-hosts requires hss-id - exiting" ; return ; }
    # ensure that epc_id is encoded with 2 digits
    epc_id=$(echo -n "0"${epc_id}|tail -c 2)
    
    # insert our SIM in the hss db
    # NOTE: setting the 'key' column raises a special issue as key is a keyword in
    # the mysql syntax
    # this will need to be fixed if it's important that we set a key

# sample from the doc    
# ('208930000000001',  '33638060010', NULL, NULL,
#  'PURGED', '120', '50000000', '100000000', 
#  '47', '0000000000', '3', 0x8BAF473F2F8FD09487CCCBD7097C6862,
#  '1', '0', '', 0x00000000000000000000000000000000, '');
###    insert_command="INSERT INTO users (imsi, msisdn, imei, imei_sv, 
###                                       ms_ps_status, rau_tau_timer, ue_ambr_ul, ue_ambr_dl,
###                                       access_restriction, mme_cap, mmeidentity_idmmeidentity, key,
###                                       RFSP-Index, urrp_mme, sqn, rand, OPc) VALUES ("
###    # imsi PRIMARY KEY
###    insert_command="$insert_command '222220000000001',"
###    # msisdn - unused but must be non-empty
###    insert_command="$insert_command '33638060010',"
###    # imei
###    insert_command="$insert_command NULL,"
###    # imei_sv
###    insert_command="$insert_command NULL,"
###    # ms_ps_status
###    insert_command="$insert_command 'PURGED',"
###    # rau_tau_timer
###    insert_command="$insert_command '120',"
###    # ue_ambr_ul upload ?
###    insert_command="$insert_command '50000000',"
###    # ue_ambr_dl download ?
###    insert_command="$insert_command '100000000',"
###    # access_restriction
###    insert_command="$insert_command '47',"
###    # mme_cap
###    insert_command="$insert_command '0000000000',"
###    # mmeidentity_idmmeidentity PRIMARY KEY
###    insert_command="$insert_command '3',"
###    # key
###    insert_command="$insert_command '0x8BAF473F2F8FD09487CCCBD7097C6862',"
###    # RFSP-Index
###    insert_command="$insert_command '1',"
###    # urrp_mme
###    insert_command="$insert_command '0',"
###    # sqn
###    insert_command="$insert_command '',"
###    # rand
###    insert_command="$insert_command '0x00000000000000000000000000000000',"
###    # OPc
###    insert_command="$insert_command '');"

    # from https://gitlab.eurecom.fr/oai/openairinterface5g/wikis/SIMInfo
    # SIM card # 2

    function name_value() {
	name="$1"; shift
	value="$1"; shift
	last="$1"; shift
	insert_command="$insert_command $value"
	update_command="$update_command $name=$value"
	if [ -n "$last" ]; then
	    insert_command="$insert_command)"
	else
	    insert_command="$insert_command",
	    update_command="$update_command",
	fi
    }

    idmmeidentity=100
    mmehost=fit${epc_id}.${oai_realm}

###    
###    # users table
###    insert_command="INSERT INTO users (imsi, msisdn, access_restriction, mmeidentity_idmmeidentity, \`key\`, sqn) VALUES ("
###    update_command="ON DUPLICATE KEY UPDATE "
###    name_value imsi "'208950000000002'"
###    name_value msisdn "'33638060010'"
###    name_value access_restriction "'47'"
###    name_value mmeidentity_idmmeidentity "'${idmmeidentity}'"
###    name_value "\`key\`" "0x8BAF473F2F8FD09487CCCBD7097C6862"
###    name_value sqn "'000000000020'" last
###
####    mysql --user=root --password=linux -e 'select imsi from users where imsi like "20895%"' oai_db 
###
###    echo issuing SQL "$insert_command $update_command"
###    mysql --user=root --password=linux -e "$insert_command $update_command" oai_db

## Following for Nexus 5 phone with SIM # 02
    hack_command="update users set mmeidentity_idmmeidentity=100 where imsi=208950000000002;"
    echo issuing HACK SQL "$hack_command"
    mysql --user=root --password=linux -e "$hack_command" oai_db

## Following for Huawei 3372 LTE stick with SIM # 07 on node fit02
    hack_command="update users set mmeidentity_idmmeidentity=100 where imsi=208950000000007;"
    echo issuing HACK SQL "$hack_command"
    mysql --user=root --password=linux -e "$hack_command" oai_db

## Following for Huawei 3372 LTE stick with SIM # 05 on node fit26
    hack_command="update users set mmeidentity_idmmeidentity=100 where imsi=208950000000005;"
    echo issuing HACK SQL "$hack_command"
    mysql --user=root --password=linux -e "$hack_command" oai_db

## Following for Iphone 6s phone with SIM # 04
    hack_command="update users set mmeidentity_idmmeidentity=100 where imsi=208950000000004;"
    echo issuing HACK SQL "$hack_command"
    mysql --user=root --password=linux -e "$hack_command" oai_db

## Following for OAI UE with fake SIM # 03 on node fit06 (with UE duplexer)
    hack_command="update users set mmeidentity_idmmeidentity=100 where imsi=208950000000003;"
    echo issuing HACK SQL "$hack_command"
    mysql --user=root --password=linux -e "$hack_command" oai_db

   # mmeidentity table
    insert_command="INSERT INTO mmeidentity (idmmeidentity, mmehost, mmerealm, \`UE-Reachability\`) VALUES ("
    update_command="ON DUPLICATE KEY UPDATE "

    name_value idmmeidentity ${idmmeidentity}
    name_value mmehost "'${mmehost}'"
    name_value mmerealm "'${oai_realm}'" 
    name_value "\`UE-Reachability\`" 0 last
    
    echo issuing SQL "$insert_command $update_command"
    mysql --user=root --password=linux -e "$insert_command $update_command" oai_db
    
}

####################
function start() {
    start-hss
    start-epc
}
doc-nodes start "function"

function start-hss() {
    if [ -n "$runs_hss" ]; then
	cd $run_dir
	echo "Running run_hss in background"
	./run_hss >& $log_hss &
    fi
}

function start-epc() {
    if [ -n "$runs_epc" ]; then
	cd $run_dir
	echo "Launching mme and spgw in background"
	./run_mme >& $log_mme &
#	./run_spgw -r >& $log_spgw &
	./run_spgw >& $log_spgw &
    fi
}

locks=""
[ -n "$runs_hss" ] && add-to-locks /var/run/oai_hss.pid
[ -n "$runs_epc" ] && add-to-locks /var/run/mme_gw.pid /var/run/mme.pid /var/run/mmed.pid /var/run/spgw.pid

####################
doc-nodes status "displays the status of the epc and/or hss processes"
doc-nodes stop "stops the epc and/or hss processes & clears locks"

function -list-processes() {
    pids=""
    [ -n "$runs_hss" ] && pids="$pids $(pgrep run_hss) $(pgrep oai_hss)"
    [ -n "$runs_epc" ] && pids="$pids $(pgrep run_epc) $(pgrep mme) $(pgrep mme_gw) $(pgrep spgw)"
    pids="$(echo $pids)"
    echo $pids
}

####################
doc-nodes manage-db "runs mysql on the oai_db database" 
function manage-db() {
    mysql --user=root --password=linux oai_db
}

########################################
define-main "$0" "$BASH_SOURCE" 
main "$@"
