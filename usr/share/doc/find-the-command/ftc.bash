# Print to stderr
alias _cnf_print='echo -e 1>&2'

_cnf_action=
_cnf_askfirst=false
_cnf_force_su=false
_cnf_noprompt=false
_cnf_noupdate=false
_cnf_verbose=true

_cnf_actions=('install' 'info' 'list files' 'list files (paged)')

# Parse options
for opt in "$@"
do
    case "$opt" in
        askfirst) _cnf_askfirst=true ;;
        noprompt) _cnf_noprompt=true ;;
        noupdate) _cnf_noupdate=true ;;
        su) _cnf_force_su=true ;;
        quiet) _cnf_verbose=false ;;
        install) _cnf_action=${_cnf_actions[@]:0:1} ;;
        info) _cnf_action=${_cnf_actions[@]:1:1} ;;
        list_files) _cnf_action=${_cnf_actions[@]:2:1} ;;
        list_files_paged) _cnf_action=${_cnf_actions[@]:3:1} ;;
        variant=zsh) command_not_found_handler() { command_not_found_handle "$@"; } ;;
        *) _cnf_print "find-the-command: unknown option: $opt" ;;
    esac
done

_cnf_pacman_db_path() {
    local db_path=$(sed -n '/^DBPath[[:space:]]*=/{s/^[^=]*=[[:space:]]*\(.*[^[:space:]]\)[[:space:]]*/\1/p;q}' /etc/pacman.conf)
    if test -z "$db_path"
    then
        db_path=/var/lib/pacman
    fi
    echo "$db_path/sync"
}

_cnf_asroot() {
    if test $EUID -ne 0
    then
        if $_cnf_force_su
        then
            su -c "$*"
        else
            sudo "$@"
        fi
    else
        "$@"
    fi
}

_cnf_prompt_yn() {
    local result
    _cnf_print -n "find-the-command: $1 [Y/n] "
    read result || kill -s INT $$
    case "$result" in
        y* | Y* | '')
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

if $_cnf_noupdate
then
    _cnf_need_to_update_files() {
        return 1
    }
else
    _cnf_need_to_update_files() {
        local old_files dir=$1
        local db_path=$(_cnf_pacman_db_path)
        if test $(find "$db_path" -type f -maxdepth 2 -name "*.db" 2>/dev/null | wc -l) -eq 0
        then
            if _cnf_prompt_yn "No pacman db files in '$db_path', refresh?"
            then
                _cnf_asroot pacman -Sy >&2
            else
                return 1
            fi
        fi
        if test $(find "$dir" -type f -maxdepth 2 -name "*.files" 2>/dev/null | wc -l) -eq 0
        then
            old_files=all
        else
            local newest_files=$(/usr/bin/ls -t "$dir"/*.files | head -n 1)
            local newest_pacman_db=$(/usr/bin/ls -t "$db_path"/*.db | head -n 1)
            old_files=$(find "$newest_pacman_db" -newer "$newest_files")
        fi
        if test -n "$old_files"
        then
            _cnf_prompt_yn "$dir/*.files are out of date, update?"
            return $?
        fi
        return 1
    }
fi

_cnf_command_packages() {
    local cmd=$1
    if type pkgfile >/dev/null 2>/dev/null
    then
        local cache=$(pkgfile --help | sed -n 's/.*--cachedir.*default:[[:space:]]*\(.*\))$/\1/p')
        if test -z "$cache"
        then
            cache=/var/cache/pkgfile
        fi

        if _cnf_need_to_update_files "$cache"
        then
            _cnf_asroot pkgfile --update >&2
        fi
        pkgfile --binaries -- "$cmd" 2>/dev/null
    else
        local pacman_version=$(pacman -Q pacman 2>/dev/null | awk -F'[ -]' '{print $2}')
        local args="-Fq"
        if test $(vercmp "$pacman_version" "5.2.0") -lt 0
        then
            args="$args"o
        fi
        local db_path=$(_cnf_pacman_db_path)
        if _cnf_need_to_update_files "$db_path"
        then
            _cnf_asroot pacman -Fy >&2
        fi
        pacman $args "/usr/bin/$cmd" 2>/dev/null
    fi
}

_cnf_package_files() {
    local package=$1
    if type pkgfile >/dev/null 2>/dev/null
    then
        pkgfile --list "$package" | sed 's/[^[:space:]]*[[:space:]]*//'
    else
        pacman -Flq "$package"
    fi
}

# Don't show pre-search warning if 'quiet' option is not set
if $_cnf_verbose
then
    _cnf_pre_search_warn() {
        local cmd=$1
        _cnf_print "find-the-command: \"$cmd\" is not found locally, searching in repositories..."
        return 0
    }
else
    _cnf_pre_search_warn() { return 0; }
fi

if $_cnf_askfirst
then
    # When askfirst is given, override default verbose behavior
    _cnf_pre_search_warn() {
        local cmd=$1
        _cnf_prompt_yn "\"$cmd\" is not found locally, search in repositories?"
        return $status
    }
fi

_cnf_cmd_not_found() {
    local cmd=$1
    _cnf_print "find-the-command: command not found: \"$cmd\""
    return 127
}

# Without installation prompt
if $_cnf_noprompt
then
    command_not_found_handle() {
        local cmd=$1
        _cnf_pre_search_warn "$cmd" || return 127
        local packages=$(_cnf_command_packages "$cmd")
        case $(echo $packages | wc -w) in
            0)
                _cnf_cmd_not_found "$cmd"
                ;;
            1)
                _cnf_print "find-the-command: \"$cmd\" may be found in package \"$packages\""
                ;;
            *)
                local package
                _cnf_print "find-the-command: \"$cmd\" may be found in the following packages:"
                for package in $(echo $packages)
                do
                    _cnf_print "\t$package"
                done
        esac
    }
