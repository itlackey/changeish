#!/bin/sh
# changeish - A script to generate a changelog from Git history, optionally using AI (Ollama or remote API)
# Version: 0.2.0
# Usage: changeish [OPTIONS]
#
# Options:
#   --help                  Show this help message and exit
#   --summary               Output a summary of the changes to the console.
#   --current               Use uncommitted (working tree) changes for git history (default)
#   --staged                Use staged (index) changes for git history
#   --all                   Include all history (from first commit to HEAD)
#   --from REV              Set the starting commit (default: HEAD)
#   --to REV                Set the ending commit (default: HEAD^)
#   --include-pattern P     Show diffs for files matching pattern P (and exclude them from full diff)
#   --exclude-pattern P     Exclude files matching pattern P from full diff
#   --todo-pattern P        Pattern for files to check for TODO changes (default: *todo*)
#   --model MODEL           Specify the local Ollama model to use (default: qwen2.5-coder)
#   --model-provider MODE  Control how changelog is generated: auto (default), local, remote, none
#   --api-model MODEL       Specify remote API model (overrides --model for remote usage)
#   --api-url URL           Specify remote API endpoint URL for changelog generation
#   --changelog-file PATH   Path to changelog file to update (default: ./CHANGELOG.md)
#   --prompt-template PATH  Path to prompt template file (default: ./changelog_prompt.md)
#   --update-mode MODE      Section update mode: auto (default), prepend, append, update, none (disables writing changelog)
#   --section-name NAME     Target section name (default: detected version or "Current Changes")
#   --version-file PATH     File to check for version number changes in each commit
#   --config-file PATH      Path to a shell config file to source before running (overrides .env)
#   --save-prompt           Generate prompt file only and do not produce changelog
#   --save-history          Do not delete the intermediate git history file
#   --make-prompt-template  Write the default prompt template to a file
#   --version               Show script version and exit
#   --available-releases    Show available script releases and exit
#   --update                Update this script to the latest version and exit
#   --debug                 Enable debug output
#
# Example:
#   # Update changelog with uncommitted changes using local model:
#   changeish
#   # Update changelog with staged changes only:
#   changeish --staged
#   # Generate changelog from specific commit range using local model:
#   changeish --from v1.0.0 --to HEAD --model llama3 --version-file custom_version.txt
#   # Include all history since start and write to custom changelog file:
#   changeish --all --changelog-file ./docs/CHANGELOG.md
#   # Use a remote API for generation:
#   changeish --model-provider remote --api-model gpt-4 --api-url https://api.example.com/v1/chat/completions
#   # Only generate the prompt file:
#   changeish --save-prompt
#   # Use a custom config file:
#   changeish --config-file ./myconfig.env
#   # Write the default prompt template to a file:
#   changeish --make-prompt-template my_prompt_template.md
#
# Environment variables:
#   CHANGEISH_MODEL       Default model to use for local generation (overridden by --model)
#   CHANGEISH_API_KEY     API key for remote generation (required if --remote is used)
#   CHANGEISH_API_URL     Default API URL for remote generation (overridden by --api-url)
#   CHANGEISH_API_MODEL   Default API model for remote generation (overridden by --api-model)
#
# END_HELP
# Notes:
# https://keepachangelog.com/en/1.1.0/
# https://thomasventurini.com/articles/the-best-way-to-work-with-todos-in-vscode/
set -e
IFS=' 
'

SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "${SCRIPT_PATH}")"
PROMPT_DIR="${SCRIPT_DIR}/prompts"

changelog_prompt_template=$(cat "${PROMPT_DIR}/changelog_prompt.md")

# Initialize default option values
debug="false"
from_rev=""
to_rev=""
include_pattern=""
exclude_pattern=""
todo_pattern="*todo*"
changelog_file="./CHANGELOG.md"
prompt_template="./changelog_prompt.md"
save_prompt="false"
save_history="false"
version_file=""
all_history="false"
current_changes="false"
staged_changes="false"
history_file="history.md"
remote="false"
default_todo_grep_pattern="TODO|FIX|ENHANCEMENT|DONE|CHORE|ADD|BUG"
model_provider="auto"
update_mode="auto"
section_name="auto"
summary="false"
message="false"

