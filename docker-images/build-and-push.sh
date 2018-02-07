#!/bin/bash

COMMAND=$(basename $0)

set -e

DOCKERHUBREPO=fitr2lab

# globals
DEFAULT_TAG=latest
OPT_BUILD_ONLY=""
OPT_FORCE=""


function usage() {
    echo "Usage: $COMMAND [options] subdir"
    echo "Supportd options:"
    echo " -b : build_only, do not push up to dockerhub repo"
    echo " -f : force, i.e. use no cache (run docker build --no-cache)"
    echo " -t tag: use that tag instead of $DEFAULT_TAG"
    [[ -n "$@" ]] && echo "$@"
    exit 1
}


function main() {
    TAG=$DEFAULT_TAG
    # parse opts
    while getopts "bft:" opt; do
        case $opt in
            b) OPT_BUILD_ONLY="true" ;;
            f) OPT_FORCE="true" ;;
            t) TAG="$OPTARG" ;;
            \?) usage "Invalid option: -$OPTARG" ;;
            :) usage "Option -$OPTARG requires an argument." ;;
        esac
    done
    shift $((OPTIND-1))
    
    # one mandatory argument
    [[ -z "$@" ]] && usage
    local subdir="$1"; shift
    [ -d "$subdir" ] || usage "subdir $subdir not found"

    # remove trailing slash that you get if you use bash completion
    subdir=$(sed -e 's,/*$,,' <<< $subdir)

    build $subdir
    [ -z "$OPT_BUILD_ONLY" ] && push $subdir
    
}


function build() {
    local subdir="$1"; shift
    # POPULATE the docker build dir with all shell scripts
    rsync -ai ../shell/*.sh $subdir
    command="docker build"
    [ -z "$OPT_FORCE" ] || command="$command --no-cache"
    command="$command $subdir -t $DOCKERHUBREPO/$subdir:$TAG"
    echo Pushing with command:
    echo $command
    $command
}


function push() {
    local subdir="$1"; shift
    docker push $DOCKERHUBREPO/$subdir:$TAG
}    

main "$@"
