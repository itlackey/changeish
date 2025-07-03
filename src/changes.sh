#!/bin/sh
# changeish - A POSIX-compliant script to generate commit messages, summaries,
# changelogs, release notes, and announcements from Git history using AI
__VERSION="0.2.0"

set -eu
IFS='\n'

# -------------------------------------------------------------------
# Paths & Defaults
# -------------------------------------------------------------------
# Resolve script directory robustly, whether sourced or executed
# Works in POSIX sh, bash, zsh, dash
get_script_dir() {
    # $1: path to script (may be $0 or ${BASH_SOURCE[0]})
    script="$1"
    case "$script" in
        /*) dir=$(dirname "$script") ;;
        *) dir=$(cd "$(dirname "$script")" 2>/dev/null && pwd) ;;
    esac
    printf '%s\n' "$dir"
}

# Detect if sourced (works in bash, zsh, dash, sh)
_is_sourced=0
# shellcheck disable=SC2292
if [ "${BASH_SOURCE[0]:-}" != "" ] && [ "${BASH_SOURCE[0]:-}" != "$0" ]; then
    _is_sourced=1
elif [ -n "${ZSH_EVAL_CONTEXT:-}" ] && [[ "$ZSH_EVAL_CONTEXT" == *:file ]]; then
    _is_sourced=1
fi

# Use BASH_SOURCE if available, else $0
if [ -n "${BASH_SOURCE[0]:-}" ]; then
    _SCRIPT_PATH="${BASH_SOURCE[0]}"
else
    _SCRIPT_PATH="$0"
fi

SCRIPT_DIR="$(get_script_dir "$_SCRIPT_PATH")"
PROMPT_DIR="$SCRIPT_DIR/prompts"

# shellcheck source=/dev/null
. "$SCRIPT_DIR/helpers.sh"


# TARGET=""
# PATTERN=""

# debug=""
# dry_run=""
# template_dir="$PROMPT_DIR"
# output_file=''
# todo_pattern='*todo*'
# version_file=''

# # Subcommand & templates
# template_name=''
# subcmd=''

# # Model settings
# model=${CHANGEISH_MODEL:-'qwen2.5-coder'}
# model_provider=${CHANGEISH_MODEL_PROVIDER:-'auto'}
# api_model=${CHANGEISH_API_MODEL:-}
# api_url=${CHANGEISH_API_URL:-}
# api_key=${CHANGEISH_API_KEY:-}

# # Changelog & release defaults
# changelog_file='CHANGELOG.md'
# release_file='RELEASE_NOTES.md'
# announce_file='ANNOUNCEMENT.md'
# update_mode='auto'
# section_name='auto'


# -------------------------------------------------------------------
# Helper Functions
# -------------------------------------------------------------------
show_version() {
    printf '%s\n' "${__VERSION}"
}
# Update the script to latest release
run_update() {
    latest_version=$(curl -s https://api.github.com/repos/itlackey/changeish/releases/latest | awk -F'"' '/"tag_name":/ {print $4; exit}')
    printf 'Updating changeish to version %s...\n' "${latest_version}"
    curl -fsSL https://raw.githubusercontent.com/itlackey/changeish/main/install.sh | sh
    printf 'Update complete.\n'
    exit 0
}
show_help() {
    cat <<EOF
Usage: changeish <subcommand> [target] [pattern] [OPTIONS]

Global Options:
  -h, --help            Show help
  -v, --version         Show version
      --verbose         Enable debug output
      --dry-run         Dry run (no writes)
      --template-dir DIR  Prompt templates directory
      --config-file PATH  Shell config to source
      --output-file PATH  Default output file
      --todo-pattern P    Pattern for TODO diff
      --version-file PATH Path to version file

AI/Model Options:
      --model MODEL       Local model
      --model-provider M  auto, local, remote, none
      --api-model MODEL   Remote API model
      --api-url URL       Remote API URL
      --update-mode MODE  Changelog update mode (auto, prepend, append, update, none)
      --section-name NAME Changelog section name

Environment:
  CHANGEISH_API_KEY      API key for remote model
  CHANGEISH_API_URL      API URL for remote model
  CHANGEISH_MODEL        Local model name
  CHANGEISH_MODEL_PROVIDER  Model provider (auto/local/remote/none)

Subcommands:
  message              Generate commit message (default)
  summary              Generate summary
  changelog            Generate or update changelog (--update-mode)
  release-notes        Generate or update release notes (--update-mode)
  announce             Draft announcement
  available-releases   List available script releases
  update               Update this script to latest version

Arguments:
  target               A git commit, commit range, --cached, or --current (optional)
  pattern              A valid git path pattern (optional)

Examples:
  changeish message HEAD~5..HEAD src/
  changeish changelog --cached
EOF
}



# Helper: build prompt file with tag and content
build_prompt_file() {
    tag="$1"
    content_file="$2"
    prompt_file="$3"
    printf '%s\n\n<<%s>>\n' "$tag" "$tag" >"$prompt_file"
    cat "$content_file" >>"$prompt_file"
    printf '<<%s>>' "$tag" >>"$prompt_file"
}

# Enable debug mode if requested
if [ -n "${debug}" ]; then
    set -x
fi

# # -------------------------------------------------------------------
# # Subcommand Implementations
# # -------------------------------------------------------------------

# Portable mktemp: fallback if mktemp not available
portable_mktemp() {
    if command -v mktemp >/dev/null 2>&1; then
        mktemp
    else
        TMP="${TMPDIR-/tmp}"
        # Use date +%s and $$ for uniqueness
        echo "$TMP/tmp.$$.$(date +%s)"
    fi
}

summarize_target() {
    target="$1"
    prompt_template="$2"
    summaries_file="$3"
    [ -n "$debug" ] && echo "DEBUG: summaries_file='$summaries_file', target='$target'"
    if [ "$target" = "--current" ] || [ "$target" = "--cached" ] || [ -z "$target" ]; then
        summarize_commit "$target" "$prompt_template" "$summaries_file"
        printf '\n\n' >>"$summaries_file"
    elif git rev-parse --verify "$target" >/dev/null 2>&1 && [ "$(git rev-list --count "$target")" = "1" ]; then
        summarize_commit "$target" "$prompt_template" "$summaries_file"
        printf '\n\n' >>"$summaries_file"
    else
        git rev-list --reverse "$target" | while IFS= read -r commit; do
            summarize_commit "$commit" "$prompt_template" "$summaries_file"
            printf '\n\n' >>"$summaries_file"
        done
    fi
}

summarize_commit() {
    commit="$1"
    prompt_template="$2"
    out_file="$3"
    hist=$(portable_mktemp)
    pr=$(portable_mktemp)
    [ -n "$debug" ] && printf "DEBUG: summarize_commit commit='%s', hist='%s', prompt file='%s'\n" "$commit" "$hist" "$pr" >&2
    build_history "$hist" "$commit" "$todo_pattern"
    printf '%s\n\n<<GIT_HISTORY>>\n' "$prompt_template" >"$pr"
    cat "$hist" >>"$pr"
    printf '<<GIT_HISTORY>>' >>"$pr"
    res=$(generate_response "$pr")
    rm -f "$hist" "$pr"
    printf '%s\n' "$res" >>"$out_file"
}

generate_from_summaries() {
    header="$1"
    summaries_file="$2"
    outfile="$3"
    pr=$(portable_mktemp)
    [ -n "$debug" ] && echo "DEBUG: generate_from_summaries header='$header', summaries='$summaries_file', output='$outfile'" >&2
    printf '%s\n\n<<COMMIT_SUMMARIES>>\n' "$header" >"$pr"
    cat "$summaries_file" >>"$pr"
    printf '<<COMMIT_SUMMARIES>>' >>"$pr"
    res=$(generate_response "$pr")
    rm -f "$pr"
    if [ -z "$dry_run" ]; then
        printf '%s\n' "$res" >"$outfile"
        printf 'Document written to %s\n' "$outfile"
    else
        printf '%s\n' "$res"
        printf 'Dry run: would write to %s\n' "$outfile"
    fi
}

cmd_message() {
    commit_id="${1:-"--current"}"
    [ -n "$debug" ] && printf 'Generating commit message for %s...\n' "${commit_id}"

    # If the target is not the working tree or staged changes, return the message for the commit
    if [ -z "${commit_id}" ]; then
        printf 'Error: No commit ID or range specified for message generation.\n' >&2
        exit 1
    elif [ "$commit_id" != "--current" ] && [ "$commit_id" != "--cached" ]; then
        # Handle commit ranges (e.g., HEAD~3..HEAD)
        if echo "$commit_id" | grep -q '\.\.'; then
            if ! git rev-list "$commit_id" >/dev/null 2>&1; then
                printf 'Error: Invalid commit range: %s\n' "$commit_id" >&2
                exit 1
            fi
            git log --reverse --pretty=%B "$commit_id"
            exit 0
        else
            if ! git rev-parse --verify "$commit_id" >/dev/null 2>&1; then
                printf 'Error: Invalid commit ID: %s\n' "$commit_id" >&2
                exit 1
            fi
            git log -1 --pretty=%B "$commit_id"
            exit 0
        fi
    fi

    hist=$(portable_mktemp)
    build_history "$hist" "$commit_id" "$todo_pattern"
    pr=$(portable_mktemp)
    printf '%s\n\n<<GIT_HISTORY>>\n' "$commit_message_prompt" >"$pr"
    cat "$hist" >>"$pr"
    printf '<<GIT_HISTORY>>' >>"$pr"
    [ -n "$debug" ] && printf 'Debug: Generated prompt file %s\n' "$pr"
    res=$(generate_response "$pr")
    rm -f "$hist" "$pr"
    if [ -n "$output_file" ]; then
        [ -z "$dry_run" ] && printf '%s' "$res" >"$output_file"
        printf 'Message written to %s\n' "$output_file"
    else printf '%s\n' "$res"; fi
}

cmd_summary() {
    prompt="$default_summary_prompt"
    summaries_file=$(portable_mktemp)
    summarize_target "$TARGET" "$prompt" "$summaries_file"
    if [ -n "$output_file" ]; then
        if [ -z "$dry_run" ]; then
            cat "$summaries_file" >"$output_file"
        fi
        printf 'Summary written to %s\n' "$output_file"
    else
        cat "$summaries_file"
    fi
    rm -f "$summaries_file"
}

cmd_release_notes() {
    version=$(get_current_version)
    prompt="Write release notes for version $version based on these summaries:"
    summaries_file=$(portable_mktemp)
    summarize_target "$TARGET" "$prompt" "$summaries_file"
    generate_from_summaries "Release notes for version $version" "$summaries_file" "${output_file:-$release_file}"
    rm -f "$summaries_file"
}

cmd_announce() {
    version=$(get_current_version)
    prompt="Write a blog-style announcement for version $version from these commit summaries:"
    summaries_file=$(portable_mktemp)
    summarize_target "$TARGET" "$prompt" "$summaries_file"
    generate_from_summaries "Announcement for version $version" "$summaries_file" "${output_file:-$announce_file}"
    rm -f "$summaries_file"
}

cmd_changelog() {
    version=$(get_current_version)
    prompt="Write a changelog for version $version based on these summaries:"
    summaries_file=$(portable_mktemp)
    summarize_target "$TARGET" "$prompt" "$summaries_file"
    generate_from_summaries "Changelog for version $version" "$summaries_file" "${output_file:-$changelog_file}"
    rm -f "$summaries_file"
}

get_current_version() {
    printf '%s\n' "$__VERSION"
}

if [ "${_is_sourced}" -eq 0 ]; then
    parse_args "$@"

    # Dispatch logic
    case "${subcmd}" in
    summary) cmd_summary ;;
    release-notes) cmd_release_notes ;;
    announce) cmd_announce ;;
    message) cmd_message "${TARGET}" ;;
    changelog) cmd_changelog ;;
    help)
        show_help
        exit 0
        ;;
    available-releases)
        get_available_releases
        ;;
    update)
        run_update
        ;;
    *) cmd_message "${TARGET}" ;;
    esac
fi
