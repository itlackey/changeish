#!/usr/bin/env bash
# changeish - A script to generate a changelog from Git history, optionally using AI (Ollama or remote API)
# Version: 0.2.0
# Usage: changeish [OPTIONS]
#
# Options:
#   --help                  Show this help message and exit
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
#   --update-mode MODE      Section update mode: auto (default), prepend, append, update
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
#set -euo pipefail
set -e

# Initialize default option values
debug="false"
from_rev=""
to_rev=""
default_diff_options="--minimal --no-prefix --unified=0 --no-color -b -w --compact-summary --color-moved=no"
include_pattern=""
exclude_pattern=""
todo_pattern="*todo*"
model="${CHANGEISH_MODEL:-qwen2.5-coder}"
changelog_file="./CHANGELOG.md"
prompt_template="./changelog_prompt.md"
save_prompt=false
save_history=false
version_file=""
all_history=false
current_changes=false
staged_changes=false
outfile="history.md"
remote=false
api_url="${CHANGEISH_API_URL:-}"
api_key="${CHANGEISH_API_KEY:-}"
api_model="${CHANGEISH_API_MODEL:-}"
default_todo_grep_pattern="TODO|FIX|ENHANCEMENT|DONE|CHORE|ADD"
model_provider="auto"
update_mode="auto"
section_name="auto"

