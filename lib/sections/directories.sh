#!/usr/bin/env bash
# Directories: render cached label|path|size[|type|newest_age] lines.
# 5-field format is current (v1.10.0+); 3-field is the legacy fallback
# from older caches and still works (type defaults to dir, no age shown).

section_directories() {
    local data
    data=$(cache_read "directories" "")
    [[ -z "$data" ]] && return

    section_heading "Monitored directories"
    local line label path size type newest_age short color age_color suffix
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        IFS='|' read -r label path size type newest_age <<<"$line"
        [[ -z "$type" ]] && type="dir"
        short="$label"
        (( ${#short} > 22 )) && short="${short:0:21}…"

        color="${C_RESET}"
        [[ "$size" == "missing" ]] && color="${C_RED}"

        # For backup-flagged dirs, append the newest-file age with a color
        # cue: green (recent), yellow (>=2 days), red (>=7 days or empty).
        suffix=""
        if [[ "$type" == "backup" ]]; then
            if [[ -z "$newest_age" ]]; then
                suffix=" ${C_DIM}(${C_RED}no files${C_DIM})${C_RESET}"
            else
                age_color="${C_GREEN}"
                case "$newest_age" in
                    *"d ago")
                        local days="${newest_age% d ago}"
                        days="${newest_age%d ago}"
                        if (( days >= 7 ));      then age_color="${C_RED}"
                        elif (( days >= 2 ));    then age_color="${C_YELLOW}"
                        fi
                        ;;
                esac
                suffix=" ${C_DIM}(newest: ${age_color}${newest_age}${C_DIM})${C_RESET}"
            fi
        fi

        printf "   %-22s %s%-7s%s %s%s%s%s\n" \
            "$short" \
            "$color" "$size" "${C_RESET}" \
            "${C_DIM}" "$path" "${C_RESET}" \
            "$suffix"
    done <<<"$data"
    section_rule
}
