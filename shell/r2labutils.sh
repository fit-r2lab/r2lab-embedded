_sourced_r2labutils=true

########################################
#
########## micro doc tool - to provide online help

# sort of decorators to define the doc-* functions
#
# create-doc-category cat message
#    will define 3 functions
#    help-cat : user-oriented, to get help on that category
#    doc-cat  : devel-oriented, to add a line in that help
#    doc-cat-sep : same, but to insert separators

function create-doc-category () {
    category="$1"; shift
    # initialize docstring for this category
    varname=_doc_$category
    # initialize docstring with rest of arguments to create-doc-category
    assign="$varname=\"#################### R2lab: $@\""
    eval "$assign"
    # define help-<> function
    defun="function help-$category() { echo -e \$$varname; }"
    eval "$defun"
    # define doc-<> function
    defun="function doc-$category() { -doc-helper $category \"\$@\"; }"
    eval "$defun"
    # define doc-<>-sep function
    defun="function doc-$category-sep() { -doc-helper-sep $category \"\$@\"; }"
    eval "$defun"
}

#
# augment-help-with cat
#
# will define a help alias that shows bash native help, then this category's help
#
function augment-help-with() {
    category=$1; shift
    defalias="alias help=\"echo '#################### Native bash help'; \\help; help-$category\""
    eval "$defalias"
}


### private stuff, not to be used from the outside
# -doc-helper <category>
function -doc-helper () {
    category=$1; shift
    fun=$1; shift;
    varname=_doc_$category
    docstring="$@"
    [ "$docstring" == 'alias' ] && docstring="$(alias $fun)"
    [ "$docstring" == 'function' ] && docstring="$(type $fun)"
    length=$(wc -c <<< $fun)
    [ $length -ge 16 ] && docstring="\n\t\t$docstring"
    assign="$varname=\"${!varname}\n$fun\r\t\t$docstring\""
    eval "$assign"
}

function -doc-helper-sep() {
    category=$1; shift
    varname=_doc_$category
    contents="$@"
    if [ -z "$contents" ] ; then
        assign="$varname=\"${!varname}\n---------------\""
    else
        assign="$varname=\"${!varname}\n============================== $contents\""
    fi
    eval "$assign"
}

########################################
########## utilities to deal with a set of files of the same kind
function random-string() {
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w ${1:-32} | head -n 1
}

# a file category is typically 'config' or 'log'
# it is used to define a set of files that play an identical role
# in a category, one may add either
# * plain files, like e.g. /var/log/softmodem.log
# * commands that print paths on their stdout,
#   this is for the OAI snap-based tools
#   like e.g. oai-cn.hss-conf-get
# * commands to be executed to produce output,
#   like e.g. journalctl -u softmodem --since '1 hour ago'
#
# a family is one of the three: files filecommands commands
#    for the three above cases, respectively
#
# in the first 2 cases, absolute paths are required to denote a file
#
# as compared with the previous implementation (for example on the config cat.)
#
# * grep-configs and tail-configs are no longer supported
# * show-configs gives the details of a category for the 3 families
# * run-configs allows to run all attached commands
#
function create-file-category() {
    # singular is the category's name
    local singular=$1; shift
    local plural=${singular}s
    local codefile="/tmp/def-category-$(random-string 12)"
    cat << EOF > "$codefile"

function clear-${plural}() {
    declare -a _${plural}_files
    declare -a _${plural}_filecommands
    declare -a _${plural}_commands
}
clear-${plural}

# not able to avoid duplication here despite having tried rather hard
function -add-files-${plural}() { _${plural}_files+=( "\$@" ); }
function -add-filecommands-${plural}() { _${plural}_filecommands+=( "\$@" ); }
function -add-commands-${plural}() { _${plural}_commands+=( "\$@" ); }

# helper to add items in arrays and avoid duplications
function -add-one-in-family-${plural}() {
    local family="\$1"; shift
    local addition="\$1"; shift
    local item
    local varname="_${plural}_\${family}"
    for item in "\${!varname}"; do
        [[ "\$item" == "\$addition" ]] && return
    done
    -add-\$family-${plural} "\$addition"
}

function add-files-to-${plural}() {
    local item
    for item in "\$@"; do
        -add-one-in-family-${plural} files \${item}
    done
}
# for historical reasons, e.g. add-to-configs
# means adding to the 'files' family
function add-to-${plural}() { add-files-to-${plural} "\$@"; }
# designed to work on several files, so of course also with one
function add-file-to-${plural}() { add-files-to-${plural} "\$@"; }

function add-filecommands-to-${plural}() {
    local item
    for item in "\$@"; do
        -add-one-in-family-${plural} filecommands \${item}
    done
}
# ditto
function add-filecommand-to-${plural}() { add-filecommands-to-${plural} "\$@"; }

# this one OTOH can only work with ONE command
# because a command typically has spaces..
function add-command-to-${plural} () {
    -add-one-in-family-${plural} commands "\$@"
}

# get-logs will just echo $_logs, while get-logs <anything> will issue
# a warning on stderr if the result is empty
function get-${plural}() {
    if [ -n "\$1" -a -z "\${_${plural}_files}""\${_${plural}_filecommands}"  ]; then
        echo "The ${plural} category is empty - use add-files-to-${plural} to fill it" >&2-
        return
    fi
    local varname
    varname="_${plural}_files[@]"
    for file in "\${!varname}"; do echo \$file; done
    varname="_${plural}_filecommands[@]"
    for filecommand in "\${!varname}"; do \$filecommand; done
}

function ls-${plural}() {
    local files=\$(get-${plural} "\$@")
    [ -n "\$files" ] && ls \$files
}

function show-${plural}() {
    local varname
    echo "----- files"
    varname="_${plural}_files[@]"
    for file in "\${!varname}"; do echo \$file; done
    echo "----- file commands"
    varname="_${plural}_filecommands[@]"
    for filecommand in "\${!varname}"; do echo \$filecommand; done
    echo "----- commands"
    varname="_${plural}_commands[@]"
    for command in "\${!varname}"; do echo \$command; done
}

function run-${plural}() {
    local varname
    varname="_${plural}_commands[@]"
    for command in "\${!varname}"; do
        echo ">>>>>>>>>>" \$command
        bash -c "\$command"
    done
}
EOF
    source "$codefile"
    rm "$codefile"
}

########################################
#
# this is not user-oriented
# it allows to turn a source-able shell file
# into a stub that can call it's internal functions
# like e.g.
# nodes.sh demo
#
function define-main() {
    zero="$1"; shift
    bash_source="$1"; shift
    function main() {
        if [ "$zero" = "$bash_source" ]; then
            if [[ -z "$@" ]]; then
                help
                return
            fi
            subcommand="$1"; shift
            # accept only subcommands that match a function
            case $(type -t $subcommand) in
                function)
                    $subcommand "$@" ;;
                *)
                    echo "$subcommand not a function : $(type -t $subcommand) - exiting" ;;
            esac
        fi
    }
}

####################
# said file just needs to end up with these 2 lines
####################
define-main "$0" "$BASH_SOURCE"
main "$@"