# Define default prompt template (multi-line string) for AI generation
default_prompt=$(
    cat <<'END_PROMPT'
<<<INSTRUCTIONS>>>
Task: Generate a changelog from the Git history that follows the structure below. 
Be sure to use only the information from the Git history in your response. 
Output rules
1. Use only information from the Git history provided in the prompt.
2. Output **ONLY** valid Markdown based on the format provided in these instructions.
    - Do not include the ``` code block markers in your output.
3. Use this exact hierarchy:
   ### Enhancements

   - ...

   ### Fixes

   - ...

   ### Chores

   - ...
4. Omit any section that would be empty and do not include a ## header.
END_PROMPT
)
example_changelog=$(
    cat <<'END_EXAMPLE'
<<<Example Output (for reference only)>>>

### Enhancements

- Example enhancement A

<<<END>>>
END_EXAMPLE
)
# Common files to check for version changes if --version-file not specified
default_version_files=("changes.sh" "package.json" "pyproject.toml" "setup.py" "Cargo.toml" "composer.json" "build.gradle" "pom.xml")

# Update the script to latest release
update() {
    local latest_version
    latest_version=$(curl -s https://api.github.com/repos/itlackey/changeish/releases/latest | jq -r '.tag_name')
    echo "Updating changeish to version $latest_version..."
    curl -fsSL https://raw.githubusercontent.com/itlackey/changeish/main/install.sh | sh
    echo "Update complete."
    exit 0
}

# Print script version
show_version() {
    awk 'NR==3{sub(/^# Version: /, ""); print; exit}' "$0"
    exit 0
}

# Print usage information
show_help() {
    # Print the usage and options from the top comments of this script
    echo "Version: $(awk 'NR==3{sub(/^# Version: /, ""); print; exit}' "$0")"
    awk '/^set -euo pipefail/ {exit} NR>2 && /^#/{sub(/^# ?/, ""); print}' "$0" | sed -e '/^Usage:/,$!d'
    echo "Default version files to check for version changes:"
    for file in "${default_version_files[@]}"; do
        echo "  $file"
    done
    exit 0
}

# Show all available release tags
show_available_releases() {
    curl -s https://api.github.com/repos/itlackey/changeish/releases | jq -r '.[].tag_name'
    exit 0
}

# -------------------------------------------------------------------
# New helper: build a single history “entry” (commit, staged or current)
# Globals:
#   outfile            – path to Markdown history file
#   found_version_file – path to version file, if any
#   include_pattern    – pattern for “include” diffs
#   exclude_pattern    – pattern for excluding files from full diff
# Arguments:
#   $1: label to display (hash or “Staged Changes” / “Working Tree”)
#   $2: git diff range (e.g. "<hash>^!" or "--cached" or empty for worktree)
build_entry() {
    local label="$1"
    local diff_spec
    if [[ -n "$2" ]]; then
        diff_spec=("$2")
    else
        diff_spec=()
    fi

    echo "Building entry for: $label"
    echo "## $label" >>"$outfile"

    # if this is a true commit (hash^!), show commit summary
    if [[ "${diff_spec[*]:-}" =~ \^!$ ]]; then
        {
            echo "**Commit:** $(git show -s --format=%s "${diff_spec[@]}")"
            echo "**Date:**   $(git show -s --format=%ci "${diff_spec[@]}")"
            echo "**Message:**"
            echo '```'
            git show -s --format=%B "${diff_spec[@]}"
            echo '```'
        } >>"$outfile"
    fi

    #[[ "$debug" == true ]] && echo "Version diff: ${found_version_file}"

    # # version‐file diff
    # if [[ -n "$found_version_file" ]]; then
    #     {
    #         echo ""
    #         local version_diff=""
    #         if [[ ${#diff_spec[@]} -gt 0 ]]; then
    #             # shellcheck disable=SC2086
    #             version_diff="$(git --no-pager diff "${diff_spec[@]}" $default_diff_options -- "$found_version_file" | grep -Ei '^[+-].*version' || true)"
    #         else
    #             # shellcheck disable=SC2086
    #             version_diff="$(git --no-pager diff $default_diff_options "$found_version_file" | grep -Ei '^[+-].*version' || true)"
    #         fi
    #         if [[ -n "$version_diff" ]]; then
    #             echo "### Version Changes"
    #             echo '```diff'
    #             echo "$version_diff"
    #             echo '```'
    #         else
    #             # No diff, just show current version lines from the file
    #             echo "### Latest Version"
    #             echo '```diff'
    #             grep -Ei 'version' "$found_version_file" || true
    #             echo '```'
    #         fi
    #     } >>"$outfile"
    #     #[[ "$debug" == false ]] && echo "$found_version_file" >>"$outfile"
    # fi

    # [[ "$debug" == false ]] && echo "TODOs diff: ${todo_pattern}"
    if [[ "$debug" == true ]]; then
        git --no-pager diff --unified=0 -- "*todo*"
    fi
    if [[ -n "$todo_pattern" ]]; then
        local todo_diff
        if [[ ${#diff_spec[@]} -gt 0 ]]; then
            todo_diff="$(git --no-pager diff "${diff_spec[@]}" --unified=0 -b -w --no-prefix --color=never -- "$todo_pattern" | grep '^[+-]' | grep -Ev '^[+-]{2,}' || true)"
        else
            todo_diff="$(git --no-pager diff --unified=0 -b -w --no-prefix --color=never -- "$todo_pattern" | grep '^[+-]' | grep -Ev '^[+-]{2,}' || true)"
        fi
        if [[ -n "$todo_diff" ]]; then
            {
                echo
                echo "### Changes in TODOs"
                echo '```diff'
                echo -e "$todo_diff"
                echo '```'
            } >>"$outfile"
        fi
    fi

    # Validate include/exclude patterns (must be valid git pathspecs)
    if [[ -n "$include_pattern" ]]; then
        if ! git ls-files -- "*$include_pattern*" >/dev/null 2>&1; then
            echo "Error: Invalid --include-pattern '$include_pattern' (no matching files or invalid pattern)." >&2
            exit 1
        fi
    fi
    if [[ -n "$exclude_pattern" ]]; then
        if ! git ls-files -- ":(exclude)*$exclude_pattern*" >/dev/null 2>&1; then
            echo "Error: Invalid --exclude-pattern '$exclude_pattern' (no matching files or invalid pattern)." >&2
            exit 1
        fi
    fi

    # full diff stat
    # [[ "$debug" == false ]] && echo "Include pattern: $include_pattern"
    # [[ "$debug" == false ]] && echo "Exclude pattern: $exclude_pattern"

    echo >>"$outfile"
    echo "### Changes in files" >>"$outfile"
    # Prepare the diff arguments based on include/exclude patterns
    diff_args=()
    if [[ -n "$include_pattern" ]]; then
        diff_args+=("*$include_pattern*")
    fi
    if [[ -n "$exclude_pattern" ]]; then
        diff_args+=(":(exclude)*$exclude_pattern*")
    fi
    # [[ $debug ]] && echo "Full diff: ${diff_args:-""}"

    echo '```diff' >>"$outfile"
    if [[ ${#diff_spec[@]} -gt 0 ]]; then
        # shellcheck disable=SC2086
        git --no-pager diff "${diff_spec[@]}" $default_diff_options "${diff_args[@]}" >>"$outfile"
        #| grep -Ev '^(@|index |--- |\+\+\+ )' || true >>"$outfile"
    else
        # shellcheck disable=SC2086
        git --no-pager diff $default_diff_options -- "${diff_args[@]}" >>"$outfile"
        #| grep -Ev '^(^@|^index |--- |\+\+\+ )' || true >>"$outfile"
    fi
    echo '```' >>"$outfile"

    echo >>"$outfile"

    if [[ "$debug" == "true" ]]; then
        echo "History output:" && cat "$outfile"
    fi
}

# Generate the prompt file by combining the prompt template and git history
# Globals:
#   default_prompt (the built-in prompt template text)
#   prompt_file (output path for prompt file)
# Arguments:
#   $1: Path to git history markdown file
#   $2: Path to custom prompt template file (optional)
generate_prompt() {
    local history_file="$1"
    local template_file="$2"
    local existing_section="$3"
    local prompt_text
    if [[ -n "$template_file" && -f "$template_file" ]]; then
        echo "Generating prompt file from template: $template_file"
        prompt_text="$(cat "$template_file")"
    else
        prompt_text="$default_prompt"
    fi
    # Compose the final prompt by inserting markers and the git history content
    local complete_prompt
    complete_prompt="${prompt_text}"

    # If an existing changelog section is provided, include it in the prompt
    if [[ -n "$existing_section" ]]; then
        complete_prompt=$(echo -e "${complete_prompt}\\n5. Include ALL of the existing items from the "EXISTING CHANGELOG" in your response. DO NOT remove any existing items.")
        complete_prompt="${complete_prompt}\\n<<<END>>>\\n<<<EXISTING CHANGELOG>>>\\n$existing_section\\n<<<END>>>"
    else
        complete_prompt="${complete_prompt}\\n<<<END>>>\\n${example_changelog}"
    fi
    complete_prompt="${complete_prompt}\\n<<<GIT HISTORY>>>\\n$(cat "$history_file")\\n<<<END>>>"

    echo -e "$complete_prompt" >"$prompt_file"

    #[[ $debug ]] && echo "Generated prompt content in $prompt_file"
}

# Run the local Ollama model with the prompt file
# Arguments:
#   $1: Model name
#   $2: Prompt file path
run_ollama() {
    local model="$1"
    local prompt_file_path="$2"
    if [[ "$debug" == "true" ]]; then
        ollama run "$model" --verbose <"$prompt_file_path"
    else
        ollama run "$model" <"$prompt_file_path"
    fi
}

# Call remote API to generate changelog based on prompt
# Arguments:
#   $1: Remote model name
#   $2: Prompt file path
generate_remote() {
    local model="$1"
    local prompt_path="$2"
    local message response result
    message=$(cat "$prompt_path")
    response=$(curl -s -X POST "$api_url" \
        -H "Authorization: Bearer $api_key" \
        -H "Content-Type: application/json" \
        -d "$(
            jq -n --arg model "$model" --arg content "$message" \
                '{model: $model, messages: [{role: "user", content: $content}], max_completion_tokens: 8192}'
        )")

    result=$(echo "$response" | jq -r '.choices[-1].message.content')
    if [[ "$debug" == "true" ]]; then
        echo "Response from remote API:" >&2
        echo "$response" | jq . >&2
    fi
    echo "$result"
}

generate_response() {
    local response
    echo "Generating changelog using model: $model" >&2
    if $remote; then
        # Use remote API generation
        model="$api_model"
        #echo "Running remote model '$model'..." >&2
        response="$(generate_remote "$model" "$prompt_file")"
    else
        # Use local Ollama model if available
        if command -v ollama >/dev/null 2>&1; then
            #echo "Running Ollama model '$model'..." >&2
            response="$(run_ollama "$model" "$prompt_file")"
        else
            echo "ollama not found, skipping changelog generation." >&2
            exit 0
        fi
    fi
    printf '%s' "$response"
}

# Generate the changelog using either Ollama or remote API and insert it into the changelog file
# Arguments:
#   $1: Model name (for local usage)
#   $2: Changelog file path
#   $3: Section name (version string)
#   $4: Update mode (auto, update, prepend, append)
#   $5: Existing changelog section (content to be replaced, if any)
generate_changelog() {
    local model="$1"
    local changelog_file_path="$2"
    local section_name="$3"
    local update_mode="$4"
    local existing_changelog_section="$5"
    local changelog
    changelog=$(generate_response)
    if [[ "$debug" == "true" ]]; then
        echo "$changelog"
    fi
    echo -e "\n## Changelog (generated by changeish using $model)\n"
    echo '```'
    echo "$changelog"
    echo '```'
    insert_changelog "$changelog_file_path" "$changelog" "$section_name" "$update_mode" "$existing_changelog_section"
}

# Insert the generated changelog content at the top of the changelog file (after the title line)
# Arguments:
#   $1: Changelog file path
#   $2: Changelog content to insert
#   $3: Section name (version string)
#   $4: Update mode (auto, update, prepend, append)
#   $5: Existing changelog section (content to be replaced, if any)
# Globals referenced:
#   debug                  – enable debug output
insert_changelog() {
    local file="$1"
    local content="$2"
    local section_name="$3"
    local update_mode="$4"
    local existing_changelog_section="$5"
    local version="$section_name"
    local esc_version
    esc_version="$(echo "$version" | sed 's/[][\\/.*^$]/\\&/g')"
    local pattern="^## $section_name?"

    # if content does not end with a newline, add one
    if [[ "${content: -1}" != $'\n' ]]; then
        content="$content"$'\n'
    fi

    if [[ -n "$existing_changelog_section" ]]; then
        # Section exists
        case "$update_mode" in
        update | auto)
            [[ "$debug" == true ]] && echo "Updating existing changelog section for '$section_name' in $file"
            [[ "$debug" == true ]] && echo "Existing section content: $existing_changelog_section"
            local start_line end_line
            start_line=$(grep -nE "$pattern" "$file" | head -n1 | cut -d: -f1)
            end_line=$(tail -n +"$((start_line + 1))" "$file" | grep -n '^## ' | head -n1 | cut -d: -f1)
            if [[ -n "$end_line" ]]; then
                end_line=$((start_line + end_line - 1))
            else
                end_line=$(wc -l <"$file")
            fi
            awk -v start="$start_line" -v end="$end_line" -v version="$version" -v content="$content" '
                NR < start { print }
                NR == start { print "## " version; print content }
                NR > end { print }
            ' "$file" >"${file}.tmp" && mv "${file}.tmp" "$file"
            ;;
        prepend)
            # Insert content immediately before the section header
            local start_line
            start_line=$(grep -nE "$pattern" "$file" | head -n1 | cut -d: -f1)
            if [[ -z "$start_line" ]]; then
                echo "Section '$section_name' not found in $file" >&2
                exit 1
            fi
            awk -v insert_line="$start_line" -v content="$content" '
                NR == insert_line {
                    print "## Current Changes"
                    print content
                }
                { print }
            ' "$file" >"${file}.tmp" && mv "${file}.tmp" "$file"
            ;;
        append)
            [[ "$debug" == true ]] && echo "Appending 'Current Changes' section after existing section for '$section_name' in $file"
            local esc_section
            esc_section="$(echo "$section_name" | sed 's/[][\\/.*^$]/\\&/g')"
            local start_line end_line
            start_line=$(grep -nE "^##[[:space:]]*\\[?$esc_section\\]?" "$file" | head -n1 | cut -d: -f1 || true)
            [[ "$debug" == true ]] && echo "Start line for section '$section_name': $start_line"
            if [[ -z "$start_line" ]]; then
                echo "Section '$section_name' not found in $file" >&2
                exit 1
            fi
            [[ "$debug" == true ]] && echo "Finding end line for section '$section_name' in $file"
            end_line=$(tail -n +$((start_line + 1)) "$file" | grep -n '^## ' | head -n1 | cut -d: -f1 || true)
            if [[ -n "$end_line" ]]; then
                end_line=$((start_line + end_line - 1))
            else
                end_line=$(awk 'END{print NR}' "$file")
            fi
            [[ "$debug" == true ]] && echo "End line for section '$section_name': $end_line"
            [[ "$debug" == true ]] && echo "Appending $content"
            awk -v end="$end_line" -v content="$content" 'NR==end{print content;print; next}1' "$file" >"${file}.tmp" && mv "${file}.tmp" "$file"
            ;;
        esac
    else
        [[ "$debug" == true ]] && echo "Adding ($update_mode) new changelog section for '$section_name' in $file"
        case "$update_mode" in
        append)
            echo -e "\n## $version\n$content" >>"$file"
            ;;
        update | auto | prepend)
            # Insert versioned section after the first top-level header
            local first_h1_line
            first_h1_line=$(grep -n '^# ' "$file" | head -n1 | cut -d: -f1 || true)
            [[ "$debug" == true ]] && echo "First H1 line: $first_h1_line"
            if [[ -n "$first_h1_line" ]]; then
                awk -v line="$first_h1_line" -v version="$version" -v content="$content" '
                    NR==line {
                        print
                        print ""
                        print "## " version
                        print content
                        next
                    }
                    { print }
                ' "$file" >"${file}.tmp" && mv "${file}.tmp" "$file"
            else
                # No H1 found, insert at top
                echo "## $version" >>"$file"
                echo "$content" >>"$file"
            fi
            ;;
        esac
    fi

    # ──────────────────────────────────────────────────────────────────────────
    # Normalize headers:
    # - Deduplicate only H1 (# ) and H2 (## ) lines
    # - Always ensure one blank line before & after every header
    awk '
    BEGIN { prev = "" }
    {
        if ($0 ~ /^# /) {
            # H1: dedupe
            if (!seen1[$0]++) {
                if (prev != "") print ""
                print
                print ""
                prev = ""
            }
        }
        else if ($0 ~ /^## /) {
            # H2: dedupe
            if (!seen2[$0]++) {
                if (prev != "") print ""
                print
                print ""
                prev = ""
            }
        }
        else if ($0 ~ /^###/) {
            # H3+ (###…): always print, but still normalize spacing
            if (prev != "") print ""
            print
            print ""
            prev = ""
        }
        else {
            # normal line
            print
            prev = $0
        }
    }
    ' "$file" >"${file}.tmp" && mv "${file}.tmp" "$file"

    if ! (tail -n5 "$file" | grep -q "Managed by changeish"); then
        echo -e "\n[Managed by changeish](https://github.com/itlackey/changeish)\n" >>"$file"
    fi

    # Remove any double blank lines (two or more newlines in a row) and replace with a single blank line
    # after all other processing
    sed -i ':a;N;$!ba;s/\n\{3,\}/\n\n/g' "$file"

}

