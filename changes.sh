#!/bin/sh
# changeish - A POSIX-compliant script to generate commit messages, summaries,
# changelogs, release notes, and announcements from Git history using AI
# Version: 0.2.0

set -eu
IFS='\n'

# -------------------------------------------------------------------
# Paths & Defaults
# -------------------------------------------------------------------
SCRIPT_PATH=$(readlink -f "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
PROMPT_DIR=$SCRIPT_DIR/prompts

debug=false
dry_run=false
template_dir=$PROMPT_DIR
config_file=''
output_file=''
todo_pattern='*todo*'
version_file=''

# Subcommand & templates
template_name=''
subcmd='message'

# Model settings
model='qwen2.5-coder'
model_provider='auto'
api_model=''
api_url=''
remote=false

# Changelog & release defaults
changelog_file='CHANGELOG.md'
release_file='RELEASE_NOTES.md'
announce_file='ANNOUNCEMENT.md'
update_mode='auto'
section_name='auto'

# Prompts
commit_message_prompt='Task: Provide a concise, commit message for the changes described in the following git diff. Output only the commit message.'
summary_prompt='Task: Provide a concise, human-readable summary (2-3 sentences) of the changes described in the following git diff. Output only the summary text.'

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
    TARGET=""
    PATTERN=""
    subcmd=""
    debug=false
    dry_run=false
    # 1. Subcommand or help/version must be first
    if [ $# -eq 0 ]; then show_help; exit 0; fi
    case "$1" in
        -h|--help|help)
            show_help; exit 0;;
        -v|--version)
            show_version; exit 0;;
        message|summary|changelog|release-notes|announce|available-releases|update)
            subcmd=$1; shift;;
        *)
            echo "First argument must be a subcommand or -h/--help/-v/--version" >&2
            show_help; exit 1;;
    esac
    # 2. Next arg: target (if present and not option)
    if [ $# -gt 0 ]; then
        case "$1" in
            --current|--staged)
                TARGET=$1; shift;;
            -* )
                : # skip, no target
                ;;
            * )
                if is_valid_git_range "$1"; then
                    TARGET=$1; shift;
                fi
                # else: do not shift, let it fall through to pattern parsing
                ;;
        esac
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
            --verbose) debug=true; shift;;
            --dry-run) dry_run=true; shift;;
            --template-dir) template_dir=$2; shift 2;;
            --config-file) config_file=$2; shift 2;;
            --output-file) output_file=$2; shift 2;;
            --todo-pattern) todo_pattern=$2; shift 2;;
            --version-file) version_file=$2; shift 2;;
            --model) model=$2; shift 2;;
            --model-provider) model_provider=$2; shift 2;;
            --api-model) api_model=$2; shift 2;;
            --api-url) api_url=$2; shift 2;;
            --update-mode) update_mode=$2; shift 2;;
            --section-name) section_name=$2; shift 2;;
            --) shift; break;;
            --*) echo "Unknown option or argument: $1" >&2; show_help; exit 1;;
            *) echo "Unknown argument: $1" >&2; show_help; exit 1;;
        esac
    done
    # Debug output
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

# Get current version from version_file or fallback
get_current_version() {
    if [ -n "$version_file" ] && [ -f "$version_file" ]; then
        grep -Eom1 '[0-9]+\.[0-9]+\.[0-9]+' "$version_file" || echo "Unreleased"
    else
        echo "Unreleased"
    fi
}

