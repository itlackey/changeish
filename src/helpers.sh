# Show all available release tags
run_available_releases() {
    curl -s https://api.github.com/repos/itlackey/changeish/releases | jq -r '.[] | .tag_name'
    exit 0
}

# Extract version string from a line (preserving v if present)
parse_version() {
    # Accepts a string, returns version like v1.2.3 or 1.2.3
    out=$(echo "$1" | sed -n -E 's/.*([vV][0-9]+\.[0-9]+\.[0-9]+).*/\1/p')
    if [ -z "$out" ]; then
        out=$(echo "$1" | sed -n -E 's/.*([0-9]+\.[0-9]+\.[0-9]+).*/\1/p')
    fi
    printf '%s' "$out"
}

get_current_version_from_file() {
    file="$1"
    if [ ! -f "$file" ]; then
        echo ""
        return 0
    fi
    version_lines="$(grep -Ei -m1 'version[^0-9]*[0-9]+\.[0-9]+(\.[0-9]+)?' "$file")"
    version=$(parse_version "$version_lines")
    if [ -n "$version" ]; then
        echo "$version"
        return 0
    fi
    echo ""
}

# Get current version from version_file or fallback
get_current_version() {
    if [ -n "$version_file" ] && [ -f "$version_file" ]; then
        grep -Eom1 '[0-9]+\.[0-9]+\.[0-9]+' "$version_file" || echo "Unreleased"
    else
        echo "Unreleased"
    fi
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

generate_remote() {

    content=$(cat "$1")

    # Escape for JSON (replace backslash, double quote, and control characters)
    # Use json_escape to safely encode the prompt as a JSON string
    escaped_content=$(printf "%s" "${content}" | json_escape)
    body=$(printf '{"model":"%s","messages":[{"role":"user","content":%s}],"max_completion_tokens":8192}' \
        "${api_model}" "${escaped_content}")

    [ "${debug}" = "true" ] && printf 'Request body:\n%s\n' "${body}" >&2

    response=$(curl -s -X POST "${api_url}" \
        -H "Authorization: Bearer ${api_key}" \
        -H "Content-Type: application/json" \
        -d "${body}")

    if [ "${debug}" = "true" ]; then
        echo "Response from remote API:" >&2
        echo "${response}" >&2
    fi

    # Extract "content" value using grep/sed to allow line breaks and special characters
    result=$(echo "${response}" | sed -n 's/.*"content"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | sed 's/\\n/\n/g; s/\\"/"/g; s/\\\\/\\/g')
    echo "${result}"



    # body=$(printf '{"model":"%s","messages":[{"role":"user","content":"%s"}]}' \
    #     "${api_model}" "$(cat "$1" | json_escape)")
    # curl -s -X POST "${api_url}" -H 'Content-Type: application/json' -d "${body}" |
    #     sed -n 's/.*"content"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
    #     sed 's/\\n/\n/g; s/\\"/"/g'
}

run_local() {
    if [ "$debug" = true ]; then
        ollama run "${model}" --verbose <"$1"
    else
        ollama run "$model" <"$1"
    fi
}

generate_response() {
    case $model_provider in
    remote) generate_remote "$1" ;;
    none) cat "$1" ;;
    *) run_local "$1" ;;
    esac
}

# Extract TODO changes for history extraction
extract_todo_changes() {
    range=$1
    if [ "$range" = "--cached" ]; then
        td=$(git --no-pager diff --cached --unified=0 -b -w --no-prefix --color=never -- $todo_pattern || true)
    elif [ "$range" = "--current" ] || [ -z "$range" ]; then
        td=$(git --no-pager diff --unified=0 -b -w --no-prefix --color=never -- $todo_pattern || true)
    else
        td=$(git --no-pager diff $range --unified=0 -b -w --no-prefix --color=never -- $todo_pattern || true)
    fi
    printf '%s' "$td"
}

# Build git history markdown (with version info)
build_history() {
    hist=$1
    commit=$2

    [ "$debug" = true ] && printf 'Debug: Building history for commit %s\n' "$commit"

    : >"$hist"
    # Version detection logic
    found_version_file=""
    if [ -n "$version_file" ] && [ -f "$version_file" ]; then
        found_version_file="$version_file"
    else
        for vf in changes.sh package.json pyproject.toml setup.py Cargo.toml composer.json build.gradle pom.xml; do
            [ -f "$vf" ] && {
                found_version_file="$vf"
                break
            }
        done
    fi
    version_info=""
    version_diff=""
    if [ -n "$found_version_file" ]; then
        # Try to get version diff for this commit
        if [ "$commit" = "--cached" ]; then
            version_diff=$(git --no-pager diff --cached --minimal --no-prefix --unified=0 --no-color -b -w --compact-summary --color-moved=no -- "$found_version_file" | grep -Ei '^[+].*version' || true)
        elif [ "$commit" = "--current" ] || [ -z "$commit" ]; then
            version_diff=$(git --no-pager diff --minimal --no-prefix --unified=0 --no-color -b -w --compact-summary --color-moved=no -- "${found_version_file}" | grep -Ei '^[+].*version' || true)
        else
            version_diff=$(git --no-pager diff $commit^! --minimal --no-prefix --unified=0 --no-color -b -w --compact-summary --color-moved=no -- "$found_version_file" | grep -Ei '^[+].*version' || true)
        fi
        if [ -n "$version_diff" ]; then
            parsed_version=$(parse_version "$version_diff")
            version_info="**Version:** $parsed_version (updated)"
        else
            current_file_version=$(get_current_version_from_file "$found_version_file")
            if [ -n "$current_file_version" ]; then
                version_info="**Version:** $current_file_version (current)"
            fi
        fi
    fi

    [ "$debug" = true ] && printf 'Debug: Found version info: %s\n' "$version_diff"

    if [ -n "$version_info" ]; then
        printf '%s\n' "$version_info" >>"$hist"
    fi
    # Determine range for git diff
    git_args="--no-pager diff"
    if [ "$commit" = "--cached" ]; then
        git_args="$git_args --cached"
    elif [ "$commit" = "--current" ] || [ -z "$commit" ]; then
        : # working tree diff
    else
        git_args="$git_args $commit^!"
    fi
    git_args="$git_args --minimal --no-prefix --unified=0 --no-color -b -w --compact-summary --color-moved=no"
    if [ -n "$PATTERN" ]; then
        git_args="$git_args -- $PATTERN"
    fi

    [ "$debug" = true ] && printf 'Debug: Running git command: git %s\n' "$git_args"

    printf '```diff\n' >>"$hist"
    eval git "$git_args" >>"$hist"
    printf '\n```' >>"$hist"
    # Append TODO section
    td=$(extract_todo_changes "$commit")
    [ -n "$td" ] && printf '\n### TODO Changes\n```diff\n%s\n```\n' "$td" >>"$hist"

    [ "$debug" = true ] && printf 'Debug: History built successfully, output file: %s\n' "$hist"
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

generate_prompt_file() {
    out=$1
    tpl=$2
    header=$3
    hist=$4
    file_tpl="$template_dir/$tpl"
    if [ -f "$file_tpl" ]; then cp "$file_tpl" "$out"; else printf '%s\n' "$header" >"$out"; fi
    printf '\n<<<GIT HISTORY>>>\n%s\n<<<END>>>\n' "$(cat "$hist")" >>"$out"
}