else
# With installation prompt (default)
    command_not_found_handle() {
        local cmd=$1
        local scroll_header="Shift up or down to scroll the preview"
        _cnf_pre_search_warn "$cmd" || return 127
        local packages=$(_cnf_command_packages "$cmd")
        case $(echo $packages | wc -w) in
            0)
                _cnf_cmd_not_found "$cmd"
                ;;
            1)
                _cnf_prompt_install() {
                    local packages=$1
                    if _cnf_prompt_yn "Would you like to install '$packages'?"
                    then
                        _cnf_asroot pacman -S "$packages"
                    else
                        return 127
                    fi
                }

                local action
                if test -z "$_cnf_action"
                then
                    local may_be_found="\"$cmd\" may be found in package \"$packages\""
                    _cnf_print "find-the-command: $may_be_found"
                    if which fzf >/dev/null 2>/dev/null
                    then
                        local package_files=$(_cnf_package_files "$packages")
                        local package_info=$(pacman -Si "$packages")
                        action=$(printf "%s\n" "${_cnf_actions[@]}" | \
                            fzf --preview "echo {} | grep -q '^list' && echo '$package_files' \
                                    || echo '$package_info'" \
                                --prompt "Action (\"esc\" to abort):" \
                                --header "$may_be_found
$scroll_header")
                    else
                        _cnf_print "find-the-command: What would you like to do? "
                        local PS3="$(echo -en "\nAction (0 to abort): ")"
                        select action in "${_cnf_actions[@]}"
                        do break
                        done
                    fi
                else
                    action="$_cnf_action"
                fi

                case "$action" in
                    install)
                        _cnf_asroot pacman -S "$packages"
                        ;;
                    info)
                        pacman -Si "$packages"
                        _cnf_prompt_install "$packages"
                        ;;
                    'list files')
                        _cnf_package_files "$packages"
                        _cnf_prompt_install "$packages"
                        ;;
                    'list files (paged)')
                        test -z "$PAGER" && local PAGER=less
                        _cnf_package_files "$packages" | "$PAGER"
                        _cnf_prompt_install "$packages"
                        ;;
                    *)
                        return 127
                        ;;
                esac
                ;;
            *)
                local package
                _cnf_print "find-the-command: \"$cmd\" may be found in the following packages:"
                if which fzf >/dev/null 2>/dev/null
                then
                    for package in $(echo $packages)
                    do
                        _cnf_print "\t$package"
                    done
                    package=$(printf "%s\n" $packages | \
                        fzf --bind="tab:preview(type pkgfile >/dev/null 2>/dev/null && \
                                pkgfile --list {} | sed 's/[^[:space:]]*[[:space:]]*//' || \
                                pacman -Flq {})" \
                            --preview "pacman -Si {}" \
                            --header "Press \"tab\" to view files
$scroll_header" \
                            --prompt "Select a package to install (\"esc\" to abort):")
                else
                    local PS3="$(echo -en "\nSelect a number of package to install (0 to abort): ")"
                    select package in $(echo $packages)
                    do break
                    done
                fi
                if test -n "$package"
                then
                    _cnf_asroot pacman -S "$package"
                else
                    return 127
                fi
                ;;
        esac
    }
fi

# Clean up environment
unset opt _cnf_askfirst _cnf_noprompt _cnf_noupdate _cnf_verbose
