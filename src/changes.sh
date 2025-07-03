#!/bin/sh
# changeish - A POSIX-compliant script to generate commit messages, summaries,
# changelogs, release notes, and announcements from Git history using AI
# Version: 0.2.0

set -eu
IFS='\n'

# Parse --config-file early to set config_file before sourcing
early_config_file=""
prev_arg=""
for arg in "$@"; do
    case "$arg" in
    --config-file)
        prev_arg="config_file"
        ;;
    --config-file=*)
        early_config_file=$(printf '%s' "$arg" | sed 's/^--config-file=//')
        break
        ;;
    *)
        if [ "$prev_arg" = "config_file" ]; then
            early_config_file="$arg"
            break
        fi
        ;;
    esac
done
config_file=${early_config_file:-$config_file}

# Always attempt to source config file if it exists; empty config_file is a valid state.
if [ -f "${config_file}" ]; then
    # shellcheck disable=SC1090
    . "${config_file}"
elif [ -n "${config_file}" ]; then
    printf 'Error: config file "%s" not found.\n' "${config_file}" >&2
    exit 1
fi

# -------------------------------------------------------------------
# Paths & Defaults
# -------------------------------------------------------------------
SCRIPT_PATH=$(readlink -f "$0")
SCRIPT_DIR=$(dirname "${SCRIPT_PATH}")
PROMPT_DIR=${SCRIPT_DIR}/prompts
. "${SCRIPT_DIR}/helpers.sh"

TARGET=""
PATTERN=""

debug=false
dry_run=false
template_dir=${PROMPT_DIR}
config_file="${PWD}/.env"
output_file=''
todo_pattern='*todo*'
version_file=''

# Subcommand & templates
template_name=''
subcmd='message'

# Model settings
model=${CHANGEISH_MODEL:-'qwen2.5-coder'}
model_provider=${CHANGEISH_MODEL_PROVIDER:-'auto'}
api_model=${CHANGEISH_API_MODEL:-}
api_url=${CHANGEISH_API_URL:-}
api_key=${CHANGEISH_API_KEY:-}

# Changelog & release defaults
changelog_file='CHANGELOG.md'
release_file='RELEASE_NOTES.md'
announce_file='ANNOUNCEMENT.md'
update_mode='auto'
section_name='auto'

# Prompts
commit_message_prompt='Task: Provide a concise, commit message for the changes described in the following git diff. Output only the commit message.'
default_summary_prompt='Task: Provide a concise, human-readable summary (2-3 sentences) of the changes described in the following git diff. Output only the summary text.'

# -------------------------------------------------------------------
# Helper Functions
# -------------------------------------------------------------------
show_version() {
    awk 'NR==3{sub(/^# Version: /, ""); print; exit}' "$0"
}

