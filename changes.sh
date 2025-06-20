#!/usr/bin/env bash
# Version: 0.1.10
# Usage: changeish [OPTIONS]
#
# Options:
#   --help                 Show this help message and exit
#   --current              Use only uncommitted changes for git history (default)
#   --staged               Use only staged changes for git history
#   --all                  Include all history (from first commit to HEAD)
#   --from REV             Set the starting commit (default: HEAD)
#   --to REV               Set the ending commit (default: HEAD^)
#   --short-diff           Show only diffs for todos-related markdown files
#   --model MODEL          Specify the model to use (default: qwen2.5-coder)
#   --changelog-file PATH  Path to changelog file to update (default: ./CHANGELOG.md)
#   --prompt-template PATH Path to prompt template file (default: ./changelog_prompt.md)
#   --prompt-only          Generate prompt file only, do not generate or insert changelog
#   --version-file PATH    File to check for version number changes in each commit (default: auto-detects common files)
#   --remote               Use remote API to generate changelog
#   --api-model MODEL      Specify the remote API model to use (overrides --model for remote)
#   --api-url URL          Specify the remote API URL for changelog generation
#   --update               Update the script to the latest version and exit
#   --version              Show script version and exit
#   --available-releases   Show available releases and exit
#
# Example:
# Update change log with information about the uncommitted changes using local model:
#   changeish 
# Update change log with information about the staged changes:
#   changeish --staged
# Update change log with information from a specific commit range:
#   changeish --from v1.0.0 --model llama3 --version-file custom_version.txt
# Update change log with information about all history:
#   changeish --all --changelog-file CHANGELOG.md
# Update changeish to the latest changes:
#   changeish --update
# Use a remote API for changelog generation (with custom model and URL):
#   changeish --remote --api-model llama3 --api-url https://api.example.com/v1/chat/completions
# Environment variables:
#   CHANGEISH_MODEL        Model to use for local generation (same as --model)
#   CHANGEISH_API_KEY      API key for remote changelog generation (required if --remote is used)
#   CHANGEISH_API_URL      API URL for remote changelog generation (same as --api-url)
#   CHANGEISH_API_MODEL    API model for remote changelog generation (same as --api-model)
#
set -euo pipefail

# Source .env file in currend directory if it exists
if [[ -f .env ]]; then
  echo "Sourcing .env file..."
  source .env
fi

default_prompt=$(cat <<'END_PROMPT'
<<<INSTRUCTIONS>>>
Task: Generate a changelog from the Git history that follows the structure below. 
Be sure to use only the information from the Git history in your response.

Output rules

1. Use only information from the Git history provided in the prompt.
2. Output **ONLY** valid Markdown.
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
version_file=""
default_version_files=("changes.sh" "package.json" "pyproject.toml" "setup.py" "Cargo.toml" "composer.json" "build.gradle" "pom.xml")

update() {
  latest_version=$(curl -s https://api.github.com/repos/itlackey/changeish/releases/latest | jq -r '.tag_name')
  echo "Updating changeish to version $latest_version..."
  curl -fsSL https://raw.githubusercontent.com/itlackey/changeish/main/install.sh | sh
  echo "Update complete."
  exit 0
}
# Print help and exit
show_help() {
  awk 'NR>2 && /^# /{sub(/^# /, ""); print} /^set -euo pipefail/{exit}' "$0"
  echo "Default version files:"
  for file in "${default_version_files[@]}"; do
    echo "  $file"
  done
  exit 0
}

show_available_releases() {
  curl -s https://api.github.com/repos/itlackey/changeish/releases | jq -r '.[].tag_name'
  exit 0
}

# Print version and exit
show_version() {
  awk 'NR==2{gsub(/^# /, ""); print; exit}' "$0"
  exit 0
}

# Write git history to markdown file
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
      # Version number changes section
      if [[ -n "$found_version_file" ]]; then
        echo "**Version number changes in $found_version_file:**"
        echo '```diff'
        git diff "$commit^!" --unified=0 -- "$found_version_file" | grep -i version || true
        echo '```'
        echo
      fi
      echo "**Diffs for todos-related markdown files:**"
      echo '```diff'
      git diff "$commit^!" --unified=0 -- '**/*.md' | grep -E 'diff --git a/.*todo.*\.md' -A100 | grep '^+' | grep -v '^+++' || true
      echo '```'
      
      echo "**Full diff:**"
      echo '```diff'
      git diff "$commit^!" --unified=0 --stat ':(exclude)*todo*.md'
      echo '```'    
      
      echo
    done
  } > "$outfile"
}

