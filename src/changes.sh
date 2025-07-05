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
PROMPT_DIR="${SCRIPT_DIR}/../prompts"

# shellcheck source=./src/helpers.sh
. "${SCRIPT_DIR}/helpers.sh"


TARGET=""
PATTERN=""

config_file=""
is_config_loaded=false
debug=""
dry_run=""
template_dir="$PROMPT_DIR"
output_file=''
todo_pattern='*todo*'
version_file=''

# Subcommand & templates
subcmd=''
update_mode='auto'
section_name='auto'

# Model settings
model=${CHANGEISH_MODEL:-'qwen2.5-coder'}
model_provider=${CHANGEISH_MODEL_PROVIDER:-'auto'}
api_model=${CHANGEISH_API_MODEL:-}
api_url=${CHANGEISH_API_URL:-}
api_key=${CHANGEISH_API_KEY:-}

# Changelog & release defaults
changelog_file='CHANGELOG.md'
release_notes_file='RELEASE_NOTES.md'
announce_file='ANNOUNCEMENT.md'

# Parse global flags and detect subcommand/target/pattern
parse_args() {

    # Restore original arguments for main parsing
    set -- "$@"

    # 1. Subcommand or help/version must be first
    if [ $# -eq 0 ]; then
        printf 'No arguments provided.\n'
        exit 1
    fi
    case "$1" in
    -h | --help | help)
        show_help
        exit 0
        ;;
    -v | --version)
        show_version
        exit 0
        ;;
    message | summary | changelog | release-notes | announcement | available-releases | update)
        subcmd=$1
        shift
        ;;
    *)
        echo "First argument must be a subcommand or -h/--help/-v/--version"
        show_help
        exit 1
        ;;
    esac

    # Preserve original arguments for later parsing
    set -- "$@"

    # Early config file parsing (handle both --config-file and --config-file=)
    config_file="${PWD}/.env"
    i=1
    while [ $i -le $# ]; do
        eval "arg=\${$i}"
        case "$arg" in
        --config-file)
            next=$((i + 1))
            if [ $next -le $# ]; then
                eval "config_file=\${$next}"
                [ -n "${debug}" ] && printf 'Debug: Found config file argument: --config-file %s\n' "${config_file}"
                break
            else
                printf 'Error: --config-file requires a file path argument.\n'
                exit 1
            fi
            ;;
        --config-file=*)
            config_file="${arg#--config-file=}"
            [ -n "${debug}" ] && printf 'Debug: Found config file argument: --config-file=%s\n' "${config_file}"
            break
            ;;
        *)
            # Not a config file argument, continue parsing
            ;;
        esac
        i=$((i + 1))
    done

    # -------------------------------------------------------------------
    # Config file handling (early parse)
    # -------------------------------------------------------------------
    [ -n "$debug" ] && printf 'Loading config file: %s\n' "$config_file"

    # Always attempt to source config file if it exists; empty config_file is a valid state.
    if [ -n "$config_file" ] && [ -f "$config_file" ]; then
        # shellcheck disable=SC1090
        . "$config_file"
        is_config_loaded=true
        [ -n "$debug" ] && cat "${config_file}"
        [ -n "$debug" ] && printf '\nLoaded config file: %s\n' "$config_file"

        # Override defaults with config file values
        model=${CHANGEISH_MODEL:-'qwen2.5-coder'}
        model_provider=${CHANGEISH_MODEL_PROVIDER:-'auto'}
        api_model=${CHANGEISH_API_MODEL:-}
        api_url=${CHANGEISH_API_URL:-}
        api_key=${CHANGEISH_API_KEY:-}

    elif [ -n "${config_file}" ]; then
        printf 'Error: config file "%s" not found.\n' "$config_file"
    fi

    # 2. Next arg: target (if present and not option)
    if [ $# -gt 0 ]; then
        case "$1" in
        --current | --staged | --cached)
            if [ "$1" = "--staged" ]; then
                TARGET="--cached"
            else
                TARGET="$1"
            fi
            shift
            ;;
        -*)
            : # skip, no target
            ;;
        *)
            # Check for commit range (e.g., v1..v2)
            if echo "$1" | grep -q '\.\.'; then
                TARGET="$1"
                shift
            elif is_valid_git_range "$1"; then
                TARGET="$1"
                shift
            fi
            # else: do not shift, let it fall through to pattern parsing
            ;;
        esac
    fi

    if [ -z "$TARGET" ]; then
        # If no target specified, default to current working tree
        TARGET="--current"
    fi
    # 3. Collect all non-option args as pattern (until first option or end)
    PATTERN=""
    while [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; do
        if [ -z "${PATTERN}" ]; then
            PATTERN="$1"
        else
            PATTERN="${PATTERN} $1"
        fi
        shift
    done

    # 4. Remaining args: global options
    while [ $# -gt 0 ]; do
        case "$1" in
        --verbose)
            debug=true
            shift
            ;;
        --dry-run)
            dry_run=true
            shift
            ;;
        --template-dir)
            template_dir=$2
            shift 2
            ;;
        --config-file)
            config_file=$2
            shift 2
            ;;
        --output-file)
            output_file=$2
            shift 2
            ;;
        --todo-pattern)
            todo_pattern=$2
            shift 2
            ;;
        --version-file)
            version_file=$2
            shift 2
            ;;
        --model)
            model=$2
            shift 2
            ;;
        --model-provider)
            model_provider=$2
            shift 2
            ;;
        --api-model)
            api_model=$2
            shift 2
            ;;
        --api-url)
            api_url=$2
            shift 2
            ;;
        --update-mode)
            update_mode=$2
            shift 2
            ;;
        --section-name)
            section_name=$2
            shift 2
            ;;
        --)
            echo "Unknown option or argument: $1" >&2
            show_help
            exit 1
            ;;
        --*)
            echo "Unknown option or argument: $1" >&2
            show_help
            exit 1
            ;;
        *)
            echo "Unknown argument: $1" >&2
            show_help
            exit 1
            ;;
        esac
    done

    # Determine ollama/remote mode once before parsing args
    if [ "${model_provider}" = "auto" ] || [ "${model_provider}" = "local" ]; then
        if ! command -v ollama >/dev/null 2>&1; then
            [ -n "${debug}" ] && printf 'Debug: ollama not found, forcing remote mode (local model unavailable).\n'
            model_provider="remote"
            if [ -z "${api_key}" ]; then
                [ -n "${debug}" ] && printf 'Warning: ollama not found, so remote mode is required, but CHANGEISH_API_KEY is not set.\n' >&2
                model_provider="none"
            fi
            if [ -z "${api_url}" ]; then
                [ -n "${debug}" ] && printf 'Warning: ollama not found, so remote mode is required, but no API URL provided (use --api-url or CHANGEISH_API_URL).\n' >&2
                model_provider="none"
            fi
        fi
    fi

    [ "${model_provider}" = "none" ] && printf 'Warning: Model provider set to "none", no model will be used.\n' >&2

    if [ "$debug" = true ]; then
        echo "Parsed options:"
        echo "  Debug: $debug"
        echo "  Dry Run: $dry_run"
        echo "  Subcommand: $subcmd"
        echo "  Target: $TARGET"
        echo "  Pattern: $PATTERN"
        echo "  Template Directory: $template_dir"
        echo "  Config File: $config_file"
        echo "  Config Loaded: $is_config_loaded"
        echo "  Output File: $output_file"
        echo "  TODO Pattern: $todo_pattern"
        echo "  Version File: $version_file"
        echo "  Model: $model"
        echo "  Model Provider: $model_provider"
        echo "  API Model: $api_model"
        echo "  API URL: $api_url"
        echo "  Update Mode: $update_mode"
        echo "  Section Name: $section_name"
    fi
}
# -------------------------------------------------------------------
# Helper Functions
# -------------------------------------------------------------------
show_version() {
    printf '%s\n' "${__VERSION}"
}
# Show all available release tags
get_available_releases() {
    curl -s https://api.github.com/repos/itlackey/changeish/releases | awk -F'"' '/"tag_name":/ {print $4}'
    exit 0
}
# Update the script to a specific release version (or latest if not specified)
run_update() {
    version="${1:-latest}"
    if [ "$version" = "latest" ]; then
        latest_version=$(get_available_releases | head -n 1)
        printf 'Updating changeish to version %s...\n' "${latest_version}"
        curl -fsSL https://raw.githubusercontent.com/itlackey/changeish/main/install.sh | sh -- --version "${latest_version}"
    else
        printf 'Updating changeish to version %s...\n' "${version}"
        curl -fsSL "https://raw.githubusercontent.com/itlackey/changeish/main/install.sh" | sh -- --version "${version}"
    fi
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

Output Options:
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
  announcement             Draft announcement
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

# # -------------------------------------------------------------------
# # Subcommand Implementations
# # -------------------------------------------------------------------

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
            [ -n "$debug" ] && printf 'Processing commit range: %s\n' "$commit_id"
            if ! git rev-list "$commit_id" >/dev/null 2>&1; then
                printf 'Error: Invalid commit range: %s\n' "$commit_id" >&2
                exit 1
            fi
            git log --reverse --pretty=%B "$commit_id"
            exit 0
        else
        [ -n "$debug" ] && printf 'Processing single commit: %s\n' "$commit_id"
            if ! git rev-parse --verify "$commit_id" >/dev/null 2>&1; then
                printf 'Error: Invalid commit ID: %s\n' "$commit_id" >&2
                exit 1
            fi
            git log -1 --pretty=%B "$commit_id" | sed '${/^$/d;}'
            exit 0
        fi
    fi
    hist=$(portable_mktemp)
    build_history "$hist" "$commit_id" "$todo_pattern" "$PATTERN"
    [ -n "$debug" ] && printf 'Debug: Generated history file %s\n' "$hist"
    pr=$(portable_mktemp)
    printf '%s' "$(build_prompt "${PROMPT_DIR}/commit_message_prompt.md" "$hist")" >"$pr"
    [ -n "$debug" ] && printf 'Debug: Generated prompt file %s\n' "$pr"
    res=$(generate_response "$pr")
    rm -f "$hist" "$pr"
   
    printf '%s\n' "$res";
}