# Extract the current version string from a version file
# Arguments:
#   $1: Path to the version file
# Returns:
#   Prints the detected version string, or empty if not found
get_current_version_from_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo ""
        return 1
    fi

    # If files is changes.sh, try to extract version from the first line
    if [[ "$file" == "changes.sh" ]]; then
        local version
        version=$(grep -Eo 'Version: [0-9]+\.[0-9]+(\.[0-9]+)?' "$file" | head -n3 | grep -Eo 'v?[0-9]+\.[0-9]+(\.[0-9]+)?')
        if [[ -n "$version" ]]; then
            echo "$version"
            return 0
        fi
    fi

    # Try common version patterns
    local version
    version=$(grep -Eo 'version[[:space:]]*[:=][[:space:]]*["'\'']?([0-9]+\.[0-9]+(\.[0-9]+)?)' "$file" | head -n1 | grep -Eo '([0-9]+\.[0-9]+(\.[0-9]+)?)')
    if [[ -n "$version" ]]; then
        echo "$version"
        return 0
    fi
    # Try Python __version__
    version=$(grep -Eo '__version__[[:space:]]*=[[:space:]]*["'\'']([0-9]+\.[0-9]+(\.[0-9]+)?)' "$file" | head -n1 | grep -Eo '([0-9]+\.[0-9]+(\.[0-9]+)?)')
    if [[ -n "$version" ]]; then
        echo "$version"
        return 0
    fi
    # Try package.json style
    version=$(grep -E '"version"[[:space:]]*:[[:space:]]*"[0-9]+\.[0-9]+(\.[0-9]+)?"' "$file" | head -n1 | grep -Eo '([0-9]+\.[0-9]+(\.[0-9]+)?)')
    if [[ -n "$version" ]]; then
        echo "$version"
        return 0
    fi
    # Try other common patterns
    version=$(grep -Eo '[vV]?([0-9]+\.[0-9]+(\.[0-9]+)?)' "$file" | head -n1 | grep -Eo '([0-9]+\.[0-9]+(\.[0-9]+)?)')
    if [[ -n "$version" ]]; then
        echo "$version"
        return 0
    fi
    echo ""
    return 1
}

