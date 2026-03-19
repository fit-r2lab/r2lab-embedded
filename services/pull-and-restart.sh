#!/bin/bash
###
# this utility script is run cyclically by systemd on
# - r2lab
# - r2labapi
# -	faraday
# - (and distrait)
#

COMMAND=$(basename $0 .sh)
# writes on stdout as it is invoked by systemd

cd /root

#### updates the contents of a specific git repo
function gtr() { git "$@" rev-parse --abbrev-ref --symbolic-full-name "@{u}"; }

# follow blindly the remote branch, no merge
# return 0 in case a change, 1 otherwise
function git-upgrade() {
	local repo="$1"; shift
	local before=$(git -C "$repo" rev-parse HEAD)
    git -C "$repo" fetch --all
    git -C "$repo" reset --hard $(gtr -C "$repo")
	local after=$(git -C "$repo" rev-parse HEAD)
	[[ "$before" != "$after" ]]
}

# same kind of tools with pip
function pip-upgrade() {
    local pkg="$1"
    local before=$(pip show "$pkg" 2>/dev/null | grep ^Version)
    pip install --upgrade "$pkg" -q
    local after=$(pip show "$pkg" 2>/dev/null | grep ^Version)
    [[ "$before" != "$after" ]]
}

echo "==================== $COMMAND starting at $(date)"

#### depending on which host:
case $(hostname) in
    faraday*|distrait*)
		if git-upgrade /root/r2lab-embedded; then
			# expose changes to slices/users
			runuser -u faraday -- git -C /home/faraday/r2lab-embedded fetch
			runuser -u faraday -- git -C /home/faraday/r2lab-embedded reset --hard origin/master
		fi

		# note that a previous version would always restart these services
		# also this was not done on distrait
		if pip-upgrade rhubarbe; then
			systemctl restart monitornodes
			systemctl restart monitorphones
			systemctl restart monitorpdus
			systemctl restart accountsmanager
		fi
	;;
    prod-r2labapi*|r2labapi*)
		git-upgrade /root/r2lab-embedded

		if git-upgrade /root/r2lab-api; then
			cd /root/r2lab-api
      		uv sync
      		systemctl restart r2lab-api
		fi
	;;
    prod-r2lab*|r2lab*)
		git-upgrade /root/r2lab-embedded

		git-upgrade r2lab.inria.fr; r1=$?
		git-upgrade r2lab.inria.fr-raw; r2=$?
		if (( r1 == 0|| r2 == 0)); then
			make -C /root/r2lab.inria.fr publish
			make -C /root/r2lab.inria.fr-raw publish
			systemctl restart r2lab-django
			systemctl restart nginx
		fi

		if pip-upgrade r2lab-sidecar; then
			systemctl restart r2lab-sidecar
		fi

        pip-upgrade rhubarbe || true
	;;

    *)
		echo Unknown host $(hostname)
		exit 1
	;;
esac