cmd_summary() {
    summaries_file=$(portable_mktemp)
    summarize_target "${TARGET}" "${summaries_file}"
    if [ -n "${output_file}" ]; then
        if [ "${dry_run}" != "true" ]; then
            cp "${summaries_file}" "${output_file}"
            printf 'Summary written to %s\n' "${output_file}"
        else
            cat "${summaries_file}"
        fi
    else
        cat "${summaries_file}"
    fi
    rm -f "${summaries_file}"
}

cmd_release_notes() {
    summaries_file=$(portable_mktemp)
    summarize_target "${TARGET}" "${summaries_file}"
    prompt_file_name="${PROMPT_DIR}/release_notes_prompt.md"
    tmp_prompt_file=$(portable_mktemp)
    build_prompt "${prompt_file_name}" "${summaries_file}" > "${tmp_prompt_file}"
    generate_from_prompt "${tmp_prompt_file}" "${output_file:-${release_notes_file}}"
    rm -f "${summaries_file}"
    rm -f "${tmp_prompt_file}"
}

cmd_announcement() {
    summaries_file=$(portable_mktemp)
    summarize_target "${TARGET}" "${summaries_file}"
    cat "${summaries_file}"
    prompt_file_name="${PROMPT_DIR}/announcement_prompt.md"
    tmp_prompt_file=$(portable_mktemp)
    build_prompt "${prompt_file_name}" "${summaries_file}" > "${tmp_prompt_file}"
    generate_from_prompt "${tmp_prompt_file}" "${output_file:-${announce_file}}"
    rm -f "${summaries_file}"
    rm -f "${tmp_prompt_file}"
}

cmd_changelog() {
    # prompt="Write a changelog for version $version based on these summaries:"
    summaries_file=$(portable_mktemp)
    summarize_target "$TARGET" "${summaries_file}"
    prompt_file_name="${PROMPT_DIR}/changelog_prompt.md"
    tmp_prompt_file=$(portable_mktemp)
    build_prompt "${prompt_file_name}" "${summaries_file}" > "${tmp_prompt_file}"

    # TODO: add support for --update-mode
    generate_from_prompt "${tmp_prompt_file}" "${output_file:-${changelog_file}}"
    rm -f "${summaries_file}"
    rm -f "${tmp_prompt_file}"
}


if [ "${_is_sourced}" -eq 0 ]; then
    parse_args "$@"

    # # Enable debug mode if requested
    # if [ -n "${debug}" ]; then
    #     set -x
    # fi

    # Dispatch logic
    case "${subcmd}" in
    summary) cmd_summary ;;
    release-notes) cmd_release_notes ;;
    announcement) cmd_announcement ;;
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
        run_update "latest"
        ;;
    *) cmd_message "${TARGET}" ;;
    esac
fi