# Extract the content of a matching changelog section by section name
# Arguments:
#   $1: Section name (e.g. "1.2.3" or "Current Changes")
#   $2: Changelog file path
extract_changelog_section() {
    local section_name="$1"
    local file="$2"

    if [[ ! -f "$file" ]]; then
        echo ""
        return 0
    # else
    #     [[ $debug ]] && printf '%s' "Extracting section '$section_name' from $file"
    fi
    local esc_version
    esc_version="$(echo "$section_name" | sed 's/[][\\/.*^$]/\\&/g')"
    local pattern="^##[[:space:]]*\\[?$esc_version\\]?"
    local start_line end_line
    start_line=$(grep -nE "$pattern" "$file" | head -n1 | cut -d: -f1)

    if [[ -z "$start_line" ]]; then
        echo ""
        return 0
    else
        start_line=$((start_line + 1)) # remove the header line
    fi
    end_line=$(tail -n +$((start_line + 1)) "$file" | grep -n '^## ' | head -n1 | cut -d: -f1)
    if [[ -n "$end_line" ]]; then
        end_line=$((start_line + end_line - 1))
    else
        end_line=$(wc -l <"$file")
    fi
    sed -n "${start_line},${end_line}p" "$file"
}

config_file=""

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    # Parse --config-file argument if specified
    for ((i = 1; i <= $#; i++)); do
        if [[ "${!i}" == "--config-file" ]]; then
            next=$((i + 1))
            config_file="${!next}"
            break
        fi
    done

    # Parse command-line arguments
    while [[ $# -gt 0 ]]; do
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
            save_prompt=true
            shift
            ;;
        --save-history)
            save_history=true
            shift
            ;;
        --version-file)
            version_file="$2"
            shift 2
            ;;
        --current)
            current_changes=true
            shift
            ;;
        --staged)
            staged_changes=true
            shift
            ;;
        --all)
            all_history=true
            shift
            ;;
        --debug)
            debug=true
            shift
            ;;
        --update) update ;;
        --available-releases) show_available_releases ;;
        --help) show_help ;;
        --version) show_version ;;
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
            echo "Unknown arg: $1" >&2
            exit 1
            ;;
        esac
    done

    # Handle --make-prompt-template if set
    if [[ -n "${make_prompt_template_path:-}" ]]; then
        echo "$default_prompt" >"$make_prompt_template_path"
        echo "Default prompt template written to $make_prompt_template_path."
        exit 0
    fi

    # Load configuration file if specified, otherwise source .env in current directory if present
    if [[ -n "$config_file" ]]; then
        if [[ -f "$config_file" ]]; then
            # [[ "$debug" == true ]] && echo "Sourcing config file: $config_file"
            # shellcheck disable=SC1090
            source "$config_file"
        else
            echo "Error: config file '$config_file' not found." >&2
            exit 1
        fi
    elif [[ -f .env ]]; then
        # [[ $debug ]] && echo "Sourcing .env file..."
        # shellcheck disable=SC1091
        source .env
    fi

    # Determine the file to track version changes
    found_version_file=""
    if [[ -n "$version_file" ]]; then
        if [[ -f "$version_file" ]]; then
            found_version_file="$version_file"
        else
            echo "Error: Specified version file '$version_file' does not exist." >&2
            exit 1
        fi
    else
        # Auto-detect: use first existing common version file
        for vf in "${default_version_files[@]}"; do
            if [[ -f "$vf" ]]; then
                found_version_file="$vf"
                break
            fi
        done
    fi

    # If no section name is set, try to detect the current version from the version file
    if [[ -z "$section_name" || "$section_name" == "auto" ]]; then
        if [[ -n "$found_version_file" ]]; then
            current_version=$(get_current_version_from_file "$found_version_file")
            if [[ -n "$current_version" ]]; then
                section_name="$current_version"
            else
                section_name="Current Changes"
            fi
        else
            section_name="Current Changes"
        fi
    fi
    echo "Using section name: $section_name"

    # set existing_changelog_section
    existing_changelog_section=$(extract_changelog_section "$section_name" "$changelog_file")

    # Decide on output filenames for history and prompt
    if $save_history; then
        outfile="history.md"
    else
        outfile="$(mktemp)"
    fi
    if $save_prompt; then
        prompt_file="prompt.md"
    else
        prompt_file="$(mktemp)"
    fi

    # Ensure we are in a git repository
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "Error: Not a git repository. Please run this script inside a git repository." >&2
        exit 1
    fi

    # Check for at least one commit before using HEAD
    if ! git rev-parse HEAD >/dev/null 2>&1; then
        echo "No commits found in repository. Nothing to show." >&2
        exit 1
    fi

    # If no specific range or mode is set, default to current uncommitted changes
    if ! $staged_changes && ! $all_history && [[ -z "$to_rev" && -z "$from_rev" ]]; then
        current_changes=true
    fi

    # Changelog generation logic
    should_generate_changelog=true
    case "$model_provider" in
    none)
        should_generate_changelog=false
        ;;
    local)
        remote=false
        ;;
    remote)
        remote=true
        ;;
    auto)
        # auto: try local, fallback to remote if ollama not found
        if ! command -v ollama >/dev/null 2>&1; then
            if [[ "$debug" == true ]]; then
                echo "ollama not found, falling back to remote API."
            fi
            remote=true
            # Remote mode requires API key and URL
            if [[ -z "$api_key" ]]; then
                echo "Warning: Falling back to remote but CHANGEISH_API_KEY is not set." >&2
                remote=false
                should_generate_changelog=false
            fi
            if [[ -z "$api_url" ]]; then
                echo "Warning: Falling back to remote but no API URL provided (use --api-url or CHANGEISH_API_URL)." >&2
                remote=false
                should_generate_changelog=false
            fi
        fi
        ;;
    *)
        echo "Unknown --model-provider: $model_provider" >&2
        exit 1
        ;;
    esac

    if [[ $should_generate_changelog && ! "auto prepend append update" =~ $update_mode ]]; then
        echo "Error: --update-mode must be one of auto, prepend, append, update." >&2
        exit 1
    fi

    # If no remote model specified but remote flag is used, set defaults
    if $remote; then
        if [[ -z "$api_model" ]]; then
            api_model="$model"
        fi
        # Remote mode requires API key and URL
        if [[ -z "$api_key" ]]; then
            echo "Error: --remote specified but CHANGEISH_API_KEY is not set." >&2
            exit 1
        fi
        if [[ -z "$api_url" ]]; then
            echo "Error: --remote specified but no API URL provided (use --api-url or CHANGEISH_API_URL)." >&2
            exit 1
        fi
    fi

    # Apply environment variable overrides for model if not set via CLI
    if [[ -n "${CHANGEISH_MODEL:-}" && "$model" == "qwen2.5-coder" ]]; then
        model="$CHANGEISH_MODEL"
    fi

    # Debug output
    if [[ "$debug" == true ]]; then
        echo "## Settings"
        echo "Debug mode enabled."
        echo "Using model: $model"
        echo "Remote mode: $remote"
        echo "API URL: $api_url"
        echo "API Model: $api_model"
        echo "Model provider: $model_provider"
        echo "Should generate changelog: $should_generate_changelog"
        echo "Changelog file: $changelog_file"
        echo "Prompt template: $prompt_template"
        echo "Version file: $found_version_file"
        echo "All history: $all_history"
        echo "Current changes: $current_changes"
        echo "Staged changes: $staged_changes"
        echo "Save prompt: $save_prompt"
        echo "Save history: $save_history"
        echo "Include pattern: $include_pattern"
        echo "Exclude pattern: $exclude_pattern"
        echo "TODO pattern: $todo_pattern"
        echo "TODO grep pattern: $default_todo_grep_pattern"

        echo "## End Settings"
    fi

    # Handle uncommitted (working tree) changes
    if $current_changes; then
        build_entry "Working Tree" ""
        echo "Generated git history for uncommitted changes in $outfile."

    # Handle staged (index) changes
    elif $staged_changes; then
        build_entry "Staged Changes" "--cached"
        echo "Generated git history for staged changes in $outfile."

    # Handle a specified commit range (including --all)
    else
        if [[ -z "$to_rev" ]]; then to_rev="HEAD"; fi
        if [[ -z "$from_rev" ]]; then from_rev="HEAD"; fi
        # Collect commits in chronological order (oldest first)
        if $all_history; then
            range_spec="--all"
            echo "Using commit range: --all (all history)"
        else
            range_spec="${to_rev}^..${from_rev}"
            echo "Using commit range: ${to_rev}^..${from_rev}"
        fi
        mapfile -t commits < <(git rev-list --reverse "$range_spec")
        if [[ ${#commits[@]} -eq 0 ]]; then
            echo "No commits found in range ${to_rev}^..${from_rev}" >&2
            exit 1
        fi
        start_commit="${commits[0]}"
        end_commit="${commits[-1]}"
        start_date="$(git show -s --format=%ci "$start_commit")"
        end_date="$(git show -s --format=%ci "$end_commit")"
        total_commits=${#commits[@]}
        echo "Generating git history for $total_commits commits from $start_commit ($start_date) to $end_commit ($end_date) on branch $(git rev-parse --abbrev-ref HEAD)..."

        for commit in "${commits[@]}"; do
            build_entry "$commit" "$commit^!"
        done
        echo "Generated git history in $outfile."
    fi

    # Create the prompt file from the git history
    if [[ "$debug" == "true" ]]; then
        echo "Existing changelog section for '$section_name':"
        echo "$existing_changelog_section"
    fi
    generate_prompt "$outfile" "$prompt_template" "$existing_changelog_section"

    if $should_generate_changelog; then
        if [[ ! -f $changelog_file ]]; then
            echo "Creating new changelog file: $changelog_file"
            echo "# Changelog" >"$changelog_file"
            echo "" >>"$changelog_file"
        fi
        generate_changelog "$model" "$changelog_file" "$section_name" "$update_mode" "$existing_changelog_section"
    else
        echo "Changelog generation skipped. Use --model-provider to enable it."
    fi

    # Cleanup: remove temp files if not saving them
    if ! $save_history; then
        rm -f "$outfile"
    fi
    if ! $save_prompt; then
        rm -f "$prompt_file"
    fi

fi
