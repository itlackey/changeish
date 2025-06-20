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

debug=true

# Define default prompt template (multi-line string) for AI generation
default_prompt=$(cat <<'END_PROMPT'
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
    awk 'NR==2{sub(/^# Version: /, ""); print; exit}' "$0"
    exit 0
}

# Write the git commit history and diffs (filtered) to a markdown file
# Globals:
#   found_version_file (if set, path of file to check for version changes)
#   include_pattern (if set, pattern to include for detailed diffs)
#   exclude_pattern (if set, pattern to exclude from full diff)
# Arguments:
#   $1: Output file path for history
#   $2: Git branch name
#   $3: Starting commit
#   $4: Ending commit
#   $5: Start commit date
#   $6: End commit date
#   $@: List of commit hashes (should be passed after the first 6 arguments)
write_git_history() {
    local outfile="$1"
    local branch="$2"
    local start="$3"
    local end="$4"
    local start_date="$5"
    local end_date="$6"
    shift 6
    local commits=("$@")
    {
        echo "# Git History"
        echo
        echo "**Branch:** $branch"
        echo
        echo "**Range:** from \`$start\` ($start_date) to \`$end\` ($end_date)"
        echo
        for commit in "${commits[@]}"; do
            local name date message
            name="$(git show -s --format=%s "$commit")"
            date="$(git show -s --format=%ci "$commit")"
            message="$(git show -s --format=%B "$commit")"
            echo "## \`$commit\`"
            echo
            echo "**Commit:** $name"
            echo
            echo "**Date:** $date"
            echo
            echo "**Message:**"
            echo '```'
            printf '%s\n' "$message"
            echo '```'
            echo
            # If a version file was found, show version number changes in that file for this commit
            if [[ -n "$found_version_file" ]]; then
                echo "**Version number changes in $found_version_file:**"
                echo '```diff'
                # Show lines with 'version' (added and removed) in the diff for the version file
                git diff "$commit^!" --unified=0 -- "$found_version_file" | grep -Ei '^[+-].*version' || true
                echo '```'
                echo
            fi
            # If include_pattern is set, show added lines from diffs for matching files
            if [[ -n "$include_pattern" ]]; then
                echo "**Diffs for files matching '$include_pattern':**"
                echo '```diff'
                git diff "$commit^!" --unified=0 -- "*$include_pattern*" | grep '^+' | grep -v '^+++' || true
                echo '```'
                echo
            fi
            # Always show a summary of all other changes (exclude pattern files from full diff if specified)
            echo "**Full diff:**"
            echo '```diff'
            if [[ -n "$exclude_pattern" ]]; then
                git diff "$commit^!" --unified=0 --stat ":(exclude)*$exclude_pattern*"
            else
                git diff "$commit^!" --unified=0 --stat
            fi
            echo '```'
            echo
        done
    } > "$outfile"
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
    echo -e "$complete_prompt" > "$prompt_file"

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
        ollama run "$model" < "$prompt_file_path" --verbose
    else
        ollama run "$model" < "$prompt_file_path"
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
        -d "$(jq -n --arg model "$model" --arg content "$message" \
              '{model: $model, messages: [{role: "user", content: $content}], max_completion_tokens: 8192}' \
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
        printf '%s\n' "$new_content" > "$changelog_tmp"
        if grep -q '^## ' "$changelog_file_path"; then
            # Insert new content right after the first line (presumably the title or initial heading) and before existing entries
            awk -v newfile="$changelog_tmp" 'NR==1 { print; print ""; while ((getline line < newfile) > 0) print line; close(newfile); next } /^## / { print; f=1; next } { if(f) print; else next }' "$changelog_file_path" > "$tmp_file" && mv "$tmp_file" "$changelog_file_path"
        else
            # If no second-level heading exists, just append the content
            printf '\n%s\n' "$new_content" >> "$changelog_file_path"
        fi
        rm -f "$changelog_tmp"
        echo "Inserted new changelog entry into '$changelog_file_path'."
    else
        echo "Changelog file '$changelog_file_path' not found. Skipping insertion." >&2
    fi
}