# Generate prompt.md file
generate_prompt() {
  local outfile="$1"
  local prompt_template="$2"
  local prompt
  if [[ -n "$prompt_template" && -f "$prompt_template" ]]; then
    echo "Generating prompt file from template: $prompt_template"
    prompt="$(cat "$prompt_template")"
  else
    prompt="$default_prompt"  
  fi
  complete_prompt=$prompt\\n"<<GIT HISTORY>>"\\n$(cat "$outfile")\\n"<<END>>"
  echo -e "$complete_prompt" > prompt.md

  echo "Generated prompt file: prompt.md"
}

# Run Ollama model
run_ollama() {
  local model="$1"
  local prompt_file="$2"
  ollama run "$model" < "$prompt_file"
}

generate_remote() {
  local model="$1"
  local prompt="$2"
  local message=$(cat $prompt)
  local response=""
  response=$(curl -s -X POST $api_url \
    -H "Authorization: Bearer $api_key" \
    -H "Content-Type: application/json" \
    -d "$(jq -n \
      --arg model "$model" \
      --arg content "$message" \
      '{model: $model, messages: [{role: "user", content: $content}]}' \
    )")
  
  #echo $response
  # Parse the content of the last item in choices array
  echo "$response" | jq -r '.choices[-1].message.content'
}



# Generate changelog using Ollama and insert into changelog file
generate_changelog() {
  local model="$1"
  local changelog_file="$2"
 
    local changelog
    if $remote; then
      model="$api_model"
      echo "Running remote model '$model'..."
      changelog="$(generate_remote "$model" prompt.md)"
    else
      if command -v ollama &>/dev/null; then
        echo "Running Ollama model '$model'..."
        changelog="$(run_ollama "$model" prompt.md)"
      else
        echo "ollama not found, skipping changelog generation."
        exit 0
      fi
    fi
    changelog="$changelog\n\nGenerated by changeish"
    echo -e "\n## Changelog \(generated by changeish using $model\)\n"
    echo '```'
    echo "$changelog"
    echo '```'
    insert_changelog "$changelog_file" "$changelog"

}

# Insert changelog into changelog file
insert_changelog() {
  local changelog_file="$1"
  local changelog="$2"
  if [[ -f "$changelog_file" ]]; then
    tmp="$(mktemp)"
    changelog_tmp="$(mktemp)"
    printf '%s\n' "$changelog" > "$changelog_tmp"
    if grep -q '^## ' "$changelog_file"; then
      awk -v changelog_file="$changelog_tmp" '
        NR==1 {print; print ""; while ((getline line < changelog_file) > 0) print line; close(changelog_file); next}
        /^## / {print; f=1; next}
        {if(f) print; else next}
      ' "$changelog_file" > "$tmp" && mv "$tmp" "$changelog_file"
    else
      # No second-level heading found, append to end
      printf '\n%s\n' "$changelog" >> "$changelog_file"
    fi
    rm -f "$changelog_tmp"
    echo "Inserted fresh changelog into '$changelog_file'."
  fi
}

# Defaults
from_rev=""
to_rev=""
short_diff=false
prompt_template="./changelog_prompt.md"
prompt_only=false
model="qwen2.5-coder"
changelog_file="./CHANGELOG.md"
all_history=false
current_changes=false
staged_changes=false
outfile="git_history.md"
show_releases=false
api_url=$CHANGEISH_API_URL
api_key=$CHANGEISH_API_KEY
api_model=$CHANGEISH_API_MODEL
remote=false
# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --from) from_rev="$2"; shift 2 ;;
    --to) to_rev="$2"; shift 2 ;;
    --short-diff) short_diff=true; shift ;;
    --model) model="$2"; shift 2 ;;
    --changelog-file) changelog_file="$2"; shift 2 ;;
    --prompt-template) prompt_template="$2"; shift 2 ;;
    --prompt-only) prompt_only=true; shift ;;
    --version-file) version_file="$2"; shift 2 ;;
    --current) current_changes=true; shift ;;
    --staged) staged_changes=true; shift ;;
    --all) all_history=true; shift ;;
    --remote) remote=true; shift ;;
    --api-model) api_model="$2"; shift 2 ;;
    --api-url) api_url="$2"; shift 2 ;;
    --update) update ;;
    --available-releases) show_available_releases ;;
    --help) show_help ;;
    --version) show_version ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ ! -n "$api_model" ]]; then
  api_model="$model"
