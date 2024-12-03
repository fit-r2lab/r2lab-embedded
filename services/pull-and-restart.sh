#!/bin/bash
###
# this utility script is cron'ed to run every morning at 6:00 
# on both r2lab and faraday (and distrait)
#

# xxx the django secret key and debug mode needs to be tweaked !

COMMAND=$(basename $0 .sh)
LOG=/var/log/$COMMAND.log

exec >> $LOG 2>&1

echo "==================== $COMMAND starting at $(date)"

#### depending on which host:
case $(hostname) in
    faraday*|distrait*)
		GIT_REPOS="/root/r2lab-embedded"
	;;
    prod-r2lab*|r2lab*)
		GIT_REPOS="/root/r2lab-embedded /root/r2lab.inria.fr /root/r2lab.inria.fr-raw"
	;;
    *)
		echo Unknown host $(hostname); exit 1;;
esac

#### updates the contents of selected git repos
function gtr() { git "$@" rev-parse --abbrev-ref --symbolic-full-name "@{u}"; }
# follow blindly
function gfollow() {
    git "$@" fetch --all
    git "$@" reset --hard $(gtr "$@")
}

for git_repo in $GIT_REPOS; do
    gfollow -C $git_repo
done

# also update the r2lab-embedded repo in /home/faraday for regular users
case $(hostname) in
	faraday*|distrait*)
		runuser -u faraday -- git -C /home/faraday/r2lab-embedded fetch
		runuser -u faraday -- git -C /home/faraday/r2lab-embedded reset --hard origin/master
	;;
esac

cd

#### depending on which host:
case $(hostname) in
	distrait*)
        pip3 install -U rhubarbe 2> /dev/null
	;;
    faraday*)
        pip3 install -U rhubarbe 2> /dev/null
		systemctl restart monitornodes
		systemctl restart monitorphones
		systemctl restart monitorleases
		systemctl restart accountsmanager
	;;
    prod-r2lab*|r2lab*)
        pip3 install -U rhubarbe 2> /dev/null
		pip3 install -U r2lab-sidecar 2> /dev/null
		make -C /root/r2lab.inria.fr publish
		make -C /root/r2lab.inria.fr-raw publish
		systemctl restart r2lab-django
		systemctl restart r2lab-sidecar
		systemctl restart nginx
	;;
esac
