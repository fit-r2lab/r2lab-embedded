#!/bin/bash
#
# Called by services/run-updates.sh after this repo has been updated.
#
# On faraday, regular users use their own copy of this repo
# in /home/faraday/r2lab-embedded, so that they can read it;
# that one has to follow as well. This is a no-op on other hosts.
#

set -euo pipefail

copy=/home/faraday/r2lab-embedded

if [[ -d "$copy" ]]; then
    runuser -u faraday -- git -C "$copy" fetch
    runuser -u faraday -- git -C "$copy" reset --hard origin/master
fi
