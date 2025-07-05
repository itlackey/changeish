


is_valid_git_range() {
    git rev-list "$1" >/dev/null 2>&1
}

is_valid_pattern() {
    git ls-files --error-unmatch "$1" >/dev/null 2>&1
}

# Portable mktemp: fallback if mktemp not available
portable_mktemp() {
    if command -v mktemp >/dev/null 2>&1; then
        mktemp
    else
        TMP="${TMPDIR-/tmp}"
        # Use date +%s and $$ for uniqueness
        echo "${TMP}/tmp.$$.$(date +%s)"
    fi
}

build_prompt() {
    prompt_file="$1"
    diff_file="$2"

    # Concatenate the prompt template and diff file content
    result="$(
        cat "${prompt_file}"
        echo
        cat "${diff_file}"
    )"

    # Return the result as a multiline string
    printf "%s\n" "${result}"
}

# Extract version string from a line (preserving v if present)
parse_version() {
    #printf 'Parsing version from: %s\n' "$1" >&2
    # Accepts a string, returns version like v1.2.3 or 1.2.3
    out=$(echo "$1" | sed -n -E 's/.*([vV][0-9]+\.[0-9]+\.[0-9]+).*/\1/p')
    if [ -z "$out" ]; then
        out=$(echo "$1" | sed -n -E 's/.*([0-9]+\.[0-9]+\.[0-9]+).*/\1/p')
    fi
    printf '%s' "$out"
}

json_escape() {
    # Reads stdin, outputs JSON-escaped string (with surrounding quotes)
    # Handles: backslash, double quote, newlines, tabs, carriage returns, form feeds, backspaces
    # Newlines are replaced with \n using tr
    sed -e 's/\\/\\\\/g' \
        -e 's/"/\\"/g' \
        -e 's/\r/\\r/g' \
        -e 's/\t/\\t/g' \
        -e 's/\f/\\f/g' \
        -e 's/\b/\\b/g' |
        awk 'BEGIN{printf "\""} {printf "%s", $0} END{print "\""}'
}

extract_content() {
    # Usage: extract_content "$json_string"
    json=$1

    # 1) pull out the raw, escaped value of "content":
    raw=$(printf '%s' "$json" | awk '
  {
    text = $0
    # find the start of "content"
    idx = index(text, "\"content\"")
    if (idx == 0) exit

    # jump to after "content"
    after = substr(text, idx + length("\"content\""))
    # find the colon
    colon = index(after, ":")
    if (colon == 0) exit
    after = substr(after, colon + 1)
    # strip leading whitespace
    sub(/^[[:space:]]*/, "", after)

    # must start with a double-quote
    if (substr(after,1,1) != "\"") exit
    s = substr(after,2)    # drop that opening "

    val = ""
    esc = 0
    # accumulate until an unescaped quote
    for (i = 1; i <= length(s); i++) {
      c = substr(s,i,1)
      if (c == "\\" && esc == 0) {
        esc = 1
        val = val c
      } else if (c == "\"" && esc == 0) {
        break
      } else {
        esc = 0
        val = val c
      }
    }
    print val
  }')

    # 2) interpret backslash-escapes (\n, \", \\) into real characters:
    printf '%b' "$raw"
}

generate_remote() {
    content=$(cat "$1")

    # Escape for JSON (replace backslash, double quote, and control characters)
    # Use json_escape to safely encode the prompt as a JSON string
    escaped_content=$(printf "%s" "${content}" | json_escape)
    body=$(printf '{"model":"%s","messages":[{"role":"user","content":%s}],"max_completion_tokens":8192}' \
        "${api_model}" "${escaped_content}")

    response=$(curl -s -X POST "${api_url}" \
        -H "Authorization: Bearer ${api_key}" \
        -H "Content-Type: application/json" \
        -d "${body}")

    if [ -n "${debug}" ]; then
        echo "Response from remote API:" >&2
        echo "${response}" >&2
        #echo "${response}" >> "response.json"
    fi

    # Extract the content field from the response
    result=$(extract_content "${response}")

    [ -n "$debug" ] && printf 'Debug: Parsed response:\n%s\n' "$result" >&2
    echo "${result}"
}

run_local() {
    if [ -n "${debug}" ]; then
        ollama run "${model}" --verbose <"$1"
    else
        ollama run "${model}" <"$1"
    fi
}

generate_response() {
    [ -n "${debug}" ] && printf 'Debug: Generating response using %s model...\n' "${model_provider}" >&2
    case ${model_provider} in
    remote) generate_remote "$1" ;;
    none) cat "$1" ;;
    *) run_local "$1" ;;
    esac
}