# Define default prompt template (multi-line string) for AI generation
default_prompt=$(
    cat <<'END_PROMPT'
[INSTRUCTIONS]
Task: Generate a changelog from the Git history that follows the structure below. 
Be sure to use only the information from the Git history in your response. 
Output rules
1. Use only information from the Git history provided in the prompt.
2. Output **ONLY** valid Markdown based on the format provided in these instructions.
    - Do not include the \`\`\` code block markers in your output.
3. Use this exact hierarchy defined in the keepachangelog standard:
   ### Added

   - ...

   ### Fixed

   - ...

   ### Changed

   - ...

   ### Removed

   - ...

   ### Security

   - ...

4. Omit any section that would be empty and do not include a ## header.
END_PROMPT
)

example_changelog=$(
    cat <<'END_EXAMPLE'
[Example Output (for reference only)]

### Added

- Example feature A

[END]
END_EXAMPLE
)

# Prompt for summarizing a single git diff
commit_message_prompt=$(
    cat <<'EOF'
Task: Provide a concise, commit message for the changes described in the following git diff.
Output only the commit message.
EOF
)
summary_prompt=$(
    cat <<'EOF'
Task: Provide a concise, human-readable summary (2-3 sentences) of the changes described in the following git diff.
Output only the summary text.
EOF
)
# Common files to check for version changes if --version-file not specified
default_version_files="changes.sh package.json pyproject.toml setup.py Cargo.toml composer.json build.gradle pom.xml"

# Update the script to latest release
update() {
    latest_version=$(curl -s https://api.github.com/repos/itlackey/changeish/releases/latest | jq -r '.tag_name')
    printf 'Updating changeish to version %s...\n' "${latest_version}"
    curl -fsSL https://raw.githubusercontent.com/itlackey/changeish/main/install.sh | sh
    printf 'Update complete.\n'
    exit 0
}

# Print script version
show_version() {
    awk 'NR==3{sub(/^# Version: /, ""); print; exit}' "$0"
    exit 0
}

# Print usage information
show_help() {
    printf 'Version: %s\n' "$(awk 'NR==3{sub(/^# Version: /, ""); print; exit}' "$0" || true)"
    awk '/^# END_HELP/ {exit} NR>2 && /^#/{sub(/^# ?/, ""); print}' "$0" | sed -e '/^Usage:/,$!d'
    printf 'Default version files to check for version changes:\n'
    for file in ${default_version_files}; do
        printf '  %s\n' "${file}"
    done
    exit 0
}

# Show all available release tags
show_available_releases() {
    curl -s https://api.github.com/repos/itlackey/changeish/releases | jq -r '.[].tag_name'
    exit 0
}

# 5. OS and WSL detection
get_app_dir() {
    OS_NAME=$(uname -s)
    case "${OS_NAME}" in
    Linux*)
        if [ -f /etc/wsl.conf ] || grep -qi microsoft /proc/version 2>/dev/null; then
            PLATFORM=windows
        else
            PLATFORM=linux
        fi
        ;;
    Darwin*) PLATFORM=macos ;;
    CYGWIN* | MINGW* | MSYS*) PLATFORM=windows ;;
    *)
        printf 'Error: Unsupported OS: %s\n' "${OS_NAME}" >&2
        exit 1
        ;;
    esac

    case "${PLATFORM}" in
    linux)
        printf '%s/changeish' "${XDG_DATA_HOME:-"${HOME}/.local/share"}"
        ;;
    windows)
        printf '%s/changeish' "${LOCALAPPDATA:-"${HOME:-USERPROFILE}/AppData/Local"}"
        ;;
    macos)
        printf '%s/Library/Application Scripts/com.example.changeish' "${HOME}"
        ;;
    *)
        printf 'Error: Unsupported platform: %s\n' "${PLATFORM}" >&2
        exit 1
        ;;
    esac
}

# -------------------------------------------------------------------
# New helper: build a single history “entry” (commit, staged or current)
# Globals:
#   history_file            - path to Markdown history file
#   found_version_file - path to version file, if any
#   include_pattern    - pattern for “include” diffs
#   exclude_pattern    - pattern for excluding files from full diff
# Arguments:
#   $1: label to display (hash or “Staged Changes” / “Working Tree”)
#   $2: version string (if available, otherwise empty)
#   $3: git diff range (e.g. "<hash>^!" or "--cached" or empty for worktree)
build_entry() {
    label="$1"
    be_version="$2"
    diff_spec="$3"
    include_arg=""
    exclude_arg=""
    # Debug output to stderr only
    [ "${debug:-false}" = "true" ] && printf 'Building entry for: %s\n' "${label}" >&2
    [ "${debug:-false}" = "true" ] && printf 'Diff spec: %s\n' "${diff_spec}" >&2
    [ "${debug:-false}" = "true" ] && printf 'be_version: %s\n' "${be_version}" >&2
    printf '## %s\n' "${label}" >>"${history_file}"
    # version‐file diff
    if [ -n "${found_version_file}" ] && [ -f "${found_version_file}" ]; then
        tmpver=$(mktemp)
        trap 'rm -f "${tmpver}"' EXIT
        version_diff=""
        if [ -n "${diff_spec}" ]; then
            version_diff=$(git --no-pager diff "${diff_spec}" \
                --minimal --no-prefix --unified=0 --no-color -b -w \
                --compact-summary --color-moved=no -- "${found_version_file}" |
                grep -Ei '^[+].*version' || true)
        else
            version_diff=$(git --no-pager diff --minimal --no-prefix --unified=0 \
                --no-color -b -w --compact-summary --color-moved=no -- "${found_version_file}" |
                grep -Ei '^[+].*version' || true)
        fi
        if [ -n "${version_diff}" ]; then
            parsed_version=$(parse_version "${version_diff}")
            printf '\n**Version:** %s (updated)\n' "${parsed_version}" >>"${history_file}"
        else
            # Fallback: parse current version from file if available
            current_file_version=$(get_current_version_from_file "${found_version_file}")
            if [ -n "${current_file_version}" ]; then
                printf '\n**Version:** %s (current)\n' "${current_file_version}" >>"${history_file}"
            else
                printf '\n**Version:** %s (arg)\n' "${be_version}" >>"${history_file}"
            fi
        fi
        rm -f "${tmpver}"
        trap - EXIT
    fi
    if [ -n "${diff_spec}" ] && [ "${diff_spec}" != "--cached" ]; then
        commit_hash=$(echo "${diff_spec}" | sed 's/\^!$//')
        {
            printf '**Commit:** %s\n' "${commit_hash}"
            printf '**Date:**   %s\n' "$(git show -s --format=%ci "${commit_hash}" 2>/dev/null || true)"
            printf '**Message:**\n'
            git show -s --format=%B "${commit_hash}"
            printf '\n'
        } >>"${history_file}"
    fi
    [ "${debug:-false}" = "true" ] && git --no-pager diff --unified=0 -- "*todo*" >&2
    if [ -n "${todo_pattern}" ]; then
        if [ -n "${diff_spec}" ]; then
            todo_diff=$(git --no-pager diff "${diff_spec}" --unified=0 -b -w --no-prefix --color=never -- "${todo_pattern}")
        else
            todo_diff=$(git --no-pager diff --unified=0 -b -w --no-prefix --color=never -- "${todo_pattern}")
        fi
        if [ -n "${todo_diff}" ]; then
            {
                printf '\n### Changes in TODOs\n'
                printf '```diff\n'
                printf '%s\n' "${todo_diff}"
                printf '```\n'
            } >>"${history_file}"
        fi
    fi
    # Validate include/exclude patterns
    if [ -n "${include_pattern}" ]; then
        if ! git ls-files -- "*${include_pattern}*" >/dev/null 2>&1; then
            printf 'Error: Invalid --include-pattern %s (no matching files or invalid pattern).\n' "${include_pattern}" >&2
            exit 1
        fi
        include_arg="*${include_pattern}*"
    fi
    if [ -n "${exclude_pattern}" ]; then
        if ! git ls-files -- ":(exclude)*${exclude_pattern}*" >/dev/null 2>&1; then
            printf 'Error: Invalid --exclude-pattern %s (no matching files or invalid pattern).\n' "${exclude_pattern}" >&2
            exit 1
        fi
        exclude_arg=":(exclude)*${exclude_pattern}*"
    fi
    [ "${debug:-false}" = "true" ] && printf 'Set include/exclude args: %s %s\n' \
        "${include_arg}" "${exclude_arg}" >&2
    {
        printf '\n### Changes in files\n'
        printf '```diff\n'
        run_git_diff "${diff_spec}" "${include_arg}" "${exclude_arg}"
        printf '```\n\n'
    } >>"${history_file}"
    if [ "${debug:-false}" = "true" ]; then
        printf 'History output:\n' >&2
        cat "${history_file}" >&2
    fi
}

