function _cnf_print
    echo -e 1>&2 $argv
end

set _cnf_action
set _cnf_askfirst false
set _cnf_force_su false
set _cnf_noprompt false
set _cnf_noupdate false
set _cnf_verbose true

set _cnf_actions "install" "info" "list files" "list files (paged)"

for opt in $argv
    if test (string length "$opt") -gt 0
        switch "$opt"
            case askfirst
                set _cnf_askfirst true
            case noprompt
                set _cnf_noprompt true
            case noupdate
                set _cnf_noupdate true
            case su
                set _cnf_force_su true
            case quiet
                set _cnf_verbose false
            case install
                set _cnf_action "$_cnf_actions[1]"
            case info
                set _cnf_action "$_cnf_actions[2]"
            case list_files
                set _cnf_action "$_cnf_actions[3]"
            case list_files_paged
                set _cnf_action "$_cnf_actions[4]"
            case '*'
                _cnf_print "find-the-command: unknown option: $opt"
        end
    end
end

function _cnf_pacman_db_path
    set db_path (string trim (sed -n 's/^DBPath[[:space:]]*=//p' /etc/pacman.conf))
    if test -z "$db_path[1]"
        set db_path /var/lib/pacman
    end
    echo "$db_path[1]/sync"
end

function _cnf_asroot
    if test (id -u) -ne 0
        if $_cnf_force_su
            su -c "$argv"
        else
            sudo $argv
        end
    else
        $argv
    end
end

function _cnf_prompt_yn --argument-name prompt
    read --prompt="echo \"find-the-command: $prompt [Y/n] \"" result
    or kill -s INT $fish_pid
    switch "$result"
    case 'y*' 'Y*' ''
        return 0
    case '*'
        return 1
    end
end

if $_cnf_noupdate
    function _cnf_need_to_update_files
        return 1
    end
