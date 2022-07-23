function __cnf_print --argument-names message
    echo -e 1>&2 "$message"
end

set __cnf_action
set __cnf_askfirst false
set __cnf_force_su false
set __cnf_noprompt false
set __cnf_verbose true

set __cnf_actions "install" "info" "list files" "list files (paged)"

for opt in $argv
    if test (string length "$opt") -gt 0
        switch "$opt"
            case askfirst
                set __cnf_askfirst true
            case noprompt
                set __cnf_noprompt true
            case su
                set __cnf_force_su true
            case quiet
                set __cnf_verbose false
            case install
                set __cnf_action "$__cnf_actions[1]"
            case info
                set __cnf_action "$__cnf_actions[2]"
            case list_files
                set __cnf_action "$__cnf_actions[3]"
            case list_files_paged
                set __cnf_action "$__cnf_actions[4]"
            case '*'
                __cnf_print "find-the-command: unknown option: $opt"
        end
    end
end

# Delete __cnf_pre_search_warn so we can check if we've created the function
functions -e __cnf_pre_search_warn

if $__cnf_askfirst
    function __cnf_pre_search_warn --argument-names cmd
        read --prompt="echo \"find-the-command: \"$cmd\" is not found locally, search in repositories? [Y/n] \"" result
        or return $status
        switch "$result"
        case 'y*' 'Y*' ''
            return 0
        case '*'
            return 127
        end
    end
end

if $__cnf_verbose
    if test "$(type -t __cnf_pre_search_warn 2>/dev/null)" != function
        function __cnf_pre_search_warn --argument-names cmd
            __cnf_print "find-the-command: \"$cmd\" is not found locally, searching in repositories...\n"
            return 0
        end
    end

    function __cnf_cmd_not_found --argument-names cmd
        __cnf_print "find-the-command: command not found: $cmd"
        return 127
    end
else
    if test "$(type -t __cnf_pre_search_warn 2>/dev/null)" != function
        function __cnf_pre_search_warn
            return 0
        end
    end

    function __cnf_cmd_not_found
        return 127
    end
end

if $__cnf_noprompt
    function fish_command_not_found
        set cmd "$argv[1]"
        __cnf_pre_search_warn "$cmd"
        or return $status

        set packages (pkgfile --binaries -- "$cmd" ^/dev/null)
        switch (echo "$packages" | wc -w)
            case 0
                __cnf_cmd_not_found "$cmd"
            case 1
                __cnf_print "\"$cmd\" may be found in package \"$packages\"\n"
            case '*'
                __cnf_print "\"$cmd\" may be found in the following packages:"
                for package in $packages
                    __cnf_print "\t$package"
                end
        end
    end
else
    function __cnf_asroot; $argv; end
    if test (id -u) -ne 0
        if $__cnf_force_su
            function __cnf_asroot; su -c "$argv"; end
        else
            function __cnf_asroot; sudo $argv; end
        end
    end
    function fish_command_not_found
        set cmd "$argv[1]"
        __cnf_pre_search_warn "$cmd"
        or return $status
        set packages (pkgfile --binaries -- "$cmd" ^/dev/null)
        switch (echo "$packages" | wc -w)
            case 0
                __cnf_cmd_not_found "$cmd"
            case 1
                function __prompt_install --argument-names packages
                    read --prompt="echo \"Would you like to install '$packages'? [Y/n] \"" result
                    or return $status
                    switch "$result"
                    case 'y*' 'Y*' ''
                        __cnf_asroot pacman -S "$packages"
                    case '*'
                        return 127
                    end
                end

                set action
                if test -z "$__cnf_action"
                    set may_be_found "\"$cmd\" may be found in package \"$packages\""
                    __cnf_print "$may_be_found\n"
                    __cnf_print "What would you like to do? "
                    set action (printf "%s\n" $__cnf_actions | \
                        fzf --prompt "Action (\"esc\" to abort):" --header "$may_be_found")
                else
                    set action "$__cnf_action"
                end

                switch "$action"
                    case 'install'
                        __cnf_asroot pacman -S "$packages"
                    case 'info'
                        pacman -Si "$packages"
                        __prompt_install "$packages"
                    case 'list files'
                        pacman -Flq "$packages"
                        __prompt_install "$packages"
                    case 'list files (paged)'
                        test -z "$pager"; and set --local pager less
                        pacman -Flq "$packages" | "$pager"
                        __prompt_install "$packages"
                    case '*'
                        return 127
                end
            case '*'
                __cnf_print "\"$cmd\" may be found in the following packages:\n"
                set --local package (printf "%s\n" $packages | fzf --prompt "Select a package to install (\"esc\" to abort):")
                test -n "$package"; and __cnf_asroot pacman -S "$package"; or return 127
        end
    end
end

function __fish_command_not_found_handler \
    --on-event fish_command_not_found
    fish_command_not_found "$argv"
end
