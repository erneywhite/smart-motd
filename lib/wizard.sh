#!/usr/bin/env bash
# smart-motd: paged interactive wizard primitives.
#
# Each "page" clears the screen, shows a header (title + step counter),
# the question, the input area, and a bottom hint line. All UI rendering
# goes to /dev/tty so functions can be safely captured with $().
#
# Public API:
#   wizard_init <total_steps> <main_title>
#   wizard_intro <title> <body>
#   wizard_done  <title> <body>
#   wizard_text   <title> <help> [default]                  # echoes user input
#   wizard_password <title> <help>                          # echoes user input (no echo to screen)
#   wizard_yesno  <title> <help> [y|n]                      # exits 0 (yes) / 1 (no)
#   wizard_select <title> <help> [default_idx] -- opt1 opt2 ...
#                                                           # echoes selected option
#   wizard_select_preview <title> <help> <default_idx> <render_fn> -- opt1 opt2 ...
#                                                           # echoes selected option;
#                                                           # render_fn "$option" prints preview lines
#   wizard_multiselect <title> <help> -- "1opt1" "0opt2" ...
#                                                           # echoes selected options (one per line)
#                                                           # leading 1/0 = pre-checked / unchecked
#   wizard_list <title> <help> [item1 item2 ...]            # echoes resulting list (one per line)

set +u

WIZ_STEP=0
WIZ_TOTAL=0
WIZ_MAIN_TITLE="smart-motd setup"

# Step counter is persisted to a temp file so subshell-invoked
# wizard functions (called via $(...) or <(...) for output capture)
# can update it visibly to the parent shell. Without this, every
# page re-reads WIZ_STEP=0 from the parent and shows "step 1".
WIZ_STEP_FILE="${WIZ_STEP_FILE:-}"

_wiz_step_init() {
    if [[ -z "$WIZ_STEP_FILE" ]] || [[ ! -f "$WIZ_STEP_FILE" ]]; then
        WIZ_STEP_FILE=$(mktemp -t smart-motd-step.XXXXXX 2>/dev/null || mktemp)
        printf '0\n' >"$WIZ_STEP_FILE"
        export WIZ_STEP_FILE
        # Best-effort cleanup. Won't fire on Ctrl+C from inside a subshell,
        # but mktemp(1) files are world-writable in /tmp so it's fine.
        trap '[[ -f "$WIZ_STEP_FILE" ]] && rm -f "$WIZ_STEP_FILE"' EXIT
    fi
}

_wiz_step_incr() {
    _wiz_step_init
    local n
    n=$(<"$WIZ_STEP_FILE")
    n=$((n + 1))
    printf '%d\n' "$n" >"$WIZ_STEP_FILE"
}

_wiz_step_get() {
    _wiz_step_init
    cat "$WIZ_STEP_FILE" 2>/dev/null || echo 0
}

_wiz_step_reset() {
    _wiz_step_init
    printf '0\n' >"$WIZ_STEP_FILE"
}

# --- terminal helpers ---

_wiz_cols() {
    local c
    c=$(tput cols 2>/dev/tty 2>/dev/null) || c=80
    [[ "$c" -lt 40 ]] && c=80
    [[ "$c" -gt 110 ]] && c=110
    printf '%d' "$c"
}

_wiz_show_cursor() { printf '\e[?25h' >/dev/tty 2>/dev/null || true; }
_wiz_hide_cursor() { printf '\e[?25l' >/dev/tty 2>/dev/null || true; }

# Full screen clear — call ONCE at entry to a new page. In-loop redraws
# use _wiz_home (no clear) + per-line clear-eol + final clear-tail to
# avoid flashing.
_wiz_clear()       { printf '\e[2J\e[H' >/dev/tty 2>/dev/null || true; }
_wiz_home()        { printf '\e[H' >/dev/tty 2>/dev/null || true; }
_wiz_clear_tail()  { printf '\e[J' >/dev/tty 2>/dev/null || true; }

trap '_wiz_show_cursor' EXIT INT TERM

# Internal: print to terminal (not stdout). \e[K (clear from cursor to
# end of line) is injected after every \n in the argument, so that any
# leftover content from a previous render gets wiped without a full
# screen clear.
_p() {
    local text="${1//\\n/\\e[K\\n}"
    printf '%b' "$text" >/dev/tty
}
_pln() {
    local text="${1//\\n/\\e[K\\n}"
    printf '%b\e[K\n' "$text" >/dev/tty
}

# Repeat a character N times.
_repeat() {
    local ch="$1" n="$2"
    printf "%${n}s" '' | tr ' ' "$ch"
}

