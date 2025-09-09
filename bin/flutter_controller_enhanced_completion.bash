#!/bin/bash

# Bash completion for flutter_controller_enhanced.sh
# To enable: source this file or copy to /etc/bash_completion.d/

_flutter_controller_enhanced() {
    local cur prev opts devices
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    
    # Main commands
    opts="run r R q quit status logs clear-logs monitor restart cleanup"
    
    # Flutter devices (common ones)
    devices="emulator-5554 chrome linux macos windows android ios"
    
    case "${prev}" in
        run|restart)
            # Complete with device names for run and restart commands
            COMPREPLY=($(compgen -W "${devices}" -- ${cur}))
            return 0
            ;;
        logs)
            # Complete with common line numbers for logs command
            COMPREPLY=($(compgen -W "10 25 50 100 200 500" -- ${cur}))
            return 0
            ;;
        *)
            # Complete with main commands
            COMPREPLY=($(compgen -W "${opts}" -- ${cur}))
            return 0
            ;;
    esac
}

# Register completion for the script
complete -F _flutter_controller_enhanced flutter_controller_enhanced.sh
complete -F _flutter_controller_enhanced flutter_controller_enhanced

# Also handle common aliases that might be used
complete -F _flutter_controller_enhanced fce
complete -F _flutter_controller_enhanced flutter_ctl