generate_from_prompt() {
    prompt_file="$1"
    output_file="$2"
    [ -n "${debug}" ] && printf 'Generating response from prompt file %s...\n' "${prompt_file}"
    res=$(generate_response "${prompt_file}")
    if [ -n "${output_file}" ] && [ "${dry_run}" != "true" ]; then
        printf '%s' "${res}" >"${output_file}"
        printf 'Response written to %s\n' "${output_file}"
    else
        printf '%s\n' "${res}"
    fi
}

# Extract TODO changes for history extraction
extract_todo_changes() {
    range="$1"
    pattern="${2:-$todo_pattern}"

    [ "$debug" = true ] && printf 'Debug: Extracting TODO changes for range: %s with pattern: %s\n' "${range}" "${pattern}" >&2
    # Default to no pattern if not set
    set -- # Reset positional args to avoid confusion

    if [ "${range}" = "--cached" ]; then
        td=$(git --no-pager diff --cached --unified=0 -b -w --no-prefix --color=never -- "${pattern}" 2>/dev/null || true)
    elif [ "${range}" = "--current" ] || [ -z "${range}" ]; then
        td=$(git --no-pager diff --unified=0 -b -w --no-prefix --color=never -- "${pattern}" 2>/dev/null || true)
    else
        td=$(git --no-pager diff "${range}^!" --unified=0 -b -w --no-prefix --color=never -- "${pattern}" 2>/dev/null || true)
    fi
    printf '%s' "${td}"
}

# helper: writes message header based on commit type
get_message_header() {
    commit="$1"
    [ -n "${debug}" ] && printf 'Debug: Getting message header for commit %s\n' "$commit" >&2
    case "$commit" in
    --cached) echo "Staged Changes" ;;
    --current | "") echo "Current Changes" ;;
    *) git log -1 --pretty=%B "$commit" ;;
    esac
}

# helper: finds the version file path
find_version_file() {
    [ -n "${debug}" ] && printf 'Debug: Finding version file...\n' >&2
    if [ -n "${version_file}" ] && [ -f "${version_file}" ]; then
        echo "${version_file}"
        return
    fi

    for vf in package.json pyproject.toml setup.py \
        Cargo.toml composer.json build.gradle pom.xml; do
        [ -f "${vf}" ] && {
            echo "${vf}"
            return
        }
    done

    [ -n "${debug}" ] && printf 'Debug: No version file found, searching for changes.sh...\n' >&2

    changes_sh=$(git ls-files --full-name | grep '/changes\.sh$' | head -n1)
    # Fallback: handle the case where "changes.sh" is in the root directory
    if [ -n "${changes_sh}" ]; then
        echo "${changes_sh}"
    fi
    if [ -n "${changes_sh}" ]; then
        echo "${changes_sh}"
    else 
      [ -n "${debug}" ] && printf 'Debug: No version file found, returning empty string.\n' >&2
        echo ""
    fi
  
}