else
    function _cnf_need_to_update_files --argument-name dir
        set db_path (_cnf_pacman_db_path)
        if test (find "$db_path" -type f -maxdepth 2 -name "*.db" 2> /dev/null | wc -w) -eq 0
            if _cnf_prompt_yn "No pacman db files in '$db_path', refresh?"
                _cnf_asroot pacman -Sy >&2
            else
                return 1
            end
        end
        if test (find "$dir" -type f -maxdepth 2 -name "*.files" 2> /dev/null | wc -w) -eq 0
            set old_files all
        else
            set newest_files (/usr/bin/ls -t "$dir"/*.files | head -n 1)
            set newest_pacman_db (/usr/bin/ls -t "$db_path"/*.db | head -n 1)
            set old_files (find $newest_pacman_db -newer $newest_files)
        end
        if test -n "$old_files"
            _cnf_prompt_yn "$dir/*.files are out of date, update?"
            return $status
        end
        return 1
    end
end

if type -q pkgfile
    function _cnf_command_packages --argument-names cmd
        set cache (string trim --chars=' )' (pkgfile --help | sed -n 's/.*--cachedir.*default://p'))
        if test -z "$cache"
            set cache /var/cache/pkgfile
        end

        if _cnf_need_to_update_files "$cache"
            _cnf_asroot pkgfile --update >&2
        end
        pkgfile --binaries -- "$cmd" 2> /dev/null
    end
else
    function _cnf_command_packages --argument-names cmd
        set pacman_version (pacman -Q pacman | awk -F'[ -]' '{print $2}')
        set args "-Fq"
        if test (vercmp "$pacman_version" "5.2.0") -lt 0
            set args "$args"o
        end
        set db_path (_cnf_pacman_db_path)
        if _cnf_need_to_update_files "$db_path"
            _cnf_asroot pacman -Fy >&2
        end
        pacman $args /usr/bin/$cmd 2> /dev/null
    end
end

if $_cnf_verbose
    function _cnf_pre_search_warn --argument-names cmd
        _cnf_print "find-the-command: \"$cmd\" is not found locally, searching in repositories...\n"
        return 0
    end

    function _cnf_cmd_not_found --argument-names cmd
        _cnf_print "find-the-command: command not found: \"$cmd\""
        return 127
    end
else
    function _cnf_pre_search_warn
        return 0
    end

    function _cnf_cmd_not_found
        return 127
    end
end

if $_cnf_askfirst
    # When askfirst is given, override default verbose behavior
    function _cnf_pre_search_warn --argument-names cmd
        _cnf_prompt_yn "\"$cmd\" is not found locally, search in repositories?"
        return $status
    end
end

if $_cnf_noprompt
    function fish_command_not_found
        set cmd "$argv[1]"
        _cnf_pre_search_warn "$cmd"
        or return 127

        set packages (_cnf_command_packages "$cmd")
        switch (count $packages)
            case 0
                _cnf_cmd_not_found "$cmd"
            case 1
                _cnf_print "\"$cmd\" may be found in package \"$packages\"\n"
            case '*'
                _cnf_print "\"$cmd\" may be found in the following packages:"
                for package in $packages
                    _cnf_print "\t$package"
                end
        end
    end
else
    function _cnf_check_fzf
        if ! which fzf >/dev/null 2>/dev/null
            if _cnf_prompt_yn "Gathering input requires 'fzf', install it?"
                _cnf_asroot pacman -S fzf
            end
            if ! which fzf >/dev/null 2>/dev/null
                return 1
            end
        end
        return 0
    end

    function fish_command_not_found
        set cmd "$argv[1]"
        set scroll_header "Shift up or down to scroll the preview"
        _cnf_pre_search_warn "$cmd"
        or return 127
        set packages (_cnf_command_packages "$cmd")
        switch (count $packages)
            case 0
                _cnf_cmd_not_found "$cmd"
            case 1
                function _cnf_prompt_install --argument-names packages
                    if _cnf_prompt_yn "Would you like to install '$packages'?"
                        _cnf_asroot pacman -S "$packages"
                    else
                        return 127
                    end
                end

                set action
                if test -z "$_cnf_action"
                    set may_be_found "\"$cmd\" may be found in package \"$packages\""
                    _cnf_print "$may_be_found\n"
                    _cnf_check_fzf; or return 127
                    _cnf_print "What would you like to do? "
                    set action (printf "%s\n" $_cnf_actions | \
                        fzf --preview "echo {} | grep -q '^list' && pacman -Flq '$packages' \
                                || pacman -Si '$packages'" \
                            --prompt "Action (\"esc\" to abort):" \
                            --header "$may_be_found"\n$scroll_header)
                else
                    set action "$_cnf_action"
                end

                switch "$action"
                    case 'install'
                        _cnf_asroot pacman -S "$packages"
                    case 'info'
                        pacman -Si "$packages"
                        _cnf_prompt_install "$packages"
                    case 'list files'
                        pacman -Flq "$packages"
                        _cnf_prompt_install "$packages"
                    case 'list files (paged)'
                        test -z "$pager"; and set --local pager less
                        pacman -Flq "$packages" | "$pager"
                        _cnf_prompt_install "$packages"
                    case '*'
                        return 127
                end
            case '*'
                _cnf_print "\"$cmd\" may be found in the following packages:"
                for package in $packages
                    _cnf_print "\t$package"
                end
                _cnf_check_fzf; or return 127
                set --local package (printf "%s\n" $packages | \
                    fzf --bind="tab:preview(pacman -Flq {})" \
                        --preview "pacman -Si {}" \
                        --header "Press \"tab\" to view files"\n$scroll_header \
                        --prompt "Select a package to install (\"esc\" to abort):")
                test -n "$package"; and _cnf_asroot pacman -S "$package"; or return 127
        end
    end
end

function __fish_command_not_found_handler \
    --on-event fish_command_not_found
    fish_command_not_found "$argv"
end

# Clean up environment
set -e _cnf_askfirst _cnf_noprompt _cnf_noupdate _cnf_verbose
