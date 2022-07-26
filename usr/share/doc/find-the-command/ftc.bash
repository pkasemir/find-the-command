# Print to stderr
alias _cnf_print='echo -e 1>&2'

cnf_action=
cnf_force_su=false
cnf_noprompt=false
cnf_verbose=true

_cnf_actions=('install' 'info' 'list files' 'list files (paged)')

pacman_files_command() {
    local cmd=$1
    local pacman_version=$(pacman -Q pacman | awk -F'[ -]' '{print $2}')
    if [[ $(vercmp "$pacman_version" "5.2.0") -ge 0 ]]
    then
        local args="-Fq"
    else
        local args="Foq"
    fi
    pacman $args /usr/bin/$cmd 2> /dev/null
}

# Parse options
for opt in $*
do
    case $opt in
        noprompt) cnf_noprompt=true ;;
        su) cnf_force_su=true ;;
        quiet) cnf_verbose=false ;;
        install) cnf_action=${_cnf_actions[@]:0:1} ;;
        info) cnf_action=${_cnf_actions[@]:1:1} ;;
        list_files) cnf_action=${_cnf_actions[@]:2:1} ;;
        list_files_paged) cnf_action=${_cnf_actions[@]:3:1} ;;
        variant=zsh) command_not_found_handler() { command_not_found_handle "$@"; } ;;
        *) _cnf_print "find-the-command: unknown option: $opt" ;;
    esac
done

_cnf_prompt_yn() {
    local result
    _cnf_print -n "find-the-command: $1 [Y/n] "
    read result || kill -s INT $$
    case "$result" in
        y* | Y* | '') return 0;;
        *) return 1;;
    esac
}

# Don't show pre-search warning if 'quiet' option is not set
if $cnf_verbose
then
    _cnf_pre_search_warn() {
        local cmd=$1
        _cnf_print "find-the-command: \"$cmd\" is not found locally, searching in repositories..."
    }
    _cnf_cmd_not_found() {
        local cmd=$1
        _cnf_print "find-the-command: command not found: \"$cmd\""
        return 127
    }
else
    _cnf_pre_search_warn() { : Do nothing; }
    _cnf_cmd_not_found() { return 127; }
fi

# Without installation prompt
if $cnf_noprompt
then
    command_not_found_handle() {
        local cmd=$1
        _cnf_pre_search_warn "$cmd"
        local packages=$(pacman_files_command "$cmd")
        case $(echo $packages | wc -w) in
            0) _cnf_cmd_not_found "$cmd";;
            1) _cnf_print "\"$cmd\" may be found in package \"$packages\"" ;;
            *)
                local package
                _cnf_print "\"$cmd\" may be found in the following packages:"
                for package in $packages
                do
                    _cnf_print "\t$package"
                done
        esac
    }
else
# With installation prompt (default)
    if [[ $EUID == 0 ]]
    then _cnf_asroot() { $*; }
    else
        if $cnf_force_su
        then _cnf_asroot() { su -c "$*"; }
        else _cnf_asroot() { sudo $*; }
        fi
    fi
    command_not_found_handle() {
        local cmd=$1
        _cnf_pre_search_warn "$cmd"
        local packages=$(pacman_files_command $cmd)
        case $(echo $packages | wc -w) in
            0) _cnf_cmd_not_found "$cmd";;
            1)
                local ACT PS3="Action (0 to abort): "
                _cnf_prompt_install() {
                    local packages=$1
                    if _cnf_prompt_yn "Would you like to install '$packages'?"
                    then
                        _cnf_asroot pacman -S "$packages"
                    else
                        return 127
                    fi
                }

                if [[ -z $cnf_action ]]
                then
                    _cnf_print "\n\"$cmd\" may be found in package \"$packages\"\n"
                    _cnf_print "What would you like to do? "
                    select ACT in "${_cnf_actions[@]}"
                    do break
                    done
                else
                    ACT=$cnf_action
                fi

                _cnf_print
                case $ACT in
                    install) _cnf_asroot pacman -S $packages ;;
                    info) pacman -Si $packages; _cnf_prompt_install "$packages";;
                    'list files') pacman -Flq $packages; _cnf_print; _cnf_prompt_install "$packages";;
                    'list files (paged)') [[ -z $PAGER ]] && local PAGER=less
                        pacman -Flq $packages | $PAGER
                        _cnf_prompt_install "$packages" ;;
                    *) _cnf_print; return 127
                esac
                ;;
            *)
                local package PS3="$(echo -en "\nSelect a number of package to install (0 to abort): ")"
                _cnf_print "\"$cmd\" may be found in the following packages:\n"
                select package in `echo -n $packages`
                do break
                done
                [[ -n $package ]] && _cnf_asroot pacman -S $package || return 127
                ;;
        esac
    }
fi

# Clean up environment
unset opt cnf_force_su cnf_noprompt cnf_verbose