# helper: extract version text from a file or git index/commit
get_version_info() {
    commit="$1"
    vf="$2"
    [ -n "$debug" ] && printf 'Debug: Getting version info for commit %s from file %s\n' "$commit" "$vf" >&2

    # Ensure empty string is returned on failure
    case "$commit" in
    --current | "")
        if [ -f "$vf" ]; then
            grep -Ei 'version[^0-9]*[0-9]+\.[0-9]+(\.[0-9]+)?' "$vf" | head -n1 || echo ""
        else
            echo ""
        fi
        ;;
    --cached)
        if git ls-files --cached --error-unmatch "$vf" >/dev/null 2>&1; then
            git show ":$vf" | grep -Ei 'version[^0-9]*[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 || echo ""
        elif [ -f "$vf" ]; then
            grep -Ei 'version[^0-9]*[0-9]+\.[0-9]+(\.[0-9]+)?' "$vf" | head -n1 || echo ""
        else
            echo ""
        fi
        ;;
    *)
        if git rev-parse --verify "$commit" >/dev/null 2>&1; then
            if git ls-tree -r --name-only "$commit" | grep -Fxq "$vf"; then
                git show "${commit}:${vf}" | grep -Ei 'version[^0-9]*[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 || echo ""
            elif [ -f "$vf" ]; then
                grep -Ei 'version[^0-9]*[0-9]+\.[0-9]+(\.[0-9]+)?' "$vf" | head -n1 || echo ""
            else
                echo ""
            fi
        else
            echo "" # Return empty string for invalid commit IDs
        fi
        ;;
    esac | {
        read -r raw
        parse_version "$raw"
    }
}

# helper: builds main diff output (tracked + optional untracked)
build_diff() {
    commit="$1"
    diff_pattern="$2"
    debug="$3"
    args=(--no-pager diff)
    case "$commit" in
    --cached) args+=(--cached) ;;
    --current | "") ;;
    *) args+=("${commit}^!") ;;
    esac
    [ -n "$debug" ] &&  printf 'Debug: Building diff for commit %s with pattern %s\n' "$commit" "$diff_pattern" >&2
    args+=(--minimal --no-prefix --unified=0 --no-color -b -w --compact-summary --color-moved=no)
    [ -n "$diff_pattern" ] && args+=(-- "$diff_pattern")

    [ "$debug" = true ] && printf 'Debug: git %s\n' "${args[*]}" >&2
    diff_output="$(git "${args[@]}")"

    # handle untracked files
    untracked=$(git ls-files --others --exclude-standard)
    IFS=$'\n'
    for f in $untracked; do
        [ ! -f "$f" ] && continue
        [ -n "$diff_pattern" ] && case "$f" in $diff_pattern) ;; *) continue ;; esac
        extra=$(git --no-pager diff --no-prefix --unified=0 --no-color -b -w --minimal --compact-summary --color-moved=no --no-index /dev/null "$f" 2>/dev/null || true)
        diff_output="${diff_output}${diff_output:+\n}${extra}"
    done
    IFS=' '

    printf '%s\n' "$diff_output"
}

# top-level refactored build_history
build_history() {
    hist="$1"
    commit="$2"
    todo_pattern="${3:-${CHANGEISH_TODO_PATTERN:-TODO}}"
    diff_pattern="${4:-}"

   [ -n "$debug" ] && printf 'Debug: Building history for commit %s\n' "$commit" >&2
    : >"$hist"

    # header
    msg=$(get_message_header "$commit")
    printf '**Message:** %s\n' "$msg" >>"$hist"

    # version
    vf=$(find_version_file)
    [ -n "$vf" ] && [ -n "$debug" ] &&  printf 'Debug: Found version file: %s\n' "$vf" >&2
    [ -n "$vf" ] && {
        ver=$(get_version_info "$commit" "$vf")
        [ -n "$ver" ] && printf '**Version:** %s\n' "$ver" >>"$hist"
    }

    # diff
    diff_out=$(build_diff "$commit" "$diff_pattern" "$debug")
    printf '```diff\n%s\n```\n' "$diff_out" >>"$hist"

    # TODO diff
    td=$(extract_todo_changes "$commit" "$todo_pattern")
    [ -n "$debug" ] && printf 'Debug: TODO changes: %s\n' "$td" >&2
    [ -n "$td" ] && printf '\n### TODO Changes\n```diff\n%s\n```\n' "$td" >>"$hist"

    return 0
}

