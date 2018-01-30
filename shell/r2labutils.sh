########################################
#
########## micro doc tool - to provide online help

# sort of decorators to define the doc-* functions
#
# create-doc-category cat message
#    will define 3 functions
#    help-cat : user-oriented, to get help on that category
#    doc-cat  : devel-oriented, to add a line in that help
#    dac-cat-sep : same, but to insert separators

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

function create-file-category() {
    catname=$1; shift
    plural=${catname}s
    codefile="/tmp/def-category-$(random-string 12)"
    cat << EOF > "$codefile"
function clear-${plural}() {
    _${plural}=""
}
clear-${plural}
function add-to-${plural}() {
    _${plural}="\$_${plural} \$@";
}
# get-logs will just echo $_logs, while get-logs <anything> will issue
# a warning on stderr if the result is empty
function get-${plural}() {
    if [ -n "\$1" -a -z "\$_${plural}" ]; then
        echo "The \'_${plural}\' env. variable is empty - Use add-to-${plural} to define some"  >&2-
    fi
    echo \$_${plural};
}
function ls-${plural}() {
    local files=\$(get-${plural} "\$@")
    [ -n "\$files" ] && ls \$files
}
function grep-${plural}() {
    [[ -z "\$@" ]] && { echo usage: grep-${plural} grep-arg..s; return; }
    grep "\$@" \$(ls-${plural})
}
function tail-${plural}() {
    local files="\$(ls-${plural})"
    for file in \$files; do
	[ -f \$file ] || { echo "Touching \$file"; touch \$file; }
    done
    tail -f \$files
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