# Show all available release tags
run_available_releases() {
    curl -s https://api.github.com/repos/itlackey/changeish/releases | jq -r '.[] | .tag_name'
    exit 0
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

# Build git history markdown (with version info)
build_history() {
    hist=$1
    commit=$2
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
    # if [ -n "$found_version_file" ]; then
    #     # Try to get version diff for this commit
    #     if [ "$commit" = "--cached" ]; then
    #         version_diff=$(git --no-pager diff --cached --minimal --no-prefix --unified=0 --no-color -b -w --compact-summary --color-moved=no -- "$found_version_file" | grep -Ei '^[+].*version' || true)
    #     elif [ "$commit" = "--current" ] || [ -z "$commit" ]; then
    #         version_diff=$(git --no-pager diff --minimal --no-prefix --unified=0 --no-color -b -w --compact-summary --color-moved=no -- "${found_version_file}" | grep -Ei '^[+].*version' || true)
    #     else
    #         version_diff=$(git --no-pager diff $commit^! --minimal --no-prefix --unified=0 --no-color -b -w --compact-summary --color-moved=no -- "$found_version_file" | grep -Ei '^[+].*version' || true)
    #     fi
    #     if [ -n "$version_diff" ]; then
    #         parsed_version=$(parse_version "$version_diff")
    #         version_info="**Version:** $parsed_version (updated)"
    #     else
    #         current_file_version=$(get_current_version_from_file "$found_version_file")
    #         if [ -n "$current_file_version" ]; then
    #             version_info="**Version:** $current_file_version (current)"
    #         fi
    #     fi
    # fi
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
    printf '```diff\n' >>"$hist"
    eval git "$git_args" >>"$hist"
    printf '\n```' >>"$hist"
    # Append TODO section
    td=$(extract_todo_changes "$commit")
    [ -n "$td" ] && printf '\n### TODO Changes\n```diff\n%s\n```\n' "$td" >>"$hist"
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
    body=$(printf '{"model":"%s","messages":[{"role":"user","content":"%s"}]}' \
        "$api_model" "$(cat "$1" | json_escape)")
    curl -s -X POST "$api_url" -H 'Content-Type: application/json' -d "$body" |
        sed -n 's/.*"content"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
        sed 's/\\n/\n/g; s/\\"/"/g'
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

generate_prompt_file() {
    out=$1
    tpl=$2
    header=$3
    hist=$4
    file_tpl="$template_dir/$tpl"
    if [ -f "$file_tpl" ]; then cp "$file_tpl" "$out"; else printf '%s\n' "$header" >"$out"; fi
    printf '\n<<<GIT HISTORY>>>\n%s\n<<<END>>>\n' "$(cat "$hist")" >>"$out"
}

# -------------------------------------------------------------------
# Subcommand Implementations
# -------------------------------------------------------------------
run_message() {
    hist=$(mktemp)
    build_history "$hist"
    pr=$(mktemp)
    printf '%s\n\n<<GIT_HISTORY>>\n' "$commit_message_prompt" >"$pr"
    cat "$hist" >>"$pr"
    printf '<<GIT_HISTORY>>' >>"$pr"
    res=$(generate_response "$pr")
    rm -f "$hist" "$pr"
    if [ -n "$output_file" ]; then
        [ "$dry_run" = false ] && printf '%s' "$res" >"$output_file"
        printf 'Message written to %s\n' "$output_file"
    else printf '%s\n' "$res"; fi
}

run_summary() {
    hist=$(mktemp)
    build_history "$hist"
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

# Remove duplicate blank lines and ensure file ends with newline
remove_duplicate_blank_lines() {
    # $1: file path
    awk 'NR==1{print} NR>1{if (!($0=="" && p=="")) print} {p=$0} END{if(p!="")print ""}' "$1" >"$1.tmp" && mv "$1.tmp" "$1"
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

run_changelog() {
    hist=$(mktemp)
    build_history "$hist"
    cat "$hist"
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

run_release_notes() {
    hist=$(mktemp)
    build_history "$hist"
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

run_announce() {
    hist=$(mktemp)
    build_history "$hist"
    pr=$(mktemp)
    header="Write a blog-style announcement for version $(get_current_version) from the following git history."
    generate_prompt_file "$pr" 'announce.tpl' "$header" "$hist"
    res=$(generate_response "$pr")
    rm -f "$hist" "$pr"
    out=${output_file:-$announce_file}
    [ "$dry_run" = false ] && printf '%s\n' "$res" >"$out"
    printf 'Announcement written to %s\n' "$out"
}

# -------------------------------------------------------------------
# Main Execution
# -------------------------------------------------------------------
# Source config if exists
[ -n "$config_file" ] && [ -f "$config_file" ] && . "$config_file" || [ -f .env ] && . .env
parse_args "$@"
# Determine remote mode
case $model_provider in
remote) remote=true ;;
none) remote=false ;;
auto) command -v ollama >/dev/null 2>&1 && remote=false || remote=true ;;
*) remote=false ;;
esac
# Dispatch
run_with_commits() {
    run_func=$1
    # If TARGET is --current, --staged, or empty, just run once
    if [ "$TARGET" = "--current" ] || [ "$TARGET" = "--staged" ] || [ -z "$TARGET" ]; then
        eval "$run_func" "$TARGET"
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
    commit_id="$1"
    hist=$(mktemp)
    build_history "$hist" "$commit_id"
    pr=$(mktemp)
    printf '%s\n\n<<GIT_HISTORY>>\n' "$commit_message_prompt" >"$pr"
    cat "$hist" >>"$pr"
    printf '<<GIT_HISTORY>>' >>"$pr"
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
    build_history "$hist" "$commit_id"
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
    build_history "$hist" "$commit_id"
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
    build_history "$hist" "$commit_id"
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
    build_history "$hist" "$commit_id"
    pr=$(mktemp)
    header="Write a blog-style announcement for version $(get_current_version) from the following git history."
    generate_prompt_file "$pr" 'announce.tpl' "$header" "$hist"
    res=$(generate_response "$pr")
    rm -f "$hist" "$pr"
    out=${output_file:-$announce_file}
    [ "$dry_run" = false ] && printf '%s\n' "$res" >"$out"
    printf 'Announcement written to %s\n' "$out"
}

case $subcmd in
update) run_update ;;
available-releases) run_available_releases ;;
help) show_help ;;
message) run_with_commits run_message_with_commit ;;
summary) run_with_commits run_summary_with_commit ;;
changelog) run_with_commits run_changelog_with_commit ;;
release-notes) run_with_commits run_release_notes_with_commit ;;
announce) run_with_commits run_announce_with_commit ;;
*) show_help ;;
esac
