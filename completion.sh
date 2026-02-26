#!/bin/bash
# Autonomy CLI Completion Script
# Add to .bashrc: source /path/to/completion.sh

_autonomy_complete() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    
    # Main commands
    local commands="status on off work task spawn schedule tool update logs daemon install help version"
    
    # Subcommands based on context
    case "$prev" in
        autonomy)
            COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
            return 0
            ;;
        task)
            local task_cmds="create complete list show delete"
            COMPREPLY=( $(compgen -W "$task_cmds" -- "$cur") )
            return 0
            ;;
        daemon)
            local daemon_cmds="start stop restart status once logs"
            COMPREPLY=( $(compgen -W "$daemon_cmds" -- "$cur") )
            return 0
            ;;
        install)
            local install_cmds="daemon cron auto"
            COMPREPLY=( $(compgen -W "$install_cmds" -- "$cur") )
            return 0
            ;;
        schedule)
            local sched_cmds="list add remove"
            COMPREPLY=( $(compgen -W "$sched_cmds" -- "$cur") )
            return 0
            ;;
        tool)
            local tool_cmds="list create"
            COMPREPLY=( $(compgen -W "$tool_cmds" -- "$cur") )
            return 0
            ;;
        update)
            local update_cmds="check apply"
            COMPREPLY=( $(compgen -W "$update_cmds" -- "$cur") )
            return 0
            ;;
        complete|delete|show)
            # Complete with task names
            local tasks=$(ls ~/.openclaw/workspace/skills/autonomy/tasks/*.json 2>/dev/null | xargs -I {} basename {} .json)
            COMPREPLY=( $(compgen -W "$tasks" -- "$cur") )
            return 0
            ;;
    esac
}

# Register completion
complete -F _autonomy_complete autonomy
complete -F _autonomy_complete ./autonomy