# Helper to run git diff with standard options, supporting include/exclude args
run_git_diff() {
    diff_spec="$1"
    include_arg="$2"
    exclude_arg="$3"

    git_args="--minimal --no-prefix --unified=0 --no-color -b -w --compact-summary --color-moved=no"
    # Prepare file pattern arguments array
    set --
    if [ -n "${include_arg}" ]; then
        set -- "$@" "${include_arg}"
    fi
    if [ -n "${exclude_arg}" ]; then
        set -- "$@" "${exclude_arg}"
    fi

    # Build the git diff command
    if [ -n "${diff_spec}" ]; then
        if [ $# -gt 0 ]; then
            # shellcheck disable=SC2086
            git --no-pager diff "${diff_spec}" ${git_args} -- "$@"
        else
            # shellcheck disable=SC2086
            git --no-pager diff "${diff_spec}" ${git_args}
        fi
    else
        if [ $# -gt 0 ]; then
            # shellcheck disable=SC2086
            git --no-pager diff ${git_args} -- "$@"
        else
            # shellcheck disable=SC2086
            git --no-pager diff ${git_args}
        fi
    fi
}

# Generate the prompt file by combining the prompt template and git history
# Globals:
#   default_prompt (the built-in prompt template text)
#   prompt_file (output path for prompt file)
# Arguments:
#   $1: Path to git history markdown file
#   $2: Path to custom prompt template file (optional)
generate_changelog_prompt() {
    gp_history_file="$1"
    gp_template_file="$2"
    gp_existing_section="$3"
    if [ -n "${gp_template_file}" ] && [ -f "${gp_template_file}" ]; then
        printf 'Generating prompt file from template: %s\n' "${gp_template_file}"
        cp "${gp_template_file}" "${prompt_file}"
    else
        printf '%s' "${default_prompt}" >"${prompt_file}"
    fi

    if [ -n "${gp_existing_section}" ]; then
        {
            printf '\n5. Include ALL of the existing items from the "EXISTING CHANGELOG" in your response. DO NOT remove any existing items.\n'
            printf '[END]\n[EXISTING CHANGELOG]\n'
            printf '%s\n' "${gp_existing_section}"
            printf '[END]\n'
        } >>"${prompt_file}"
    else
        printf '\n[END]\n%s' "${example_changelog}" >>"${prompt_file}"
    fi
    {
        printf '\n<<<GIT HISTORY>>>\n'
        cat "${gp_history_file}"
        printf '\n<<<END>>>\n'
    } >>"${prompt_file}"

}

# Run the local Ollama model with the prompt file
# Arguments:
#   $1: Model name
#   $2: Prompt file path
run_ollama() {
    o_model="$1"
    o_prompt_file_path="$2"
    if [ "${debug}" = "true" ]; then
        ollama run "${o_model}" --verbose <"${o_prompt_file_path}"
    else
        ollama run "${o_model}" <"${o_prompt_file_path}"
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
    remote_model="$1"
    prompt_path="$2"
    # Read the prompt file as plain text
    content=$(cat "${prompt_path}")

    # Escape for JSON (replace backslash, double quote, and control characters)
    # Use json_escape to safely encode the prompt as a JSON string
    escaped_content=$(printf "%s" "${content}" | json_escape)
    body=$(printf '{"model":"%s","messages":[{"role":"user","content":%s}],"max_completion_tokens":8192}' \
        "${remote_model}" "${escaped_content}")

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
}

generate_response() {
    gr_prompt_file="$1"

    if [ "${remote}" = "true" ]; then
        [ "${debug}" = "true" ] && printf 'Generating changelog using model: %s\n' "${api_model}" >&2
        response=$(generate_remote "${api_model}" "${gr_prompt_file}")
    else
        if command -v ollama >/dev/null 2>&1; then
            [ "${debug}" = "true" ] && printf 'Generating changelog using model: %s\n' "${model}" >&2
            response=$(run_ollama "${model}" "${gr_prompt_file}")
        else
            printf 'ollama not found, skipping changelog generation.\n' >&2
            exit 0
        fi
    fi
    printf '%s' "${response}"
}

# Summarize one diff via the configured LLM
# $1 = raw diff text
summarize_diff() {
    diff_text="$1"
    temp_prompt_file=$(mktemp)

    {
        printf '%s\n\n<<DIFF>>\n' "${summary_prompt}"
        printf '%s\n' "${diff_text}"
        printf '<<DIFF>>\n'
    } >"${temp_prompt_file}"

    generate_response "${temp_prompt_file}"

    rm -f "${temp_prompt_file}"
}

# Summarize one diff via the configured LLM
# $1 = raw diff text
generate_commit_message_for_diff() {
    diff_text="$1"
    temp_prompt_file=$(mktemp)

    {
        printf '%s\n\n<<DIFF>>\n' "${commit_message_prompt}"
        printf '%s\n' "${diff_text}"
        printf '<<DIFF>>\n'
    } >"${temp_prompt_file}"

    generate_response "${temp_prompt_file}"

    rm -f "${temp_prompt_file}"
}

generate_changelog() {
    cg_model="$1"
    cg_file="$2"
    cg_section="$3"
    cg_mode="$4"
    cg_existing="$5"
    changelog_response=$(generate_response "${prompt_file}")
    if [ "${debug}" = "true" ]; then
        echo ""
        echo "## Changelog (generated by changeish using ${cg_model})"
        echo '```'
        printf '%s\n' "${changelog_response}"
        echo '```'
    fi
    update_changelog "${cg_file}" "${changelog_response}" "${cg_section}" "${cg_mode}" "${cg_existing}"
    printf 'Changelog updated in %s\n' "${cg_file}"
}

# Helper: ensure blank line before/after header, but not multiple blank lines
ensure_blank_lines() {
    awk '
        function is_header(line) { return line ~ /^## / || line ~ /^# / }
        {
            if (is_header($0)) {
                if (NR > 1 && prev != "") print "";
                print $0;
                getline nextline;
                if (nextline != "") print "";
                print nextline;
                prev = nextline;
                next;
            }
            print $0;
            prev = $0;
        }
        END { if (prev != "") print "" }
    '
}

# Remove duplicate blank lines and ensure file ends with newline
remove_duplicate_blank_lines() {
    # $1: file path
    awk 'NR==1{print} NR>1{if (!($0=="" && p=="")) print} {p=$0} END{if(p!="")print ""}' "$1" >"$1.tmp" && mv "$1.tmp" "$1"
}

# Updates a specific section in a changelog file, or adds it if not present.
# Arguments:
#   $1 - Path to the changelog file.
#   $2 - Content to insert into the changelog section.
#   $3 - Version string to use as the section header.
#   $4 - Regex pattern to identify the section to replace.
#
# If a section matching the given pattern exists, it is replaced with the new content.
# Otherwise, the new section is inserted after the first H1 header, or appended to the end if no H1 exists.
#
# To avoid awk errors with multiline content, use a temp file for content and read with getline.

update_changelog_section() {
    ic_file="$1"
    ic_content="$2"
    ic_version="$3"
    ic_pattern="$4"
    content_file=$(mktemp)
    printf "%s\n" "${ic_content}" >"${content_file}"
    if grep -qE "${ic_pattern}" "${ic_file}"; then
        awk -v pat="${ic_pattern}" -v ver="${ic_version}" -v content_file="${content_file}" '
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
            ' "${ic_file}" | ensure_blank_lines >"${ic_file}.tmp"
        mv "${ic_file}.tmp" "${ic_file}"
        rm -f "${content_file}"
        return 0
    else
        rm -f "${content_file}"
        return 1
    fi
}

# prepend_changelog_section: Always inserts a new section at the top (after H1), even if duplicate exists.
prepend_changelog_section() {
    ic_file="$1"
    ic_content="$2"
    ic_version="$3"
    content_file=$(mktemp)
    printf "%s\n" "${ic_content}" >"${content_file}"
    awk -v ver="${ic_version}" -v content_file="${content_file}" '
        BEGIN { added=0 }
        /^# / && !added { print; print ""; print "## " ver; while ((getline line < content_file) > 0) print line; close(content_file); print ""; added=1; next }
        { print }
        END { if (!added) { print "## " ver; while ((getline line < content_file) > 0) print line; close(content_file); print "" } }
        ' "${ic_file}" | ensure_blank_lines >"${ic_file}.tmp"
    mv "${ic_file}.tmp" "${ic_file}"
    rm -f "${content_file}"
}

# append_changelog_section: Always inserts a new section at the bottom, even if duplicate exists.
append_changelog_section() {
    ic_file="$1"
    ic_content="$2"
    ic_version="$3"
    content_file=$(mktemp)
    printf "%s\n" "${ic_content}" >"${content_file}"
    awk -v ver="${ic_version}" -v content_file="${content_file}" '
        { print }
        END { print ""; print "## " ver; while ((getline line < content_file) > 0) print line; close(content_file); print "" }
        ' "${ic_file}" | ensure_blank_lines >"${ic_file}.tmp"
    mv "${ic_file}.tmp" "${ic_file}"
    rm -f "${content_file}"
}

update_changelog() {
    ic_file="$1"
    ic_content="$2"
    ic_section_name="$3"
    ic_mode="$4"
    ic_version="${ic_section_name}"
    ic_esc_version=$(echo "${ic_version}" | sed 's/[][\\/.*^$]/\\&/g')
    ic_pattern="^##[[:space:]]*\[?${ic_esc_version}\]?"

    [ -f "${ic_file}" ] || touch "${ic_file}"

    # POSIX-compatible: preserve newlines in content using a temp file
    content_file=$(mktemp)
    printf "%s\n" "${ic_content}" >"${content_file}"
    ic_content_block=$(cat "${content_file}")
    rm -f "${content_file}"

    # Update mode behavior:
    #   'auto'   - Update the section if it exists, otherwise prepend it (default, same as 'update').
    #   'update' - Update the section if it exists, otherwise prepend it (currently identical to 'auto').
    #   'prepend'- Always insert a new section at the top (after H1), even if a duplicate exists.
    #   'append' - Always insert a new section at the bottom, even if a duplicate exists.
    case "${ic_mode}" in
    auto | update)
        if update_changelog_section "${ic_file}" "${ic_content_block}" "${ic_version}" "${ic_pattern}"; then
            :
        else
            prepend_changelog_section "${ic_file}" "${ic_content_block}" "${ic_version}"
        fi
        ;;
    prepend)
        prepend_changelog_section "${ic_file}" "${ic_content_block}" "${ic_version}"
        ;;
    append)
        append_changelog_section "${ic_file}" "${ic_content_block}" "${ic_version}"
        ;;
    *)
        printf 'Unknown mode: %s\n' "${ic_mode}" >&2
        return 1
        ;;
    esac

    if ! tail -n 5 "${ic_file}" | grep -q "Managed by changeish"; then
        printf '\n[Managed by changeish](https://github.com/itlackey/changeish)\n\n' >>"${ic_file}"
    fi
    remove_duplicate_blank_lines "${ic_file}"
}