# Truncate a plain string to N chars, appending "…" if truncated.
# Used to keep multiselect / select option labels from spilling past
# the right edge on narrow terminals. Don't pass strings that contain
# ANSI escape codes — wizard option labels don't.
_truncate() {
    local s="$1" max="$2"
    if (( ${#s} <= max )); then
        printf '%s' "$s"
    else
        printf '%s…' "${s:0:$((max - 1))}"
    fi
}

# Word-wrap text to N columns. Pure bash so we never break inside a
# multibyte UTF-8 sequence (which `fold -w` does — it counts bytes,
# not characters, and turns each ─ / `─` divider line into garbage on
# wrap). Splits only on ASCII spaces, which are always 1 byte, so
# Cyrillic / box-drawing / emoji content is preserved verbatim.
_wrap() {
    local text="$1" width="${2:-78}"
    local line cur w
    local words=()
    while IFS= read -r line; do
        if (( ${#line} <= width )); then
            printf '%s\n' "$line"
            continue
        fi
        # word-wrap this line on whitespace
        # shellcheck disable=SC2206
        words=( $line )
        cur=""
        for w in "${words[@]}"; do
            if [[ -z "$cur" ]]; then
                cur="$w"
            elif (( ${#cur} + 1 + ${#w} <= width )); then
                cur="$cur $w"
            else
                printf '%s\n' "$cur"
                cur="$w"
            fi
        done
        [[ -n "$cur" ]] && printf '%s\n' "$cur"
    done <<<"$text"
}

# --- header & footer ---

wizard_init() {
    WIZ_TOTAL="$1"
    WIZ_STEP=0
    [[ -n "${2:-}" ]] && WIZ_MAIN_TITLE="$2"
}

_wiz_header() {
    local title="$1"
    local cols; cols=$(_wiz_cols)
    _wiz_home

    local step=""
    local step_n
    step_n=$(_wiz_step_get)
    if (( step_n > 0 )); then
        if (( WIZ_TOTAL > 0 )); then
            step="step ${step_n} of ${WIZ_TOTAL} "
        else
            step="step ${step_n} "
        fi
    fi
    local left=" ${WIZ_MAIN_TITLE}"
    local right="${step} "
    local pad=$(( cols - ${#left} - ${#right} ))
    (( pad < 1 )) && pad=1
    _p "\e[1;46;30m${left}$(_repeat ' ' $pad)${right}\e[0m\n"
    _p "\n"
    _p "\e[1m${title}\e[0m\n\n"
}

_wiz_help() {
    local help="$1"
    local cols; cols=$(_wiz_cols)
    [[ -z "$help" ]] && return
    while IFS= read -r line; do
        _p "\e[2m${line}\e[0m\n"
    done < <(_wrap "$help" $((cols - 4)))
    _p "\n"
}

_wiz_footer() {
    local hint="$1"
    _p "\n\e[2m─── ${hint}\e[0m\n"
}

# --- intro / done pages ---

wizard_intro() {
    local title="$1" body="$2"
    _wiz_header "$title"
    _wiz_help "$body"
    _wiz_footer "Press Enter to begin · Ctrl+C to cancel"
    _wiz_clear_tail
    local _key
    IFS= read -r _key </dev/tty || true
}

wizard_done() {
    local title="$1" body="$2"
    _wiz_header "$title"
    _wiz_help "$body"
    _wiz_footer "Press Enter to finish"
    _wiz_clear_tail
    local _key
    IFS= read -r _key </dev/tty || true
}

# --- text input ---

wizard_text() {
    _wiz_step_incr
    local title="$1" help="$2" default="${3:-}"
    _wiz_header "$title"
    _wiz_help "$help"
    _p "  > "
    # Wipe everything below the prompt — leftover content from a previous,
    # taller page (multiselect, list editor) would otherwise be visible
    # under the input.
    _wiz_clear_tail
    _wiz_show_cursor
    local result
    if [[ -n "$default" ]]; then
        IFS= read -r -e -i "$default" result </dev/tty
    else
        IFS= read -r -e result </dev/tty
    fi
    printf '%s' "$result"
}

wizard_password() {
    _wiz_step_incr
    local title="$1" help="$2"
    _wiz_header "$title"
    _wiz_help "$help"
    _p "  > "
    _wiz_clear_tail
    local result
    IFS= read -r -s result </dev/tty
    _p "\n"
    printf '%s' "$result"
}

# --- yes / no (just a 2-option select with shortcut keys) ---

wizard_yesno() {
    _wiz_step_incr
    local title="$1" help="$2" default="${3:-y}"
    local sel=0
    [[ "$default" == "n" || "$default" == "no" ]] && sel=1
    local options=("Yes" "No")

    _wiz_hide_cursor
    local key seq
    while true; do
        _wiz_header "$title"
        _wiz_help "$help"

        local i
        for i in 0 1; do
            if (( i == sel )); then
                _p "  \e[1;36m❯ ${options[i]}\e[0m\n"
            else
                _p "    ${options[i]}\n"
            fi
        done
        _wiz_footer "↑/↓ or y/n · Enter to confirm"

        _wiz_clear_tail
        IFS= read -rsn1 key </dev/tty || break
        case "$key" in
            $'\e')
                IFS= read -rsn2 -t 0.05 seq </dev/tty 2>/dev/null || seq=""
                case "$seq" in
                    "[A"|"OA") sel=0 ;;
                    "[B"|"OB") sel=1 ;;
                esac
                ;;
            "")  break ;;
            y|Y) sel=0; break ;;
            n|N) sel=1; break ;;
            j|J) sel=1 ;;
            k|K) sel=0 ;;
        esac
    done
    _wiz_show_cursor
    return $sel
}

# --- single-choice select ---
# Usage:
#   wizard_select "Title" "Help" 0 -- "Option A" "Option B" "Option C"

wizard_select() {
    _wiz_step_incr
    local title="$1" help="$2" sel="${3:-0}"
    shift 3
    [[ "${1:-}" == "--" ]] && shift
    local options=("$@")
    local n=${#options[@]}
    (( sel < 0 || sel >= n )) && sel=0

    _wiz_hide_cursor
    local key seq i cols max_label label
    while true; do
        _wiz_header "$title"
        _wiz_help "$help"
        cols=$(_wiz_cols)
        max_label=$(( cols - 6 ))  # account for "  ❯ " prefix + 1 char margin
        (( max_label < 10 )) && max_label=10

        for i in "${!options[@]}"; do
            label=$(_truncate "${options[i]}" "$max_label")
            if (( i == sel )); then
                _p "  \e[1;36m❯ ${label}\e[0m\n"
            else
                _p "    ${label}\n"
            fi
        done
        _wiz_footer "↑/↓ navigate · 1-9 jump · Enter to confirm"

        _wiz_clear_tail
        IFS= read -rsn1 key </dev/tty || break
        case "$key" in
            $'\e')
                IFS= read -rsn2 -t 0.05 seq </dev/tty 2>/dev/null || seq=""
                case "$seq" in
                    "[A"|"OA") (( sel > 0 )) && sel=$((sel - 1)) ;;
                    "[B"|"OB") (( sel < n - 1 )) && sel=$((sel + 1)) ;;
                esac
                ;;
            "")  break ;;
            j|J) (( sel < n - 1 )) && sel=$((sel + 1)) ;;
            k|K) (( sel > 0 )) && sel=$((sel - 1)) ;;
            [1-9])
                local idx=$((key - 1))
                (( idx < n )) && sel=$idx
                ;;
        esac
    done
    _wiz_show_cursor
    printf '%s' "${options[$sel]}"
}

