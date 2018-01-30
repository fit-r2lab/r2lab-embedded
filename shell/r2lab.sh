# convenience tools for r2lab.inria.fr
#
# not sure where this log file is going to end up

# use the micro doc-help tool
source $(dirname $(readlink -f $BASH_SOURCE))/r2labutils.sh

create-doc-category admin "admin-oriented commands"

alias logs-django="tail -f /var/lib/r2lab.inria.fr/django.log /var/log/httpd/*log"
doc-admin logs-django alias
alias logs-r2lab=logs-django
doc-admin logs-r2lab alias

alias log-sidecar="tail -f /var/log/sidecar.log"
doc-admin log-sidecar alias

alias jou-sidecar="journalctl -b -f --unit=sidecar"
doc-admin jou-sidecar alias

doc-admin gitup "runs git pull in /root/r2lab"
function gitup() {
    cd /root/r2lab
    git pull
}
