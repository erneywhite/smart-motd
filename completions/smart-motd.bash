# Bash completion for smart-motd. Installed to
# /usr/share/bash-completion/completions/smart-motd (or
# /etc/bash_completion.d/smart-motd as a fallback) by install.sh.
# Also works in zsh sessions that have run `bashcompinit`.

_smart_motd() {
    local cur
    cur="${COMP_WORDS[COMP_CWORD]}"

    # Only complete the first positional — none of our subcommands take args.
    if [[ "$COMP_CWORD" -eq 1 ]]; then
        local opts="show setup update-cache edit status doctor version upgrade uninstall help"
        # shellcheck disable=SC2207
        COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
        return 0
    fi
    COMPREPLY=()
}
complete -F _smart_motd smart-motd