# --- single-choice select with live preview ---
# render_fn is the name of a function that takes the option as an argument
# and prints preview lines to stdout. Each preview line is shown with a left
# rule under "Preview:".

wizard_select_preview() {
    _wiz_step_incr
    local title="$1" help="$2" sel="${3:-0}" render_fn="$4"
    shift 4
    [[ "${1:-}" == "--" ]] && shift
    local options=("$@")
    local n=${#options[@]}
    (( sel < 0 || sel >= n )) && sel=0

    _wiz_hide_cursor
    local key seq i cols max_label label
    while true; do
        _wiz_header "$title"
        _wiz_help "$help"
        cols=$(_wiz_cols)
        max_label=$(( cols - 6 ))
        (( max_label < 10 )) && max_label=10

        for i in "${!options[@]}"; do
            label=$(_truncate "${options[i]}" "$max_label")
            if (( i == sel )); then
                _p "  \e[1;36m❯ ${label}\e[0m\n"
            else
                _p "    ${label}\n"
            fi
        done

        _p "\n  \e[2m── Preview ──\e[0m\n"
        local pline
        while IFS= read -r pline; do
            _p "    ${pline}\n"
        done < <("$render_fn" "${options[$sel]}" 2>/dev/null)

        _wiz_footer "↑/↓ navigate · Enter to confirm"

        _wiz_clear_tail
        IFS= read -rsn1 key </dev/tty || break
        case "$key" in
            $'\e')
                IFS= read -rsn2 -t 0.05 seq </dev/tty 2>/dev/null || seq=""
                case "$seq" in
                    "[A"|"OA") (( sel > 0 )) && sel=$((sel - 1)) ;;
                    "[B"|"OB") (( sel < n - 1 )) && sel=$((sel + 1)) ;;
                esac
                ;;
            "")  break ;;
            j|J) (( sel < n - 1 )) && sel=$((sel + 1)) ;;
            k|K) (( sel > 0 )) && sel=$((sel - 1)) ;;
        esac
    done
    _wiz_show_cursor
    printf '%s' "${options[$sel]}"
}