summarize_target() {
    target="$1"
    summaries_file="$2"
    [ -n "$debug" ] && echo "DEBUG: summaries_file='$summaries_file', target='$target'"

    # If no target is specified, summarize the current commit or staged changes
    if [ "$target" = "--current" ] || [ "$target" = "--cached" ] || [ -z "$target" ]; then
        summarize_commit "$target" "$summaries_file"
        printf '\n\n' >>"$summaries_file"
    # Single commit
    elif git rev-parse --verify "$target" >/dev/null 2>&1 && [ "$(git rev-list --count "$target")" = "1" ]; then
        summarize_commit "$target" "$summaries_file"
        printf '\n\n' >>"$summaries_file"
    else
        # Handle commit ranges
        git rev-list --reverse "$target" | while IFS= read -r commit; do
            summarize_commit "$commit" "$summaries_file"
            printf '\n\n' >>"$summaries_file"
        done
    fi
}

summarize_commit() {
    commit="$1"
    out_file="$2"
    hist=$(portable_mktemp)
    pr=$(portable_mktemp)
    [ -n "$debug" ] && printf "DEBUG: summarize_commit commit='%s', hist='%s', prompt file='%s'\n" "$commit" "$hist" "$pr" >&2
    build_history "$hist" "$commit" "$todo_pattern" "$PATTERN"
    summary_template=$(build_prompt "${PROMPT_DIR}/summary_prompt.md" "$hist")
    #[ -n "$debug" ] && printf 'Debug: Using summary prompt: %s\n' "$summary_template"
    printf '%s\n' "$summary_template" >"$pr"
    res=$(generate_response "$pr")
    rm -f "$hist" "$pr"
    printf '%s\n' "$res" >>"$out_file"
}

# Remove duplicate blank lines and ensure file ends with newline
remove_duplicate_blank_lines() {
    # $1: file path
    awk 'NR==1{print} NR>1{if (!($0=="" && p=="")) print} {p=$0} END{if(p!="")print ""}' "$1" >"$1.tmp" && mv "$1.tmp" "$1"
}