parse_version() {
    # Extracts version numbers like v1.2.3, 1.2.3, or "1.2.3" from a string argument, preserving the v if present
    output=$(echo "$1" | sed -n -E 's/.*([vV][0-9]+\.[0-9]+\.[0-9]+).*/\1/p')

    if [ -z "${output}" ]; then
        output=$(echo "$1" | sed -n -E 's/.*([0-9]+\.[0-9]+\.[0-9]+).*/\1/p')
    fi

    echo "${output}"
}

get_current_version_from_file() {
    file="$1"
    if [ ! -f "${file}" ]; then
        echo ""
        return 0
    fi

    version_lines="$(grep -Ei -m1 'version[^0-9]*[0-9]+\.[0-9]+(\.[0-9]+)?' "${file}")"
    version=$(parse_version "${version_lines}")
    if [ -n "${version}" ]; then
        echo "${version}"
        return 0
    fi

    echo ""
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

main() {
    # POSIX-compliant error trap: print error message, line number, and exit code
    # on_exit() {
    #     status=$?
    #     if [ $status -ne 0 ]; then
    #         echo "Error: Command failed at line $LAST_EVAL_LINE (exit code $status)" >&2
    #     fi
    # }
    # # Save the line number before each command
    # trap 'LAST_EVAL_LINE=$LINENO' DEBUG
    # trap on_exit EXIT

    # POSIX-compliant error trap: print error message, line number, and exit
    # on_error() {
    #     echo "Error: Command failed at line $LINENO (exit code $1)" >&2
    # }
    # Use trap to capture the exit code and line number before exiting

    # if [ "$(basename -- "$0")" = "changes.sh" ]; then
    #     set -eu
    # fi

    config_file=""
    model="qwen2.5-coder"
    model_set="false"

    while [ $# -gt 0 ]; do
        case "$1" in
        --from)
            from_rev="$2"
            shift 2
            ;;
        --to)
            to_rev="$2"
            shift 2
            ;;
        --include-pattern)
            include_pattern="$2"
            shift 2
            ;;
        --exclude-pattern)
            exclude_pattern="$2"
            shift 2
            ;;
        --todo-pattern)
            todo_pattern="$2"
            shift 2
            ;;
        --model)
            model="$2"
            model_set="true"
            shift 2
            ;;
        --api-model)
            api_model="$2"
            shift 2
            ;;
        --api-url)
            api_url="$2"
            shift 2
            ;;
        --config-file)
            config_file="$2"
            shift 2
            ;;
        --changelog-file)
            changelog_file="$2"
            shift 2
            ;;
        --prompt-template)
            prompt_template="$2"
            shift 2
            ;;
        --save-prompt)
            save_prompt="true"
            shift
            ;;
        --save-history)
            save_history="true"
            shift
            ;;
        --version-file)
            version_file="$2"
            shift 2
            ;;
        --current)
            current_changes="true"
            shift
            ;;
        --staged)
            staged_changes="true"
            shift
            ;;
        --all)
            all_history="true"
            shift
            ;;
        --summary)
            summary="true"
            shift
            ;;
        --message)
            message="true"
            shift
            ;;
        --debug)
            debug="true"
            shift
            ;;
        --update)
            update
            ;;
        --available-releases)
            show_available_releases
            ;;
        --help)
            show_help
            ;;
        --version)
            show_version
            ;;
        --model-provider)
            model_provider="$2"
            shift 2
            ;;
        --make-prompt-template)
            make_prompt_template_path="$2"
            shift 2
            ;;
        --update-mode)
            update_mode="$2"
            shift 2
            ;;
        --section-name)
            section_name="$2"
            shift 2
            ;;
        *)
            printf 'Unknown arg: %s\n' "$1" >&2
            exit 1
            ;;
        esac
    done

    if [ -n "${make_prompt_template_path-}" ]; then
        printf '%s\n' "${default_prompt}" >"${make_prompt_template_path}"
        printf 'Default prompt template written to %s.\n' "${make_prompt_template_path}"
        exit 0
    fi
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        printf 'Error: Not a git repository. Please run this script inside a git repository.\n' >&2
        exit 1
    fi
    if ! git rev-parse HEAD >/dev/null 2>&1; then
        printf 'No commits found in repository. Nothing to show.\n' >&2
        exit 1
    fi

    if [ "${save_history}" = "true" ]; then
        history_file="history.md"
    else
        history_file=$(mktemp)
    fi
    if [ "${save_prompt}" = "true" ]; then
        prompt_file="prompt.md"
    else
        prompt_file=$(mktemp)
    fi

    if [ -n "${config_file}" ]; then
        if [ -f "${config_file}" ]; then
            [ "${debug}" = "true" ] && printf 'Loading config file: %s\n' "${config_file}" >&2
            # shellcheck disable=SC1090
            . "${config_file}"
        else
            printf 'Error: config file "%s" not found.\n' "${config_file}" >&2
            exit 1
        fi
    elif [ -f .env ]; then
        [ "${debug}" = "true" ] && printf 'Loading config file: %s/.env\n' "${PWD}" >&2
        # shellcheck disable=SC1091
        . "${PWD}/.env"
    fi

    if [ "${model_set}" = "false" ] && [ -n "${CHANGEISH_MODEL+x}" ] && [ -n "${CHANGEISH_MODEL}" ]; then
        model="${CHANGEISH_MODEL}"
    fi

    api_key="${CHANGEISH_API_KEY:-}"
    api_url="${api_url:-${CHANGEISH_API_URL:-}}"
    api_model="${api_model:-${CHANGEISH_API_MODEL:-}}"

    if [ "${staged_changes}" = "false" ] && [ "${all_history}" = "false" ] && [ -z "${to_rev}" ] && [ -z "${from_rev}" ]; then
        current_changes="true"
    else
        current_changes="false"
    fi

    should_generate_changelog="true"
    case "${model_provider}" in
    none)
        should_generate_changelog="false"
        ;;
    local)
        remote="false"
        ;;
    remote | api)
        remote="true"
        ;;
    auto)
        [ "${debug}" = "true" ] && printf 'Generation mode auto...\n' >&2
        if ! command -v ollama >/dev/null 2>&1; then
            if [ "${debug}" = "true" ]; then
                printf 'ollama not found, falling back to remote API.\n'
            fi
            remote="true"
            if [ -z "${api_key}" ]; then
                printf 'Warning: Falling back to remote but CHANGEISH_API_KEY is not set.\n' >&2
                remote="false"
                should_generate_changelog="false"
                printf 'Warning: Changelog generation disabled because CHANGEISH_API_KEY is not set.\n' >&2
            fi
            if [ -z "${api_url}" ]; then
                printf 'Warning: Changelog generation disabled because no API URL provided (use --api-url or CHANGEISH_API_URL).\n' >&2
                remote="false"
                should_generate_changelog="false"
            fi
        elif ! ollama list >/dev/null 2>&1; then
            if [ "${debug}" = "true" ]; then
                printf 'ollama daemon not running, falling back to remote API.\n'
            fi
            remote="true"
            if [ -z "${api_key}" ]; then
                printf 'Warning: Falling back to remote but CHANGEISH_API_KEY is not set.\n' >&2
                remote="false"
                should_generate_changelog="false"
                printf 'Warning: Changelog generation disabled because CHANGEISH_API_KEY is not set.\n' >&2
            fi
            if [ -z "${api_url}" ]; then
                printf 'Warning: Changelog generation disabled because no API URL provided (use --api-url or CHANGEISH_API_URL).\n' >&2
                remote="false"
                should_generate_changelog="false"
            fi
        fi
        ;;
    *)
        printf 'Unknown --model-provider: %s\n' "${model_provider}" >&2
        exit 1
        ;;
    esac

    if [ "${remote}" = "true" ]; then
        if [ -z "${api_model}" ]; then
            api_model="${model}"
        fi
        missing_api=""
        if [ -z "${api_key}" ]; then
            missing_api="CHANGEISH_API_KEY"
        fi
        if [ -z "${api_url}" ]; then
            if [ -n "${missing_api}" ]; then
                missing_api="${missing_api} and API URL"
            else
                missing_api="API URL"
            fi
        fi
        if [ -n "${missing_api}" ]; then
            printf 'Error: --remote specified but %s is not set (use --api-url or CHANGEISH_API_URL for the URL).\n' "${missing_api}" >&2
            exit 1
        fi
    fi

    if [ "${update_mode}" = "none" ]; then
        should_generate_changelog="false"
    fi

    if [ "${should_generate_changelog}" = "true" ]; then
        case "${update_mode}" in
        auto | prepend | append | update | none) ;;
        *)
            printf 'Error: --update-mode must be one of none, auto, prepend, append, update.\n' >&2
            exit 1
            ;;
        esac
    fi

    found_version_file=""
    if [ -n "${version_file}" ]; then
        if [ -f "${version_file}" ]; then
            found_version_file="${version_file}"
        else
            printf 'Error: Specified version file "%s" does not exist.\n' "${version_file}" >&2
            exit 1
        fi
    else
        [ "${debug:-false}" = "true" ] && printf 'Default version files: %s\n' "${default_version_files}" >&2
        for vf in ${default_version_files}; do
            [ "${debug:-false}" = "true" ] && printf 'Checking for version file: %s\n' "${vf}" >&2
            if [ -f "${vf}" ]; then
                found_version_file="${vf}"
                [ "${debug:-false}" = "true" ] && printf 'Found version file: %s\n' "${found_version_file}" >&2
                break
            fi
        done
        [ "${debug:-false}" = "true" ] && printf 'Final found_version_file: %s\n' "${found_version_file}" >&2
    fi

    if [ -z "${section_name}" ] || [ "${section_name}" = "auto" ]; then
        if [ -n "${found_version_file}" ]; then
            current_version=$(get_current_version_from_file "${found_version_file}")
            if [ "${debug}" = "true" ]; then
                printf 'Found version file: %s\n' "${found_version_file}"
                printf 'Current version: %s\n' "${current_version}"
            fi
            if [ -n "${current_version}" ]; then
                section_name="${current_version}"
            else
                section_name="[Unreleased]"
            fi
        else
            section_name="[Unreleased]"
        fi
    fi

    existing_changelog_section=$(extract_changelog_section "${section_name}" "${changelog_file}")

    if [ "${debug}" = "true" ]; then
        printf "## Settings\n"
        printf "Debug mode enabled.\n"
        printf "Prompt directory: %s\n" "${PROMPT_DIR}"
        printf "Using model: %s\n" "${model}"
        printf "Remote mode: %s\n" "${remote}"
        printf "API URL: %s\n" "${api_url}"
        printf "API Model: %s\n" "${api_model}"
        printf "Model provider: %s\n" "${model_provider}"
        printf "Should generate changelog: %s\n" "${should_generate_changelog}"
        printf "Changelog file: %s\n" "${changelog_file}"
        printf 'Using section name: %s\n' "${section_name}"
        printf "Prompt template: %s\n" "${prompt_template}"
        printf "Version file: %s\n" "${found_version_file}"
        printf "Current Version: %s\n" "${current_version}"
        printf "All history: %s\n" "${all_history}"
        printf "Current changes: %s\n" "${current_changes}"
        printf "Staged changes: %s\n" "${staged_changes}"
        printf "Save prompt: %s\n" "${save_prompt}"
        printf "Save history: %s\n" "${save_history}"
        printf "Include pattern: %s\n" "${include_pattern}"
        printf "Exclude pattern: %s\n" "${exclude_pattern}"
        printf "TODO pattern: %s\n" "${todo_pattern}"
        printf "TODO grep pattern: %s\n" "${default_todo_grep_pattern}"
        printf "## End Settings\n"
    fi

    if [ "${current_changes}" = "true" ]; then
        build_entry "Working Tree" "${current_version}" ""
        if [ "${summary}" = "true" ]; then
            summary_response=$(summarize_diff "$(cat "${history_file}" || true)")
            printf '%s\n' "${summary_response}"
        fi
        if [ "${message}" = "true" ]; then
            message_response=$(generate_commit_message_for_diff "$(cat "${history_file}" || true)")
            printf '%s\n' "${message_response}"
        fi
        [ "${debug}" = "true" ] && printf 'Generated git history for uncommitted changes in %s.\n' "${history_file}"
    elif [ "${staged_changes}" = "true" ]; then
        build_entry "Staged Changes" "${current_version}" "--cached"
        [ "${debug}" = "true" ] && printf 'Generated git history for staged changes in %s.\n' "${history_file}"
        if [ "${summary}" = "true" ]; then
            summary_response=$(summarize_diff "$(cat "${history_file}" || true)")
            printf '%s\n' "${summary_response}"
        fi
        if [ "${message}" = "true" ]; then
            message_response=$(generate_commit_message_for_diff "$(cat "${history_file}" || true)")
            printf '%s\n' "${message_response}"
        fi
    else
        if [ -z "${to_rev}" ]; then to_rev="HEAD"; fi
        if [ -z "${from_rev}" ]; then from_rev="HEAD"; fi
        if [ "${all_history}" = "true" ]; then
            [ "${debug}" = "true" ] && printf 'Using commit range: --all (all history)\n'
            commits_list=$(git rev-list --all)
        else
            range_spec="${to_rev}^..${from_rev}"
            [ "${debug}" = "true" ] && printf 'Using commit range: %s\n' "${range_spec}"
            commits_list=$(git rev-list --reverse "${range_spec}")
        fi
        if [ -z "${commits_list}" ]; then
            printf 'No commits found in range %s\n' "${range_spec}" >&2
            exit 1
        fi
        if [ "${debug}" = "true" ]; then
            printf 'Commits list:\n'
            printf '%s\n' "${commits_list}"
        fi

        [ "${debug}" = "true" ] && git --no-pager log

        start_commit=$(echo "${commits_list}" | head -1)
        end_commit=$(echo "${commits_list}" | tail -1)
        start_date=$(git show -s --format=%ci "${start_commit}")
        end_date=$(git show -s --format=%ci "${end_commit}")
        total_commits=$(echo "${commits_list}" | wc -l | tr -d '[:space:]')
        branch_name=$(git rev-parse --abbrev-ref HEAD)
        [ "${debug}" = "true" ] && printf "Generating git history for %s commits from %s (%s) to %s (%s) on branch %s...\n" \
            "${total_commits}" "${start_commit}" "${start_date}" "${end_commit}" "${end_date}" "${branch_name}"
        OLDIFS="${IFS}"
        IFS=' 
        '
        summaries=$(mktemp)
        printf '# Summary of Changes\n' >"$summaries"
        for commit in ${commits_list}; do
            build_entry "${commit}" "" "${commit}^!"
            if [ "${summary}" = "true" ]; then
                summary_response=$(summarize_diff \
                    "$(run_git_diff "${commit}" "${include_pattern}" "${exclude_pattern}")")
                printf '%s\n%s\n' "Commit: ${commit}" "${summary_response}" >>"$summaries"
            fi
        done

        temp_summary_prompt_file=$(mktemp)
        {
            printf 'Task: Provide a high-level summary of these commit summaries:\n\n<<ALL>>\n'
            printf '%b\n' "$(cat "${summaries}")"
            printf '<<ALL>>\n'
        } >"${temp_summary_prompt_file}"

        final_summary="$(generate_response "${temp_summary_prompt_file}")"
        rm -f "${temp_summary_prompt_file}"
        printf '%s\n' "${final_summary}"

        IFS="${OLDIFS}"
        [ "${debug}" = "true" ] && printf 'Generated git history in %s.\n' "${history_file}"
    fi

    generate_changelog_prompt "${history_file}" "${prompt_template}" "${existing_changelog_section}"

    if [ "${should_generate_changelog}" = "true" ]; then
        if [ ! -f "${changelog_file}" ]; then
            printf 'Creating new changelog file: %s\n' "${changelog_file}"
            printf '# Changelog\n## [Unreleased]\n' >"${changelog_file}"
        fi
        generate_changelog "${model}" "${changelog_file}" "${section_name}" "${update_mode}" "${existing_changelog_section}"
    else
        [ "${update_mode}" != "none" ] && printf 'Changelog generation skipped. Use --model-provider to enable it.\n'
    fi

    if [ "${save_history}" != "true" ]; then
        rm -f "${history_file}"
    fi
    if [ "${save_prompt}" != "true" ]; then
        rm -f "${prompt_file}"
    fi
}

script_name="$(basename -- "$0")"
if [ "${script_name}" = "changes.sh" ] || [ "${script_name}" = "changeish" ]; then
    main "$@"
fi