config_file=""
# Parse --config-file argument if specified
for ((i=1; i<=$#; i++)); do
  if [[ "${!i}" == "--config-file" ]]; then
    next=$((i+1))
    config_file="${!next}"
    break
  fi
done


# Load configuration file if specified, otherwise source .env in current directory if present
if [[ -n "$config_file" ]]; then
    if [[ -f "$config_file" ]]; then
        [[ $debug ]] && echo "Sourcing config file: $config_file"             
        source "$config_file"
    else
        echo "Error: config file '$config_file' not found." >&2
        exit 1
    fi
elif [[ -f .env ]]; then
    [[ $debug ]] && echo "Sourcing .env file..."
    source .env
fi

# Initialize default option values
from_rev=""
to_rev=""
short_diff=false
include_pattern=""
exclude_pattern=""
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
show_releases=false
remote=false
api_url="${CHANGEISH_API_URL:-}"
api_key="${CHANGEISH_API_KEY:-}"
api_model="${CHANGEISH_API_MODEL:-}"

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --from) from_rev="$2"; shift 2 ;;
        --to) to_rev="$2"; shift 2 ;;
        --include-pattern) include_pattern="$2"; shift 2 ;;
        --exclude-pattern) exclude_pattern="$2"; shift 2 ;;
        --model) model="$2"; shift 2 ;;
        --remote) remote=true; shift ;;
        --api-model) api_model="$2"; shift 2 ;;
        --api-url) api_url="$2"; shift 2 ;;
        --config-file) config_file="$2"; shift 2 ;;
        --changelog-file) changelog_file="$2"; shift 2 ;;
        --prompt-template) prompt_template="$2"; shift 2 ;;
        --save-prompt) save_prompt=true; shift ;;
        --save-history) save_history=true; shift ;;
        --version-file) version_file="$2"; shift 2 ;;
        --current) current_changes=true; shift ;;
        --staged) staged_changes=true; shift ;;
        --all) all_history=true; shift ;;
        --update) update ;;
        --available-releases) show_available_releases ;;
        --help) show_help ;;
        --version) show_version ;;
        *) echo "Unknown arg: $1" >&2; exit 1 ;;
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

# If no specific range or mode is set, default to current uncommitted changes
if ! $staged_changes && ! $all_history && [[ -z "$to_rev" && -z "$from_rev" ]]; then
    current_changes=true
fi

# Handle uncommitted (working tree) changes
if $current_changes; then
    {
        echo ""
        echo "# Git History (Uncommitted Changes)"
        echo
        echo "**Branch:** $(git rev-parse --abbrev-ref HEAD)"
        echo
        echo "**Uncommitted changes as of:** $(date)"
        echo
        if [[ -n "$found_version_file" ]]; then
            echo "**Version number changes in $found_version_file:**"
            echo '```diff'
            git diff --unified=0 "$found_version_file" | grep -Ei '^[+-].*version' || true
            echo '```'
            echo
        fi
        echo "**Diff:**"
        echo '```diff'
        if [[ -n "$exclude_pattern" ]]; then
            git diff --unified=0 --stat -- ":(exclude)*$exclude_pattern*"
        else
            git diff --unified=0 --stat
        fi
        echo '```'
        echo
        if [[ -n "$include_pattern" ]]; then
            echo "**Diffs for files matching '$include_pattern':**"
            echo '```diff'
            git diff --unified=0 -- "*$include_pattern*" | grep '^+' | grep -v '^+++' || true
            echo '```'
            echo
        fi
    } > "$outfile"
    echo "Generated git history for uncommitted changes in $outfile."

# Handle staged (index) changes
elif $staged_changes; then
    {
        echo ""
        echo "# Git History (Staged Changes)"
        echo
        echo "**Branch:** $(git rev-parse --abbrev-ref HEAD)"
        echo
        echo "**Staged changes as of:** $(date)"
        echo
        if [[ -n "$found_version_file" ]]; then
            echo "**Version number changes in $found_version_file:**"
            echo '```diff'
            git diff --unified=0 --cached "$found_version_file" | grep -Ei '^.*version.*[vV]?[0-9]+\.[0-9]+(\.[0-9]+)?' || true
            echo '```'
            echo
        fi
        echo "**Diff:**"
        echo '```diff'
        if [[ -n "$exclude_pattern" ]]; then
            git diff --minimal --unified=0 --stat --cached -- ":(exclude)*$exclude_pattern*"
        else
            git diff --minimal --unified=0 --stat --cached
        fi
        echo '```'
        echo
        if [[ -n "$include_pattern" ]]; then
            echo "**Diffs for files matching '$include_pattern':**"
            echo '```diff'
            git diff --minimal --unified=0 --cached -- "*$include_pattern*" | grep '^+' | grep -v '^+++' || true
            echo '```'
            echo
        fi
    } > "$outfile"
    echo "Generated git history for staged changes in $outfile."

# Handle a specified commit range (including --all)
else
    # If --all was specified, set from_rev to HEAD and to_rev to earliest commit
    if $all_history; then
        to_rev="$(git rev-list --max-parents=0 HEAD | tail -n1)"
        from_rev="HEAD"
    fi
    if [[ -z "$to_rev" ]]; then to_rev="HEAD"; fi
    if [[ -z "$from_rev" ]]; then from_rev="HEAD"; fi
    echo "Using commit range: ${to_rev}^..${from_rev}"
    # Collect commits in chronological order (oldest first)
    if $all_history && ! git rev-parse --verify "${to_rev}^" >/dev/null 2>&1; then
        range_spec="${to_rev}..${from_rev}"
    else
        range_spec="${to_rev}^..${from_rev}"
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
    write_git_history "$outfile" "$(git rev-parse --abbrev-ref HEAD)" "$start_commit" "$end_commit" "$start_date" "$end_date" "${commits[@]}"
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
