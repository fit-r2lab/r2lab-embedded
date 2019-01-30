#!/bin/bash
###
# this utility script is cron'ed to run every morning at 6:00 on both faraday and r2lab
#

# xxx the django secret key and debug mode needs to be tweaked !

COMMAND=$(basename $0 .sh)
LOG=/var/log/$COMMAND.log

exec >> $LOG 2>&1

echo "==================== $COMMAND starting at $(date)"

#### depending on which host:
case $(hostname) in
    faraday*)
	GIT_REPOS="/root/r2lab-embedded"
	;;
    r2lab*)
	GIT_REPOS="/root/r2lab-embedded /root/r2lab-sidecar /root/r2lab.inria.fr /root/r2lab.inria.fr-raw"
	;;
    *)
	echo Unknown host $(hostname); exit 1;;
esac

#### updates the contents of selected git repos
for git_repo in $GIT_REPOS; do
    cd $git_repo
    git reset --hard HEAD
    git pull
done

cd

#### depending on which host:
case $(hostname) in
    faraday*)
        pip3 install -U rhubarbe 2> /dev/null
	systemctl restart monitornodes
	systemctl restart monitorphones
	systemctl restart monitorleases
	systemctl restart accountsmanager
	;;
    r2lab*)
        pip3 install -U rhubarbe 2> /dev/null
	make -C /root/r2lab.inria.fr publish
	make -C /root/r2lab.inria.fr-raw publish
	systemctl restart sidecar
	systemctl restart httpd
	;;
esac
