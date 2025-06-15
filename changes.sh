#!/usr/bin/env bash
# Version: 0.1.1
# Usage: ./changes.sh [OPTIONS]
#
# Options:
#   --from REV           Set the starting commit (default: HEAD)
#   --to REV             Set the ending commit (default: HEAD^)
#   --short-diff         Show only diffs for todos-related markdown files
#   --model MODEL        Specify the Ollama model to use (default: devstral)
#   --changelog-file PATH  Path to changelog file to update (default: ./static/help/changelog.md)
#   --prompt-file PATH   Path to prompt file (default: ./docs/prompts/changelog_prompt.md)
#   --generate           Generate changelog using Ollama
#   --all                Include all history (from first commit to HEAD)
#   --help               Show this help message and exit
#
# Example:
#   ./changes.sh --from v1.0.0 --to HEAD --generate --model llama3
set -euo pipefail

# Print help and exit
show_help() {
  awk 'NR>2 && /^# /{sub(/^# /, ""); print} /^set -euo pipefail/{exit}' "$0"
  exit 0
}

# Print version and exit
show_version() {
  awk 'NR==2{gsub(/^# /, ""); print; exit}' "$0"
  exit 0
}

# Defaults
from_rev="HEAD"
to_rev="HEAD^"
short_diff=false
prompt_file="./changelog_prompt.md"
generate=false
model="devstral"
changelog_file="./CHANGELOG.md"
all_history=false

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --from) from_rev="$2"; shift 2 ;;
    --to) to_rev="$2"; shift 2 ;;
    --short-diff) short_diff=true; shift ;;
    --model) model="$2"; shift 2 ;;
    --changelog-file) changelog_file="$2"; shift 2 ;;
    --prompt-file) prompt_file="$2"; shift 2 ;;
    --generate) generate=true; shift ;;
    --all) all_history=true; shift ;;
    --help) show_help ;;
    --version) show_version ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

# Handle --all and default commit ranges
if $all_history; then
  to_rev="$(git rev-list --max-parents=0 HEAD | tail -n1)"
  from_rev="HEAD"
else
  # If --to not specified, use previous commit
  if [[ "$to_rev" == "$(git rev-list --max-parents=0 HEAD | tail -n1)" ]]; then
    if ! [[ "$*" =~ --to ]]; then
      to_rev="HEAD^"
    fi
  fi
  # If --from not specified, use current commit
  if [[ "$from_rev" == "HEAD" ]]; then
    if ! [[ "$*" =~ --from ]]; then
      from_rev="HEAD"
    fi
  fi
fi

branch="$(git rev-parse --abbrev-ref HEAD)"
commits=( $(git rev-list --reverse "$to_rev".."$from_rev") )
if [[ ${#commits[@]} -eq 0 ]]; then
  echo "No commits found in range $to_rev..$from_rev" >&2
  exit 1
fi

start="${commits[0]}"
end="${commits[-1]}"
start_date="$(git show -s --format=%ci "$start")"
end_date="$(git show -s --format=%ci "$end")"

outfile="git_history.md"
{
  echo "# Git History"
  echo
  echo "**Branch:** $branch"
  echo
  echo "**Range:** from \`$start\` ($start_date) to \`$end\` ($end_date)"
  echo

  for commit in "${commits[@]}"; do
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

    echo "**Changes in package.json:**"
    echo '```diff'
    git diff "$commit^!" -- package.json || true
    echo '```'
    echo

    if $short_diff; then
      echo "**Diffs for todos-related markdown files:**"
      echo '```diff'
      git diff "$commit^!" -- '*.md' | grep -E 'diff --git a/.*todos.*\.md' -A100 || true
      echo '```'
    else
      echo "**Full diff:**"
      echo '```diff'
      git diff "$commit^!" --no-color
      echo '```'    
    fi

    echo
  done
} > "$outfile"

echo "Generated git history in $outfile."

# Set prompt variable
if [[ -f "$prompt_file" ]]; then
  prompt="$(cat "$prompt_file")"
else  
  prompt=$'\n=== INSTRUCTIONS===\nPlease generate a change log based on the provided Git History above. The change log should be grouped by version (descending), then by Enhancements, Fixes, and Chores. It is VERY IMPORTANT that you follow this format exactly and DO NOT include additional comments.\n\nHere is an example of the desired changelog format:\n\n## v2.0.213-3 (2025-02-13)\n\n### Enhancements\n\n- Some TODO clean up and started on authentication refactor.\n- Improved caching for available projects and organizations.\n- Refactored organization and project API clients for better cache usage.\n- Updated user profile editor to show loading state.\n\n### Fixes\n\n- Fixed issues with My Account page and user profile loading.\n- Moved processResponse to toast.js and improved notification handling.\n\n### Chores\n\n- Updated .vscode/settings.json to ignore build directory.\n- Updated documentation TODOs for v2.0 and v2.1.'
fi
complete_prompt=$(cat "$outfile")$prompt
echo "$complete_prompt" > prompt.md

if $generate; then
  if command -v ollama &>/dev/null; then
    echo "Running Ollama model '$model'..."
    changelog="$(ollama run $model < prompt.md)"
    changelog="$changelog\nGenerated my changeish"

    echo -e "\n## Changelog \(generated by changeish using $model\)\n"
    echo '```'
    echo "$changelog"
    echo '```'

    # Only write to changelog_file if change log is found
    if [[ -f "$changelog_file" ]]; then
      tmp="$(mktemp)"
      if grep -q '^## ' "$changelog_file"; then
        awk -v new="$changelog\n" '
          NR==1 {print; print ""; print new; next}
          /^## / {print; f=1; next}
          {if(f) print; else next}
        ' "$changelog_file" > "$tmp" && mv "$tmp" "$changelog_file"
      else
        # No second-level heading found, append to end
        printf '\n%s\n' "$changelog" >> "$changelog_file"
      fi
      echo "Inserted fresh changelog into '$changelog_file'."
    fi
  else
    echo "ollama not found, skipping changelog generation."
  fi
fi
