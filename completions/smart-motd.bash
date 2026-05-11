# Bash completion for smart-motd. Installed to
# /usr/share/bash-completion/completions/smart-motd (or
# /etc/bash_completion.d/smart-motd as a fallback) by install.sh.
# Also works in zsh sessions that have run `bashcompinit`.

_smart_motd() {
    local cur prev
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    if [[ "$COMP_CWORD" -eq 1 ]]; then
        local opts="show watch setup update-cache edit config test-alert status doctor version upgrade benchmark uninstall help"
        # shellcheck disable=SC2207
        COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
        return 0
    fi

    # Second positional — sub-sub-commands for config / test-alert.
    if [[ "$COMP_CWORD" -eq 2 ]]; then
        case "$prev" in
            config)
                # shellcheck disable=SC2207
                COMPREPLY=( $(compgen -W "get set help" -- "$cur") )
                return 0 ;;
            test-alert)
                # shellcheck disable=SC2207
                COMPREPLY=( $(compgen -W "ssh recap help" -- "$cur") )
                return 0 ;;
        esac
    fi

    COMPREPLY=()
}
complete -F _smart_motd smart-motd