# --- multi-select (checkboxes) ---
# Each option is a prefixed string: "1Option A" (checked) or "0Option B" (unchecked)
# Returns: lines of selected option labels (without the prefix).

wizard_multiselect() {
    _wiz_step_incr
    local title="$1" help="$2"
    shift 2
    [[ "${1:-}" == "--" ]] && shift
    local options=("$@")
    local n=${#options[@]}
    local sel=0
    local checked=()
    local i
    for i in "${!options[@]}"; do
        local first="${options[i]:0:1}"
        if [[ "$first" == "1" ]]; then
            checked[i]=1
        else
            checked[i]=0
        fi
        options[i]="${options[i]:1}"
    done

    _wiz_hide_cursor
    local key seq cols max_label label mark
    while true; do
        _wiz_header "$title"
        _wiz_help "$help"
        cols=$(_wiz_cols)
        max_label=$(( cols - 10 ))  # "  ❯ [✓] " prefix
        (( max_label < 10 )) && max_label=10

        for i in "${!options[@]}"; do
            mark="\e[2m[ ]\e[0m"
            [[ "${checked[i]}" == "1" ]] && mark="\e[1;32m[✓]\e[0m"
            label=$(_truncate "${options[i]}" "$max_label")
            if (( i == sel )); then
                _p "  \e[1;36m❯\e[0m ${mark} \e[1m${label}\e[0m\n"
            else
                _p "    ${mark} ${label}\n"
            fi
        done
        _wiz_footer "↑/↓ move · Space toggle · a all · n none · Enter confirm"

        _wiz_clear_tail
        IFS= read -rsn1 key </dev/tty || break
        case "$key" in
            $'\e')
                IFS= read -rsn2 -t 0.05 seq </dev/tty 2>/dev/null || seq=""
                case "$seq" in
                    "[A"|"OA") (( sel > 0 )) && sel=$((sel - 1)) ;;
                    "[B"|"OB") (( sel < n - 1 )) && sel=$((sel + 1)) ;;
                esac
                ;;
            "")  break ;;
            " ") checked[sel]=$(( 1 - ${checked[sel]:-0} )) ;;
            a|A) for i in "${!options[@]}"; do checked[i]=1; done ;;
            n|N) for i in "${!options[@]}"; do checked[i]=0; done ;;
            j|J) (( sel < n - 1 )) && sel=$((sel + 1)) ;;
            k|K) (( sel > 0 )) && sel=$((sel - 1)) ;;
        esac
    done
    _wiz_show_cursor
    for i in "${!options[@]}"; do
        [[ "${checked[i]}" == "1" ]] && printf '%s\n' "${options[i]}"
    done
}

# --- list editor ---
# Usage:
#   result=$(wizard_list "Title" "Help" "${current[@]}")
#   mapfile -t newlist <<<"$result"
# (Note: empty list returns no output.)

wizard_list() {
    _wiz_step_incr
    local title="$1" help="$2"
    shift 2
    local items=("$@")
    local key

    while true; do
        _wiz_header "$title"
        _wiz_help "$help"

        local cols max_label label
        cols=$(_wiz_cols)
        max_label=$(( cols - 8 ))
        (( max_label < 10 )) && max_label=10

        if [[ ${#items[@]} -eq 0 ]]; then
            _p "  \e[2m(empty list)\e[0m\n"
        else
            local i
            for i in "${!items[@]}"; do
                label=$(_truncate "${items[i]}" "$max_label")
                _p "  \e[2m$(printf '%2d.' $((i+1)))\e[0m ${label}\n"
            done
        fi
        _wiz_footer "[a] add · [d] delete last · [c] clear · Enter to finish"

        _wiz_clear_tail
        IFS= read -rsn1 key </dev/tty || break
        case "$key" in
            a|A)
                _p "\n  Add: "
                _wiz_show_cursor
                local new
                IFS= read -r new </dev/tty
                _wiz_hide_cursor
                [[ -n "$new" ]] && items+=("$new")
                ;;
            d|D)
                if [[ ${#items[@]} -gt 0 ]]; then
                    unset 'items[${#items[@]}-1]'
                    items=("${items[@]}")
                fi
                ;;
            c|C)
                items=()
                ;;
            "")  break ;;
        esac
    done
    _wiz_show_cursor
    if [[ ${#items[@]} -gt 0 ]]; then
        printf '%s\n' "${items[@]}"
    fi
}