show_help() {
    cat <<EOF
Usage: changeish [GLOBAL OPTIONS] <subcommand> [target] [pattern] [OPTIONS]

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
      --model MODEL       Local model
      --model-provider M  auto, local, remote, none
      --api-model MODEL   Remote API model
      --api-url URL       Remote API URL
      --update-mode MODE  Changelog update mode (auto, prepend, append, update, none)
      --section-name NAME Changelog section name

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

is_valid_git_range() {
    git rev-list "$1" >/dev/null 2>&1
}

is_valid_pattern() {
    git ls-files --error-unmatch "$1" >/dev/null 2>&1
}

# Parse global flags and detect subcommand/target/pattern
parse_args() {
    subcmd=""
    debug=false
    dry_run=false
    # 1. Subcommand or help/version must be first
    if [ $# -eq 0 ]; then
        show_help
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
        echo "First argument must be a subcommand or -h/--help/-v/--version" >&2
        show_help
        exit 1
        ;;
    esac
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

# -------------------------------------------------------------------
# Subcommand Implementations
# -------------------------------------------------------------------
# run_message() {
#     hist=$(mktemp)
#     build_history "$hist"
#     pr=$(mktemp)
#     printf '%s\n\n<<GIT_HISTORY>>\n' "$commit_message_prompt" >"$pr"
#     cat "$hist" >>"$pr"
#     printf '<<GIT_HISTORY>>' >>"$pr"
#     res=$(generate_response "$pr")
#     rm -f "$hist" "$pr"
#     if [ -n "$output_file" ]; then
#         [ "$dry_run" = false ] && printf '%s' "$res" >"$output_file"
#         printf 'Message written to %s\n' "$output_file"
#     else printf '%s\n' "$res"; fi
# }

# run_summary() {
#     hist=$(mktemp)
#     build_history "$hist"
#     pr=$(mktemp)
#     printf '%s\n\n<<GIT_HISTORY>>\n' "$summary_prompt" >"$pr"
#     cat "$hist" >>"$pr"
#     printf '<<GIT_HISTORY>>' >>"$pr"
#     res=$(generate_response "$pr")
#     rm -f "$hist" "$pr"
#     if [ -n "$output_file" ]; then
#         [ "$dry_run" = false ] && printf '%s' "$res" >"$output_file"
#         printf 'Summary written to %s\n' "$output_file"
#     else printf '%s\n' "$res"; fi
# }

# run_changelog() {
#     hist=$(mktemp)
#     build_history "$hist"
#     cat "$hist"
#     pr=$(mktemp)
#     version=$(get_current_version)
#     header="Write a changelog for version $version from the following git history."
#     generate_prompt_file "$pr" 'changelog.tpl' "$header" "$hist"
#     res=$(generate_response "$pr")
#     rm -f "$hist" "$pr"
#     out=${output_file:-$changelog_file}
#     if [ "$update_mode" != 'none' ]; then
#         [ "$dry_run" = false ] && update_changelog "$out" "$res" "$version" "$update_mode"
#     fi
#     printf 'Changelog updated in %s\n' "$out"
# }

# run_release_notes() {
#     hist=$(mktemp)
#     build_history "$hist"
#     pr=$(mktemp)
#     version=$(get_current_version)
#     header="Write release notes for version $version from the following git history."
#     generate_prompt_file "$pr" 'release.tpl' "$header" "$hist"
#     res=$(generate_response "$pr")
#     rm -f "$hist" "$pr"
#     out=${output_file:-$release_file}
#     if [ "$update_mode" != 'none' ]; then [ "$dry_run" = false ] && printf '%s\n' "$res" >>"$out"; fi
#     printf 'Release notes updated in %s\n' "$out"
# }

# run_announce() {
#     hist=$(mktemp)
#     build_history "$hist"
#     pr=$(mktemp)
#     header="Write a blog-style announcement for version $(get_current_version) from the following git history."
#     generate_prompt_file "$pr" 'announce.tpl' "$header" "$hist"
#     res=$(generate_response "$pr")
#     rm -f "$hist" "$pr"
#     out=${output_file:-$announce_file}
#     [ "$dry_run" = false ] && printf '%s\n' "$res" >"$out"
#     printf 'Announcement written to %s\n' "$out"
# }

# Helper to collect summaries for a set of commits and pass to a callback
create_summary_file() {
    diff_spec="$1"
    sum_prompt_file="$2"
    summaries_doc="$3"

    summary_prompt=$(cat "$sum_prompt_file"):-"$default_summary_prompt"

    # If TARGET is --current, --staged, or empty, just run once
    if [ "$diff_spec" = "--current" ] || [ "$diff_spec" = "--staged" ] || [ -z "$diff_spec" ]; then
        get_summary_for_commit "$diff_spec" "$summary_prompt" >>"$summaries_doc"
    elif git rev-parse --verify "$diff_spec" >/dev/null 2>&1 && [ "$(git rev-list --count $diff_spec 2>/dev/null)" -eq 1 ]; then
        get_summary_for_commit "$diff_spec" "$summary_prompt" >>"$summaries_doc"
    else
        for commit in $(git rev-list --reverse "$diff_spec"); do
            get_summary_for_commit "$commit" "$summary_prompt" >>"$summaries_doc"
        done
    fi
}

get_summary_for_commit() {
    commit_id="$1"
    summary_prompt="$2"

    hist=$(mktemp)
    build_history "$hist" "$commit_id" "$todo_pattern"
    pr=$(mktemp)
    printf '%s\n\n<<GIT_HISTORY>>\n' "$summary_prompt" >"$pr"
    cat "$hist" >>"$pr"
    printf '<<GIT_HISTORY>>' >>"$pr"
    res=$(generate_response "$pr")
    rm -f "$hist" "$pr"
    printf '%s\n' "$res"
}

# Helper to collect summaries for a set of commits and pass to a callback
run_with_summaries() {
    callback_func=$1
    # Create a temp file to collect summaries
    summaries_doc=$(mktemp)
    # If TARGET is --current, --staged, or empty, just run once
    if [ "$TARGET" = "--current" ] || [ "$TARGET" = "--staged" ] || [ -z "$TARGET" ]; then
        run_summary_with_commit "$TARGET" >>"$summaries_doc"
    elif git rev-parse --verify "$TARGET" >/dev/null 2>&1 && [ "$(git rev-list --count $TARGET 2>/dev/null)" -eq 1 ]; then
        run_summary_with_commit "$TARGET" >>"$summaries_doc"
    else
        for commit in $(git rev-list --reverse "$TARGET"); do
            run_summary_with_commit "$commit" >>"$summaries_doc"
        done
    fi
    "$callback_func" "$summaries_doc"
    rm -f "$summaries_doc"
}

run_release_notes_with_summaries() {
    summaries_doc="$1"
    pr=$(mktemp)
    version=$(get_current_version)
    header="Write release notes for version $version from the following commit summaries."
    printf '%s\n\n<<COMMIT_SUMMARIES>>\n' "$header" >"$pr"
    cat "$summaries_doc" >>"$pr"
    printf '<<COMMIT_SUMMARIES>>' >>"$pr"
    res=$(generate_response "$pr")
    rm -f "$pr"
    out=${output_file:-$release_file}
    if [ "$update_mode" != 'none' ]; then [ "$dry_run" = false ] && printf '%s\n' "$res" >>"$out"; fi
    printf 'Release notes updated in %s\n' "$out"
}

run_announce_with_summaries() {
    summaries_doc="$1"
    pr=$(mktemp)
    version=$(get_current_version)
    header="Write a blog-style announcement for version $version from the following commit summaries."
    printf '%s\n\n<<COMMIT_SUMMARIES>>\n' "$header" >"$pr"
    cat "$summaries_doc" >>"$pr"
    printf '<<COMMIT_SUMMARIES>>' >>"$pr"
    res=$(generate_response "$pr")
    rm -f "$pr"
    out=${output_file:-$announce_file}
    [ "$dry_run" = false ] && printf '%s\n' "$res" >"$out"
    printf 'Announcement written to %s\n' "$out"
}

# -------------------------------------------------------------------
# Main Execution
# -------------------------------------------------------------------

parse_args "$@"

# Determine ollama/remote mode once before parsing args
if ! command -v ollama >/dev/null 2>&1; then
    [ "${debug:-false}" = "true" ] && printf 'ollama not found, forcing remote mode (local model unavailable).\n'
    model_provider="remote"
    if [ -z "${api_key}" ]; then
        printf 'Error: ollama not found, so remote mode is required, but CHANGEISH_API_KEY is not set.\n' >&2
        model_provider="none"
        printf 'Warning: Remote mode (and changelog generation) disabled because CHANGEISH_API_KEY is not set.\n' >&2
    fi
    if [ -z "${api_url}" ]; then
        printf 'Error: ollama not found, so remote mode is required, but no API URL provided (use --api-url or CHANGEISH_API_URL).\n' >&2
        model_provider="none"
        printf 'Warning: Changelog generation disabled because no API URL provided.\n' >&2
    fi
elif ! ollama list >/dev/null 2>&1; then
    [ "${debug:-false}" = "true" ] && printf 'ollama daemon not running, forcing remote mode (local model unavailable).\n'
    model_provider="remote"
    if [ -z "${api_key}" ]; then
        printf 'Error: ollama daemon not running, so remote mode is required, but CHANGEISH_API_KEY is not set.\n' >&2
        model_provider="none"
        printf 'Warning: Changelog generation disabled because CHANGEISH_API_KEY is not set.\n' >&2
    fi
    if [ -z "${api_url}" ]; then
        printf 'Error: ollama daemon not running, so remote mode is required, but no API URL provided (use --api-url or CHANGEISH_API_URL).\n' >&2
        model_provider="none"
        printf 'Warning: Changelog generation disabled because no API URL provided.\n' >&2
    fi
fi

# Dispatch
run_with_commits() {
    [ "$debug" = true ] && printf 'Debug: Running with commits...%s : %s\n' "$1" "$TARGET"

    run_func=$1

    # Validation for --current and --staged
    if [ "$TARGET" = "--current" ]; then
        if ! git diff --quiet -- .; then
            eval "$run_func" "$TARGET"
        else
            printf 'No changes in the working tree to process.\n' >&2
            exit 1
        fi
    elif [ "$TARGET" = "--cached" ]; then
        if ! git diff --cached --quiet -- .; then
            eval "$run_func" "$TARGET"
        else
            printf 'No staged changes to process.\n' >&2
            exit 1
        fi
    # If TARGET is a single commit, run once
    elif git rev-parse --verify "$TARGET" >/dev/null 2>&1 && [ "$(git rev-list --count $TARGET 2>/dev/null)" -eq 1 ]; then
        eval "$run_func" "$TARGET"
    # If TARGET is a range or multi-commit, loop through each commit
    else
        for commit in $(git rev-list --reverse "$TARGET"); do
            eval "$run_func" "$commit"
        done
    fi
}

run_message_with_commit() {
    [ "$debug" = "true" ] && printf 'Generating commit message for %s...\n' "$1"
    commit_id="$1"
    hist=$(mktemp)
    build_history "$hist" "$commit_id" "$todo_pattern"
    pr=$(mktemp)
    printf '%s\n\n<<GIT_HISTORY>>\n' "${commit_message_prompt}" >"$pr"
    cat "$hist" >>"$pr"
    printf '<<GIT_HISTORY>>' >>"$pr"

    [ "$debug" = true ] && printf 'Debug: Generated prompt file %s\n' "$pr"

    res=$(generate_response "$pr")
    rm -f "$hist" "$pr"
    if [ -n "$output_file" ]; then
        [ "$dry_run" = false ] && printf '%s' "$res" >"$output_file"
        printf 'Message written to %s\n' "$output_file"
    else printf '%s\n' "$res"; fi

}

run_summary_with_commit() {
    commit_id="$1"
    hist=$(mktemp)
    build_history "$hist" "$commit_id" "$todo_pattern"
    pr=$(mktemp)
    printf '%s\n\n<<GIT_HISTORY>>\n' "$summary_prompt" >"$pr"
    cat "$hist" >>"$pr"
    printf '<<GIT_HISTORY>>' >>"$pr"
    res=$(generate_response "$pr")
    rm -f "$hist" "$pr"
    if [ -n "$output_file" ]; then
        [ "$dry_run" = false ] && printf '%s' "$res" >"$output_file"
        printf 'Summary written to %s\n' "$output_file"
    else printf '%s\n' "$res"; fi
}

run_changelog_with_commit() {
    commit_id="$1"
    hist=$(mktemp)
    build_history "$hist" "$commit_id" "$todo_pattern"
    pr=$(mktemp)
    version=$(get_current_version)
    header="Write a changelog for version $version from the following git history."
    generate_prompt_file "$pr" 'changelog.tpl' "$header" "$hist"
    res=$(generate_response "$pr")
    rm -f "$hist" "$pr"
    out=${output_file:-$changelog_file}
    if [ "$update_mode" != 'none' ]; then
        [ "$dry_run" = false ] && update_changelog "$out" "$res" "$version" "$update_mode"
    fi
    printf 'Changelog updated in %s\n' "$out"
}

run_release_notes_with_commit() {
    commit_id="$1"
    hist=$(mktemp)
    build_history "$hist" "$commit_id" "$todo_pattern"
    pr=$(mktemp)
    version=$(get_current_version)
    header="Write release notes for version $version from the following git history."
    generate_prompt_file "$pr" 'release.tpl' "$header" "$hist"
    res=$(generate_response "$pr")
    rm -f "$hist" "$pr"
    out=${output_file:-$release_file}
    if [ "$update_mode" != 'none' ]; then [ "$dry_run" = false ] && printf '%s\n' "$res" >>"$out"; fi
    printf 'Release notes updated in %s\n' "$out"
}

run_announce_with_commit() {
    commit_id="$1"
    hist=$(mktemp)
    build_history "$hist" "$commit_id" "$todo_pattern"
    pr=$(mktemp)
    header="Write a blog-style announcement for version $(get_current_version) from the following git history."
    generate_prompt_file "$pr" 'announce.tpl' "$header" "$hist"
    res=$(generate_response "$pr")
    rm -f "$hist" "$pr"
    out=${output_file:-$announce_file}
    [ "$dry_run" = false ] && printf '%s\n' "$res" >"$out"
    printf 'Announcement written to %s\n' "$out"
}

case ${subcmd} in
update) run_update ;;
available-releases) run_available_releases ;;
help) show_help ;;
message) run_with_commits run_message_with_commit ;;
summary) create_summary_file ;;
release-notes) run_with_summaries run_release_notes_with_summaries ;;
announce) run_with_summaries run_announce_with_summaries ;;
changelog) run_with_commits run_changelog_with_commit ;;
*) show_help ;;
esac