extract_changelog_section() {
    ecs_section="$1"
    ecs_file="$2"
    if [ ! -f "${ecs_file}" ]; then
        echo ""
        return 0
    fi
    ecs_esc=$(echo "${ecs_section}" | sed 's/[][\\/.*^$]/\\&/g')
    ecs_pattern="^##[[:space:]]*\[?${ecs_esc}\]?"
    start_line=$(grep -nE "${ecs_pattern}" "${ecs_file}" | head -n1 | cut -d: -f1)
    if [ -z "${start_line}" ]; then
        echo ""
        return 0
    else
        start_line=$((start_line + 1))
    fi
    end_line=$(tail -n "$((start_line + 1))" "${ecs_file}" | grep -n '^## ' | head -n1 | cut -d: -f1)
    if [ -n "${end_line}" ]; then
        end_line=$((start_line + end_line - 1))
    else
        end_line=$(wc -l <"${ecs_file}")
    fi
    sed -n "${start_line},${end_line}p" "${ecs_file}"
}
# Updates a specific section in a changelog file, or adds it if not present.
# $1 - Path to the changelog file.
# $2 - Content to insert into the changelog section.
# $3 - Version string to use as the section header.
# $4 - Regex pattern to identify the section to replace.
update_changelog_section() {
    ic_file="$1"
    ic_content="$2"
    ic_version="$3"
    ic_pattern="$4"
    content_file=$(mktemp)
    printf "%s\n" "$ic_content" >"$content_file"
    if grep -qE "$ic_pattern" "$ic_file"; then
        awk -v pat="$ic_pattern" -v ver="$ic_version" -v content_file="$content_file" '
      BEGIN { in_section=0; replaced=0 }
      {
        if ($0 ~ pat && !replaced) {
          print "";
          print "## " ver;
          while ((getline line < content_file) > 0) print line;
          close(content_file);
          in_section=1;
          replaced=1;
          next
        }
        if (in_section && $0 ~ /^## /) in_section=0
        if (!in_section) print $0
      }
      ' "$ic_file" | awk 'NR==1{print} NR>1{if (!($0=="" && p=="")) print} {p=$0} END{if(p!="")print ""}' >"$ic_file.tmp"
        mv "$ic_file.tmp" "$ic_file"
        rm -f "$content_file"
        return 0
    else
        rm -f "$content_file"
        return 1
    fi
}

# Always inserts a new section at the top (after H1), even if duplicate exists.
prepend_changelog_section() {
    ic_file="$1"
    ic_content="$2"
    ic_version="$3"
    content_file=$(mktemp)
    printf "%s\n" "$ic_content" >"$content_file"
    awk -v ver="$ic_version" -v content_file="$content_file" '
    BEGIN { added=0 }
    /^# / && !added { print; print ""; print "## " ver; while ((getline line < content_file) > 0) print line; close(content_file); print ""; added=1; next }
    { print }
    END { if (!added) { print "## " ver; while ((getline line < content_file) > 0) print line; close(content_file); print "" } }
    ' "$ic_file" | awk 'NR==1{print} NR>1{if (!($0=="" && p=="")) print} {p=$0} END{if(p!="")print ""}' >"$ic_file.tmp"
    mv "$ic_file.tmp" "$ic_file"
    rm -f "$content_file"
}

# Always inserts a new section at the bottom, even if duplicate exists.
append_changelog_section() {
    ic_file="$1"
    ic_content="$2"
    ic_version="$3"
    content_file=$(mktemp)
    printf "%s\n" "$ic_content" >"$content_file"
    awk -v ver="$ic_version" -v content_file="$content_file" '
    { print }
    END { print ""; print "## " ver; while ((getline line < content_file) > 0) print line; close(content_file); print "" }
    ' "$ic_file" | awk 'NR==1{print} NR>1{if (!($0=="" && p=="")) print} {p=$0} END{if(p!="")print ""}' >"$ic_file.tmp"
    mv "$ic_file.tmp" "$ic_file"
    rm -f "$content_file"
}

# Update/prepend/append changelog section
update_changelog() {
    ic_file="$1"
    ic_content="$2"
    ic_section_name="$3"
    ic_mode="$4"
    ic_version="$ic_section_name"
    ic_esc_version=$(echo "$ic_version" | sed 's/[][\\/.*^$]/\\&/g')
    ic_pattern="^##[[:space:]]*\[?$ic_esc_version\]?"
    [ -f "$ic_file" ] || touch "$ic_file"
    content_file=$(mktemp)
    printf "%s\n" "$ic_content" >"$content_file"
    ic_content_block=$(cat "$content_file")
    rm -f "$content_file"
    case "$ic_mode" in
    auto | update)
        if update_changelog_section "$ic_file" "$ic_content_block" "$ic_version" "$ic_pattern"; then :; else prepend_changelog_section "$ic_file" "$ic_content_block" "$ic_version"; fi
        ;;
    prepend)
        prepend_changelog_section "$ic_file" "$ic_content_block" "$ic_version"
        ;;
    append)
        append_changelog_section "$ic_file" "$ic_content_block" "$ic_version"
        ;;
    *)
        printf 'Unknown mode: %s\n' "$ic_mode" >&2
        return 1
        ;;
    esac
    if ! tail -n 5 "$ic_file" | grep -q "Managed by changeish"; then
        printf '\n[Managed by changeish](https://github.com/itlackey/changeish)\n\n' >>"$ic_file"
    fi
    remove_duplicate_blank_lines "$ic_file"
}
