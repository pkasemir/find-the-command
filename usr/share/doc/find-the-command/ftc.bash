# Print to stderr
alias _cnf_print='echo -e 1>&2'

cnf_action=
cnf_force_su=0
cnf_noprompt=0
cnf_verbose=1

_cnf_actions=('install' 'info' 'list files' 'list files (paged)')

pacman_files_command(){
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
        noprompt) cnf_noprompt=1 ;;
        su) cnf_force_su=1 ;;
        quiet) cnf_verbose=0 ;;
        install) cnf_action=${_cnf_actions[@]:0:1} ;;
        info) cnf_action=${_cnf_actions[@]:1:1} ;;
        list_files) cnf_action=${_cnf_actions[@]:2:1} ;;
        list_files_paged) cnf_action=${_cnf_actions[@]:3:1} ;;
        variant=zsh) command_not_found_handler() { command_not_found_handle "$@"; } ;;
        *) _cnf_print "find-the-command: unknown option: $opt" ;;
    esac
done

# Don't show pre-search warning if 'quiet' option is not set
if [[ $cnf_verbose != 0 ]]
then
    _cnf_pre_search_warn(){
        _cnf_print "find-the-command: \"$cmd\" is not found locally, searching in repositories..."
    }
    _cnf_cmd_not_found(){
        _cnf_print "find-the-command: command not found: $cmd"
        return 127
    }
else
    _cnf_pre_search_warn(){ : Do nothing; }
    _cnf_cmd_not_found(){ return 127; }
fi

# Without installation prompt
if [[ $cnf_noprompt == 1 ]]
then
    command_not_found_handle() {
        local cmd=$1
        _cnf_pre_search_warn
        local packages=$(pacman_files_command $cmd)
        case $(echo $packages | wc -w) in
            0) _cnf_cmd_not_found ;;
            1) _cnf_print "\"$cmd\" may be found in package \"$packages\"" ;;
            *)
                local package
                _cnf_print "\"$cmd\" may be found in the following packages:"
                for package in `echo -n $packages`
                do
                _cnf_print "\t$package"
                done
        esac
    }
else
# With installation prompt (default)
    if [[ $EUID == 0 ]]
    then _cnf_asroot(){ $*; }
    else
        if [[ $cnf_force_su == 1 ]]
        then _cnf_asroot() { su -c "$*"; }
        else _cnf_asroot() { sudo $*; }
        fi
    fi
    command_not_found_handle() {
        local cmd=$1
        _cnf_pre_search_warn
        local packages=$(pacman_files_command $cmd)
        case $(echo $packages | wc -w) in
            0) _cnf_cmd_not_found ;;
            1)
                local ACT PS3="Action (0 to abort): "
                prompt_install(){
                    _cnf_print -n "Would you like to install this package? (y|n) "
                    local RESULT
                    read RESULT &&
                        [[ "$RESULT" = y || "$RESULT" = Y ]] &&
                        (_cnf_print;_cnf_asroot pacman -S $packages) || (_cnf_print; return 127)
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
                    info) pacman -Si $packages; prompt_install;;
                    'list files') pacman -Flq $packages; _cnf_print; prompt_install;;
                    'list files (paged)') [[ -z $PAGER ]] && local PAGER=less
                        pacman -Flq $packages | $PAGER
                        prompt_install ;;
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
