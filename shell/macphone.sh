# These helpers target the MAC that is sitting in the R2lab chamber
# and has a USB connection to a commercial phone (nexus 6 as of now)

source $(dirname "$BASH_SOURCE")/r2labutils.sh

adb=$(type -p adb)

if [ -z "$adb" ]; then
    adb="$HOME/nexustools/adb"
    [ -x $adb ] || echo "WARNING: from $BASH_SOURCE : $adb not executable"
fi
    

create-doc-category phone "tools for managing R2lab phone from macphone"
augment-help-with phone


doc-phone refresh "retrieve latest git repo, and source it in this shell"
function refresh() {
    cd ~/r2lab
    git pull
    source ~/.bash_profile
}

doc-phone phone-start-app "start an app from its package name"
function phone-start-app() {
    package_name=$1; shift
    # default : speedtest
    [ -z "$package_name" ] && package_name="org.zwanoo.android.speedtest"
    echo "Starting app $package_name"
    $adb shell monkey -p $package_name -c android.intent.category.LAUNCHER 1
}

doc-phone phone-wifi-on "turn on wifi (tested on nexus 5)"
function phone-wifi-on() {
    echo "Turning WiFi ON"
    $adb shell am start -a android.intent.action.MAIN -n com.android.settings/.wifi.WifiSettings
    $adb shell input keyevent 23
}
   
doc-phone phone-wifi-off "turn off wifi (tested on nexus 5)"
function phone-wifi-off() {
    echo "Turning WiFi OFF"
    $adb shell am start -a android.intent.action.MAIN -n com.android.settings/.wifi.WifiSettings
    $adb shell input keyevent 19
}
   
doc-phone phone-on "turn off airplane mode"
function phone-on() {
    echo "Turning ON phone : turning off airplane mode"
    $adb shell "settings put global airplane_mode_on 0; am broadcast -a android.intent.action.AIRPLANE_MODE --ez state false"
}

doc-phone phone-off "turn off airplane mode - does not touch wifi settings"
function phone-off() {
    # in a first version we attempted to turn off the wifi interface
    # however this feature happens to be unreliable at this point
    # most likely the constants used above are not right, or depend on the phone
    # and to actually sometimes turn it ON instead of OFF !!
    # so let's have the caller decide to turn off wifi or not
    # phone-wifi-off
    echo "Turning OFF phone : turning on airplane mode"
    $adb shell "settings put global airplane_mode_on 1; am broadcast -a android.intent.action.AIRPLANE_MODE --ez state true"
}

doc-phone phone-status "shows wheter airplane mode is on or off"
function phone-status() {
    airplane_mode_on=$($adb shell "settings get global airplane_mode_on")
    airplane_mode_on=$(echo $airplane_mode_on)
    case $airplane_mode_on in
	0*) echo phone is turned ON ;;
	1*) echo phone is turned OFF ;;
	*) echo "Could not figure phone status" ;;
    esac
}

doc-phone phone-reboot "reboot phone with abd reboot"
function phone-reboot() {
    echo "REBOOTING phone ..."
    #    $adb shell am broadcast -a android.intent.action.BOOT_COMPLETED
    $adb reboot
}

# to set LTE only - except that sqlite3 is not known
#$adb shell sqlite3 /data/data/com.android.providers.settings/databases/settings.db "update global SET value=11 WHERE name='preferred_network_mode'"
#$adb shell sqlite3 /data/data/com.android.providers.settings/databases/settings.db "select value FROM secure WHERE name='preferred_network_mode'"

function r2gw() {
    ssh -i ~/.ssh/tester_key root@192.168.4.100 "$@"
}
########################################
define-main "$0" "$BASH_SOURCE" 
main "$@"