fi

# After argument parsing, set current_changes if no relevant flags are set
if ! $staged_changes && ! $all_history && [ -z "$to_rev" ] && [ -z "$from_rev" ]; then
  current_changes=true
else
  current_changes=false
  if [[ -z "$to_rev" ]]; then
    to_rev="HEAD"
  fi
  if [[ -z "$from_rev" ]]; then
    from_rev="HEAD"
  fi
fi

found_version_file=""
if [[ -n "$version_file" ]]; then
  if [[ -f "$version_file" ]]; then
    found_version_file="$version_file"
  fi
else
  for vf in "${default_version_files[@]}"; do
    if [[ -f "$vf" ]]; then
      found_version_file="$vf"
      break
    fi
  done
fi



# # print all parsed options
# echo "Parsed options:"
# echo "  current_changes: $current_changes"
# echo "  staged_changes: $staged_changes"
# echo "  all_history: $all_history"
# echo "  from_rev: $from_rev"
# echo "  to_rev: $to_rev"
# echo "  short_diff: $short_diff"
# echo "  model: $model"
# echo "  changelog_file: $changelog_file"
# echo "  prompt_template: $prompt_template"
# echo "  prompt_only: $prompt_only"
# echo "  version_file: $found_version_file"
# if [[ -z "$found_version_file" ]]; then
#   echo "No version file found. Skipping version number changes section." >&2
# fi


# Check if git is initialized
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  echo "Error: Not a git repository. Please run this script inside a git repository." >&2
  exit 1
fi

if $current_changes; then
  outfile="git_history.md"
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
      git diff "$found_version_file" | grep -i version | grep '^+' | grep -v '^+++' || true
      echo '```'
      echo
    fi
    echo
    echo "**Diff:**"
    echo '```diff'
    git diff --unified=0 --stat -- . ':(exclude)*todo*.md'
    echo '```'
    echo
    echo "**Diffs for todos-related markdown files:**"
    echo '```diff'
    git diff --unified=0 -- '**/*.md' | grep -E 'diff --git a/.*todo.*\.md' -A100 | grep '^+' | grep -v '^+++' || true
    echo '```'
  } > "$outfile"
  echo "Generated git history for uncommitted changes in $outfile."
elif $staged_changes; then
  outfile="git_history.md"
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
      git diff --unified=0 --cached "$found_version_file" | grep -i version | grep '^+' | grep -v '^+++' || true
      echo '```'
      echo
    fi
    echo
    echo "**Diff:**"
    echo '```diff'
    git diff --unified=0 --stat --cached -- . ':(exclude)*todo*.md'
    echo '```'
    echo
    echo "**Diffs for todos-related markdown files:**"
    echo '```diff'
    git diff --unified=0 --cached -- '**/*.md' | grep -E 'diff --git a/.*todo.*\.md' -A100 | grep '^+' | grep -v '^+++' || true
    echo '```'
  } > "$outfile"
  echo "Generated git history for staged changes in $outfile."
else
  
  # Handle --all and default commit ranges
  if $all_history; then
    to_rev="$(git rev-list --max-parents=0 HEAD | tail -n1)"
    from_rev="HEAD"
  fi

  echo "Using commit range: $to_rev^..$from_rev"
  branch="$(git rev-parse --abbrev-ref HEAD)"
  commits=( $(git rev-list --reverse "$to_rev^".."$from_rev") )
  if [[ ${#commits[@]} -eq 0 ]]; then
    echo "No commits found in range $to_rev^..$from_rev" >&2
    exit 1
  fi
  start="${commits[0]}"
  end="${commits[-1]}"
  start_date="$(git show -s --format=%ci "$start")"
  end_date="$(git show -s --format=%ci "$end")"
  total_commits=${#commits[@]}
  echo "Generating git history for total $total_commits commits from $start ($start_date) to $end ($end_date) on branch $branch..."
  write_git_history "$outfile" "$branch" "$start" "$end" "$start_date" "$end_date" "${commits[@]}"
  echo "Generated git history in $outfile."
fi

# Replace prompt generation and writing with function call
generate_prompt "$outfile" "$prompt_template"

if ! $prompt_only; then
  generate_changelog "$model" "$changelog_file"
fi
