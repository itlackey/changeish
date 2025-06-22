#!/usr/bin/env bash
# changeish - A script to generate a changelog from Git history, optionally using AI (Ollama or remote API)
# Version: 0.2.0 (unreleased)
# Usage: changeish [OPTIONS]
#
# Options:
#   --help               Show this help message and exit
#   --current            Use uncommitted (working tree) changes for git history
#   --staged             Use staged (index) changes for git history
#   --all                Include all history (from first commit to HEAD)
#   --from REV           Set the starting commit (default: HEAD)
#   --to REV             Set the ending commit (default: HEAD^)
#   --include-pattern P  Show diffs for files matching pattern P (and exclude them from full diff)
#   --exclude-pattern P  Exclude files matching pattern P from full diff (default: same as include pattern if --include-pattern is used)
#   --model MODEL        Specify the local Ollama model to use (default: qwen2.5-coder)
#   --remote             Use remote API for changelog generation instead of local model
#   --api-model MODEL    Specify remote API model (overrides --model for remote usage)
#   --api-url URL        Specify remote API endpoint URL for changelog generation
#   --changelog-file PATH  Path to changelog file to update (default: ./CHANGELOG.md)
#   --prompt-template PATH  Path to prompt template file (default: ./changelog_prompt.md)
#   --save-prompt        Generate prompt file only and do not produce changelog (replaces --prompt-only)
#   --save-history       Do not delete the intermediate git history file (save it as git_history.md in working directory)
#   --version-file PATH  File to check for version number changes in each commit (default: auto-detect common files)
#   --update             Update this script to the latest version and exit
#   --available-releases Show available script releases and exit
#   --version            Show script version and exit
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
#   changeish --remote --api-model gpt-4 --api-url https://api.example.com/v1/chat/completions
#
# Environment variables:
#   CHANGEISH_MODEL       Default model to use for local generation (overridden by --model)
#   CHANGEISH_API_KEY     API key for remote generation (required if --remote is used)
#   CHANGEISH_API_URL     Default API URL for remote generation (overridden by --api-url)
#   CHANGEISH_API_MODEL   Default API model for remote generation (overridden by --api-model)
#
set -euo pipefail

# Initialize default option values
debug=false
from_rev=""
to_rev=""
default_diff_options="--patience --unified=0 --no-color -b -w --compact-summary --color-moved=no"
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
default_todo_grep_pattern="TODO|FIXME|ENHANCEMENT|DONE|CHORE"

