#!/bin/bash
###
# generic updater, run hourly by systemd (see run-updates.timer) on
# - faraday
# - r2lab
# - r2labapi
#
# for each git repo listed in hosts/<host>.repos
# - follow blindly the upstream branch, no merge
# - if that changed anything, run the repo's own deploy/update.sh
#   (that is where the knowledge of how to build and restart lives)
#
# usage: run-updates.sh [host]
#   host defaults to the short hostname, stripped from any 'prod-' prefix
#

# git-upgrade repo
# returns 0 if the repo has changed, 1 if not, 2 in case of failure
function git-upgrade() {
    local repo="$1"
    local before after
    before=$(git -C "$repo" rev-parse HEAD) || return 2
    git -C "$repo" fetch --all -q || return 2
    git -C "$repo" reset --hard -q '@{u}' || return 2
    after=$(git -C "$repo" rev-parse HEAD) || return 2
    [[ "$before" != "$after" ]]
}

function main() {
    local here=$(dirname "$(readlink -f "$0")")
    local host=${1:-$(hostname -s | sed -e 's/^prod-//')}
    local manifest="$here/hosts/$host.repos"
    [[ -f "$manifest" ]] || { echo "unknown host $host - no $manifest"; return 1; }

    # one run at a time
    exec 9> "${LOCKFILE:-/run/lock/run-updates.lock}"
    flock -n 9 || { echo "already running"; return 0; }

    echo "==================== $(basename $0) on $host starting at $(date)"
    local failures=0 repo
    while read -r repo; do
        [[ -z "$repo" || "$repo" == \#* ]] && continue
        git-upgrade "$repo"
        case $? in
            0)
                echo "== $repo has changed"
                if [[ -x "$repo/deploy/update.sh" ]]; then
                    "$repo/deploy/update.sh" || { echo "!! $repo/deploy/update.sh failed"; failures=$((failures+1)); }
                fi
                ;;
            1) echo "== $repo is up to date" ;;
            *) echo "!! $repo could not be updated"; failures=$((failures+1)) ;;
        esac
    done < "$manifest"
    return $((failures != 0))
}

# this script lives in a repo that it resets under its own feet
# so it is all in a function, and we exit before bash gets to read any further
main "$@"; exit
