#!/bin/sh
# changeish - A POSIX-compliant script to generate commit messages, summaries,
# changelogs, release notes, and announcements from Git history using AI
__VERSION="0.2.0"

set -eu
IFS='\n'

# -------------------------------------------------------------------
# Paths & Defaults
# -------------------------------------------------------------------
# Portable script path resolution (no readlink -f)
SCRIPT_PATH="$0"
case "$SCRIPT_PATH" in
/*) ;; # absolute
*) SCRIPT_PATH="$PWD/$SCRIPT_PATH" ;;
esac
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
PROMPT_DIR="$SCRIPT_DIR/prompts"
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

# Prompts
commit_message_prompt='Task: Provide a concise, commit message for the changes described in the following git diff. Output only the commit message.'
default_summary_prompt='Task: Provide a human-readable summary of the changes described in the following git diff. The summary should be no more than five sentences long. Output only the summary text.'

# -------------------------------------------------------------------
# Helper Functions
# -------------------------------------------------------------------
show_version() {
    printf '%s\n' "$__VERSION"
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

# Parse global flags and detect subcommand/target/pattern

# Parse global flags and detect subcommand/target/pattern
parse_args_og() {
    subcmd=""
    debug=false
    dry_run=false

    # Preserve original arguments for later parsing
    set -- "$@"

    # Early config file parsing
    config_file=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --config-file)
                shift
                if [ $# -gt 0 ]; then
                    config_file="$1"
                    shift
                fi
                ;;
            --config-file=*)
                config_file="${1#--config-file=}"
                shift
                ;;
            *)
                break
                ;;
        esac
        [ -n "$config_file" ] && break
    done

    # Restore original arguments for main parsing
    set -- "$@"

    # -------------------------------------------------------------------
    # Config file handling (early parse)
    # -------------------------------------------------------------------
    printf 'Loading config file: %s\n' "$config_file"

    # Always attempt to source config file if it exists; empty config_file is a valid state.
    if [ -n "$config_file" ] && [ -f "$config_file" ]; then
        # shellcheck disable=SC1090
        . "$config_file"
    elif [ -n "$config_file" ]; then
        printf 'Error: config file "%s" not found.\n' "$config_file"
    fi
    # 1. Subcommand or help/version must be first
    if [ $# -eq 0 ]; then
        printf 'No arguments provided.\n'
        exit 0
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
    message | summary | changelog | release-notes | announce | available-releases | update)
        subcmd=$1
        shift
        ;;
    *)
        echo "First argument must be a subcommand or -h/--help/-v/--version"
        show_help
        exit 1
        ;;
    esac

    printf 'Subcommand: %s\n' "$subcmd"

    # 2. Next arg: target (if present and not option)
    if [ $# -gt 0 ]; then
        case "$1" in
        --current | --staged | --cached)
            if [ "$1" = "--staged" ]; then
                TARGET="--cached"
            else
                TARGET="$1"
            fi
            TARGET=$1
            shift
            ;;
        -*)
            : # skip, no target
            ;;
        *)
            if is_valid_git_range "$1"; then
                TARGET=$1
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
        if [ -z "$PATTERN" ]; then
            PATTERN="$1"
        else
            PATTERN="$PATTERN $1"
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
            shift
            break
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
    if ! command -v ollama >/dev/null 2>&1; then
        [ -n "${debug}" ] && printf 'ollama not found, forcing remote mode (local model unavailable).\n'
        model_provider="remote"
        if [ -z "$api_key" ]; then
            printf 'Error: ollama not found, so remote mode is required, but CHANGEISH_API_KEY is not set.\n' >&2
            model_provider="none"
        fi
        if [ -z "$api_url" ]; then
            printf 'Error: ollama not found, so remote mode is required, but no API URL provided (use --api-url or CHANGEISH_API_URL).\n' >&2
            model_provider="none"
        fi
    elif ! ollama list >/dev/null 2>&1; then
        [ -n "$debug" ] && printf 'ollama daemon not running, forcing remote mode (local model unavailable).\n'
        model_provider="remote"
        if [ -z "$api_key" ]; then
            printf 'Error: ollama daemon not running, so remote mode is required, but CHANGEISH_API_KEY is not set.\n' >&2
            model_provider="none"
        fi
        if [ -z "$api_url" ]; then
            printf 'Error: ollama daemon not running, so remote mode is required, but no API URL provided (use --api-url or CHANGEISH_API_URL).\n' >&2
            model_provider="none"
        fi
    fi

    if [ "$debug" = true ]; then
        echo "Parsed options:"
        echo "  Subcommand: $subcmd"
        echo "  Target: $TARGET"
        echo "  Pattern: $PATTERN"
        echo "  Template Directory: $template_dir"
        echo "  Config File: $config_file"
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

printf 'Parsing arguments...\n'
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