# Define default prompt template (multi-line string) for AI generation
default_prompt=$(
    cat <<'END_PROMPT'
<<<INSTRUCTIONS>>>
Task: Generate a changelog from the Git history that follows the structure below. Be sure to use only the information from the Git history in your response.
Output rules
1. Use only information from the Git history provided in the prompt.
2. Output **ONLY** valid Markdown on the format provided in these instructions.
3. Use this exact hierarchy:

   ## {version} ({date})

   ### Enhancements

   - ...

   ### Fixes

   - ...

   ### Chores

   - ...
4. Omit any section that would be empty.

Version ordering: newest => oldest (descending).

### Example Output (for reference only)

## v2.0.1 (2025-02-13)

### Enhancements

- Example enhancement A

### Fixes

- Example fix A

### Chores

- Example chore A
<<<END>>>
END_PROMPT
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

# Print usage information
show_help() {
    # Print the usage and options from the top comments of this script
    awk 'NR>2 && /^#/{sub(/^# ?/, ""); print}' "$0" | sed -e '/^Usage:/,$!d'
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

# Print script version
show_version() {
    awk 'NR==3{sub(/^# Version: /, ""); print; exit}' "$0"
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
        diff_spec=($2)
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

    [[ $debug ]] && echo "Version diff: ${found_version_file}"

    # version‐file diff
    if [[ -n "$found_version_file" ]]; then
        {
            echo ""
            local version_diff=""
            if [[ ${#diff_spec[@]} -gt 0 ]]; then
                version_diff="$(git diff "${diff_spec[@]}" $default_diff_options -- "$found_version_file" | grep -Ei '^[+-].*version' || true)"
            else
                version_diff="$(git diff $default_diff_options "$found_version_file" | grep -Ei '^[+-].*version' || true)"
            fi
            if [[ -n "$version_diff" ]]; then
                echo "### Version Changes"
                echo '```diff'
                echo "$version_diff"
                echo '```'
            else
                # No diff, just show current version lines from the file
                echo "### Latest Version"
                echo '```diff'
                grep -Ei 'version' "$found_version_file" || true
                echo '```'
            fi
        } >>"$outfile"
        [[ $debug ]] && echo "$found_version_file" >>"$outfile"
    fi

    [[ $debug ]] && echo "TODOs diff: ${todo_pattern}"
    if [[ $debug ]]; then
        git diff --unified=0 -- "*todo*"
    fi
    if [[ -n "$todo_pattern" ]]; then
        local todo_diff
        if [[ ${#diff_spec[@]} -gt 0 ]]; then
            todo_diff="$(git diff "${diff_spec[@]}" --unified=0 -b -w --no-prefix --color=never -- "$todo_pattern" | grep '^[+-]' | grep -Ev '^[+-]{2,}' || true)"
        else
            todo_diff="$(git diff --unified=0 -b -w --no-prefix --color=never -- "$todo_pattern" | grep '^[+-]' | grep -Ev '^[+-]{2,}' || true)"
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
    [[ $debug ]] && echo "Include pattern: $include_pattern"
    [[ $debug ]] && echo "Exclude pattern: $exclude_pattern"

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
    [[ $debug ]] && echo "Full diff: ${diff_args:-""}"

    echo '```diff' >>"$outfile"
    if [[ ${#diff_spec[@]} -gt 0 ]]; then
        git diff "${diff_spec[@]}" $default_diff_options "${diff_args[@]}" >>"$outfile"
    else
        git diff $default_diff_options -- "${diff_args[@]}" >>"$outfile"
    fi
    echo '```' >>"$outfile"

    echo >>"$outfile"

    [[ $debug ]] && echo "History output:" && cat "$outfile" >&2
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
    local prompt_text
    if [[ -n "$template_file" && -f "$template_file" ]]; then
        echo "Generating prompt file from template: $template_file"
        prompt_text="$(cat "$template_file")"
    else
        prompt_text="$default_prompt"
    fi
    # Compose the final prompt by inserting markers and the git history content
    local complete_prompt
    complete_prompt="${prompt_text}\\n<<<GIT HISTORY>>>\\n$(cat "$history_file")\\n<<<END>>>"
    echo -e "$complete_prompt" >"$prompt_file"

    [[ $debug ]] && echo "Generated prompt content in $prompt_file"
}

# Run the local Ollama model with the prompt file
# Arguments:
#   $1: Model name
#   $2: Prompt file path
run_ollama() {
    local model="$1"
    local prompt_file_path="$2"
    if [[ $debug ]]; then
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
    if [[ $debug ]]; then
        echo "Response from remote API:" >&2
        echo "$response" | jq . >&2
    fi
    echo "$result"
}

# Generate the changelog using either Ollama or remote API and insert it into the changelog file
# Globals:
#   remote (boolean, whether to use remote API)
#   api_model (the model name for remote API)
#   api_url, api_key (remote API endpoint and key)
#   prompt_file (path to prompt file)
# Arguments:
#   $1: Model name (for local usage)
#   $2: Changelog file path
generate_changelog() {
    local model="$1"
    local changelog_file_path="$2"
    local changelog
    if $remote; then
        # Use remote API generation
        model="$api_model"
        echo "Running remote model '$model'..."
        changelog="$(generate_remote "$model" "$prompt_file")"
    else
        # Use local Ollama model if available
        if command -v ollama >/dev/null 2>&1; then
            echo "Running Ollama model '$model'..."
            changelog="$(run_ollama "$model" "$prompt_file")"
        else
            echo "ollama not found, skipping changelog generation."
            exit 0
        fi
    fi
    # Append attribution to changelog content
    changelog="${changelog}\\n\\nGenerated by changeish"
    # Print the generated changelog for user reference
    echo -e "\n## Changelog (generated by changeish using $model)\n"
    echo '```'
    echo "$changelog"
    echo '```'
    # Insert the changelog content into the specified changelog file
    insert_changelog "$changelog_file_path" "$changelog"
}

# Insert the generated changelog content at the top of the changelog file (after the title line)
# Arguments:
#   $1: Changelog file path
#   $2: Changelog content to insert
insert_changelog() {
    local changelog_file_path="$1"
    local new_content="$2"
    if [[ -f "$changelog_file_path" ]]; then
        local tmp_file changelog_tmp
        tmp_file="$(mktemp)"
        changelog_tmp="$(mktemp)"
        printf '%s\n' "$new_content" >"$changelog_tmp"
        if grep -q '^## ' "$changelog_file_path"; then
            # Insert new content right after the first line (presumably the title or initial heading) and before existing entries
            awk -v newfile="$changelog_tmp" 'NR==1 { print; print ""; while ((getline line < newfile) > 0) print line; close(newfile); next } /^## / { print; f=1; next } { if(f) print; else next }' "$changelog_file_path" >"$tmp_file" && mv "$tmp_file" "$changelog_file_path"
        else
            # If no second-level heading exists, just append the content
            printf '\n%s\n' "$new_content" >>"$changelog_file_path"
        fi
        rm -f "$changelog_tmp"
        echo "Inserted new changelog entry into '$changelog_file_path'."
    else
        echo "Changelog file '$changelog_file_path' not found. Skipping insertion." >&2
    fi
}

config_file=""
# Parse --config-file argument if specified
for ((i = 1; i <= $#; i++)); do
    if [[ "${!i}" == "--config-file" ]]; then
        next=$((i + 1))
        config_file="${!next}"
        break
    fi
done

# Load configuration file if specified, otherwise source .env in current directory if present
if [[ -n "$config_file" ]]; then
    if [[ -f "$config_file" ]]; then
        [[ $debug ]] && echo "Sourcing config file: $config_file"
        # shellcheck disable=SC1090
        source "$config_file"
    else
        echo "Error: config file '$config_file' not found." >&2
        exit 1
    fi
elif [[ -f .env ]]; then
    [[ $debug ]] && echo "Sourcing .env file..."
    # shellcheck disable=SC1091
    source .env
fi

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
    --remote)
        remote=true
        shift
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
    *)
        echo "Unknown arg: $1" >&2
        exit 1
        ;;
    esac
done

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

if [[ $debug ]]; then
    echo "Debug mode enabled."
    echo "Using model: $model"
    echo "Remote mode: $remote"
    echo "API URL: $api_url"
    echo "API Model: $api_model"
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
generate_prompt "$outfile" "$prompt_template"

if ! $save_prompt; then
    generate_changelog "$model" "$changelog_file"
fi

# Cleanup: remove temp files if not saving them
if ! $save_history; then
    rm -f "$outfile"
fi
if ! $save_prompt; then
    rm -f "$prompt_file"
fi
