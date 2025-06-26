#!/bin/sh
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
set -eu

# Initialize default option values
debug="false"
from_rev=""
to_rev=""
default_diff_options="--minimal --no-prefix --unified=0 --no-color -b -w --compact-summary --color-moved=no"
include_pattern=""
exclude_pattern=""
todo_pattern="*todo*"
changelog_file="./CHANGELOG.md"
prompt_template="./changelog_prompt.md"
save_prompt="false"
save_history="false"
version_file=""
all_history="false"
current_changes="false"
staged_changes="false"
outfile="history.md"
remote="false"
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
    - Do not include the \`\`\` code block markers in your output.
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
default_version_files="changes.sh package.json pyproject.toml setup.py Cargo.toml composer.json build.gradle pom.xml"

# Update the script to latest release
update() {
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
    echo "Version: $(awk 'NR==3{sub(/^# Version: /, ""); print; exit}' "$0")"
    awk '/^set -eu/ {exit} NR>2 && /^#/{sub(/^# ?/, ""); print}' "$0" | sed -e '/^Usage:/,$!d'
    echo "Default version files to check for version changes:"
    for file in $default_version_files; do
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
    label="$1"
    diff_spec=""
    include_arg=""
    exclude_arg=""
    if [ -n "$2" ]; then
        diff_spec="$2"
    fi

    echo "Building entry for: $label"
    echo "## $label" >>"$outfile"

    case "$diff_spec" in
    *^!)
        echo "**Commit:** $(git show -s --format=%s "$diff_spec")" >>"$outfile"
        echo "**Date:**   $(git show -s --format=%ci "$diff_spec")" >>"$outfile"
        echo "**Message:**" >>"$outfile"
        echo '```' >>"$outfile"
        git show -s --format=%B "$diff_spec" >>"$outfile"
        echo '```' >>"$outfile"
        ;;
    esac

    if [ "$debug" = "true" ]; then
        git --no-pager diff --unified=0 -- "*todo*"
    fi
    if [ -n "$todo_pattern" ]; then
        if [ -n "$diff_spec" ]; then
            todo_diff=$(git --no-pager diff "$diff_spec" --unified=0 -b -w --no-prefix --color=never -- "$todo_pattern" | grep '^[+-]' | grep -Ev '^[+-]{2,}' || true)
        else
            todo_diff=$(git --no-pager diff --unified=0 -b -w --no-prefix --color=never -- "$todo_pattern" | grep '^[+-]' | grep -Ev '^[+-]{2,}' || true)
        fi
        if [ -n "$todo_diff" ]; then
            echo "" >>"$outfile"
            echo "### Changes in TODOs" >>"$outfile"
            echo '```diff' >>"$outfile"
            printf '%s\n' "$todo_diff" >>"$outfile"
            echo '```' >>"$outfile"
        fi
    fi

    if [ -n "$include_pattern" ]; then
        if ! git ls-files -- "*$include_pattern*" >/dev/null 2>&1; then
            echo "Error: Invalid --include-pattern '$include_pattern' (no matching files or invalid pattern)." >&2
            exit 1
        fi
    fi
    if [ -n "$exclude_pattern" ]; then
        if ! git ls-files -- ":(exclude)*$exclude_pattern*" >/dev/null 2>&1; then
            echo "Error: Invalid --exclude-pattern '$exclude_pattern' (no matching files or invalid pattern)." >&2
            exit 1
        fi
    fi

    echo "" >>"$outfile"
    echo "### Changes in files" >>"$outfile"
    echo '```diff' >>"$outfile"
    if [ -n "$include_pattern" ]; then
        include_arg="*$include_pattern*"
    fi
    if [ -n "$exclude_pattern" ]; then
        exclude_arg=":(exclude)*$exclude_pattern*"
    fi

    if [ -n "$diff_spec" ]; then
        if [ -n "$include_arg" ] && [ -n "$exclude_arg" ]; then
            git --no-pager diff "$diff_spec" $default_diff_options "$include_arg" "$exclude_arg" >>"$outfile"
        elif [ -n "$include_arg" ]; then
            git --no-pager diff "$diff_spec" $default_diff_options "$include_arg" >>"$outfile"
        elif [ -n "$exclude_arg" ]; then
            git --no-pager diff "$diff_spec" $default_diff_options "$exclude_arg" >>"$outfile"
        else
            git --no-pager diff "$diff_spec" $default_diff_options >>"$outfile"
        fi
    else
        if [ -n "$include_arg" ] && [ -n "$exclude_arg" ]; then
            git --no-pager diff $default_diff_options "$include_arg" "$exclude_arg" >>"$outfile"
        elif [ -n "$include_arg" ]; then
            git --no-pager diff $default_diff_options "$include_arg" >>"$outfile"
        elif [ -n "$exclude_arg" ]; then
            git --no-pager diff $default_diff_options "$exclude_arg" >>"$outfile"
        else
            git --no-pager diff $default_diff_options >>"$outfile"
        fi
    fi
    echo '```' >>"$outfile"

    echo "" >>"$outfile"

    if [ "$debug" = "true" ]; then
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
    gp_history_file="$1"
    gp_template_file="$2"
    gp_existing_section="$3"
    if [ -n "$gp_template_file" ] && [ -f "$gp_template_file" ]; then
        echo "Generating prompt file from template: $gp_template_file"
        cp "$gp_template_file" "$prompt_file"
    else
        printf '%s' "$default_prompt" >"$prompt_file"
    fi

    if [ -n "$gp_existing_section" ]; then
        printf '\n5. Include ALL of the existing items from the "EXISTING CHANGELOG" in your response. DO NOT remove any existing items.\n' >>"$prompt_file"
        printf '<<<END>>>\n<<<EXISTING CHANGELOG>>>\n' >>"$prompt_file"
        printf '%s\n' "$gp_existing_section" >>"$prompt_file"
        printf '<<<END>>>\n' >>"$prompt_file"
    else
        printf '\n<<<END>>>\n%s' "$example_changelog" >>"$prompt_file"
    fi
    printf '\n<<<GIT HISTORY>>>\n' >>"$prompt_file"
    cat "$gp_history_file" >>"$prompt_file"
    printf '\n<<<END>>>\n' >>"$prompt_file"
}

# Run the local Ollama model with the prompt file
# Arguments:
#   $1: Model name
#   $2: Prompt file path
run_ollama() {
    model="$1"
    prompt_file_path="$2"
    if [ "$debug" = "true" ]; then
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
    remote_model="$1"
    prompt_path="$2"
    message=$(cat "$prompt_path")
    response=$(curl -s -X POST "$api_url" \
        -H "Authorization: Bearer $api_key" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg model "$remote_model" --arg content "$message" \
            '{model: $model, messages: [{role: "user", content: $content}], max_completion_tokens: 8192}')")
    result=$(echo "$response" | jq -r '.choices[-1].message.content')
    if [ "$debug" = "true" ]; then
        echo "Response from remote API:" >&2
        echo "$response" | jq . >&2
    fi
    echo "$result"
}

generate_response() {
    if [ "$remote" = "true" ]; then
        echo "Generating changelog using model: $api_model" >&2
        response=$(generate_remote "$api_model" "$prompt_file")
    else
        if command -v ollama >/dev/null 2>&1; then
            echo "Generating changelog using model: $model" >&2
            response=$(run_ollama "$model" "$prompt_file")
        else
            echo "ollama not found, skipping changelog generation." >&2
            exit 0
        fi
    fi
    printf '%s' "$response"
}

generate_changelog() {
    cg_model="$1"
    cg_file="$2"
    cg_section="$3"
    cg_mode="$4"
    cg_existing="$5"
    changelog=$(generate_response)
    if [ "$debug" = "true" ]; then
        echo ""
        echo "## Changelog (generated by changeish using $cg_model)"
        echo '```'
        printf '%s\n' "$changelog"
        echo '```'
    fi
    insert_changelog "$cg_file" "$changelog" "$cg_section" "$cg_mode" "$cg_existing"
    echo "Changelog updated in $cg_file"
}

insert_changelog() {
    ic_file="$1"
    ic_content="$2"
    ic_section_name="$3"
    ic_mode="$4"
    ic_existing_section="$5"
    ic_version="$ic_section_name"
    ic_esc_version=$(echo "$ic_version" | sed 's/[][\\/.*^$]/\\&/g')
    ic_pattern="^##[[:space:]]*\[?$ic_esc_version\]?"
    ic_content=$(printf '%s\n' "$ic_content")
    ic_content_file=$(mktemp)
    printf '%s' "$ic_content" >"$ic_content_file"

    if [ -n "$ic_existing_section" ]; then
        case "$ic_mode" in
        update | auto)
            ic_start_line=$(grep -nE "$ic_pattern" "$ic_file" | head -n1 | cut -d: -f1)
            ic_next=$(tail -n +"$((ic_start_line + 1))" "$ic_file" | grep -n '^## ' | head -n1 | cut -d: -f1)
            if [ -n "$ic_next" ]; then
                ic_end_line=$((ic_start_line + ic_next - 1))
            else
                ic_end_line=$(wc -l <"$ic_file")
            fi
            awk -v start="$ic_start_line" -v end="$ic_end_line" -v version="$ic_version" -v content_file="$ic_content_file" '
                    function slurp(file,   l, s) { while ((getline l < file) > 0) s = s l "\n"; close(file); return s }
                    NR < start { print }
                    NR == start { print "## " version; printf "%s", slurp(content_file) }
                    NR > end { print }
                ' "$ic_file" >"${ic_file}.tmp" && mv "${ic_file}.tmp" "$ic_file"
            ;;
        prepend)
            ic_start_line=$(grep -nE "$ic_pattern" "$ic_file" | head -n1 | cut -d: -f1)
            if [ -z "$ic_start_line" ]; then
                echo "Section '$ic_section_name' not found in $ic_file" >&2
                exit 1
            fi
            awk -v insert_line="$ic_start_line" -v content_file="$ic_content_file" '
                    function slurp(file,   l, s) { while ((getline l < file) > 0) s = s l "\n"; close(file); return s }
                    NR == insert_line {
                        print "## Current Changes"
                        printf "%s", slurp(content_file)
                    }
                    { print }
                ' "$ic_file" >"${ic_file}.tmp" && mv "${ic_file}.tmp" "$ic_file"
            ;;
        append)
            ic_start_line=$(grep -nE "$ic_pattern" "$ic_file" | head -n1 | cut -d: -f1)
            if [ -z "$ic_start_line" ]; then
                echo "Section '$ic_section_name' not found in $ic_file" >&2
                exit 1
            fi
            ic_next=$(tail -n +"$((ic_start_line + 1))" "$ic_file" | grep -n '^## ' | head -n1 | cut -d: -f1)
            if [ -n "$ic_next" ]; then
                ic_end_line=$((ic_start_line + ic_next - 1))
            else
                ic_end_line=$(wc -l <"$ic_file")
            fi
            awk -v end="$ic_end_line" -v content_file="$ic_content_file" '
                    function slurp(file,   l, s) { while ((getline l < file) > 0) s = s l "\n"; close(file); return s }
                    NR == end { printf "%s", slurp(content_file) }
                    { print }
                ' "$ic_file" >"${ic_file}.tmp" && mv "${ic_file}.tmp" "$ic_file"
            ;;
        esac
    else
        echo "Adding ($ic_mode) new changelog section for '$ic_section_name' in $ic_file"
        case "$ic_mode" in
        append)
            printf "\n## %s\n" "$ic_version" >>"$ic_file"
            printf '%s\n' "$ic_content" >>"$ic_file"
            ;;
        update | auto | prepend)
            ic_first_h1=$(grep -n '^# ' "$ic_file" | head -n1 | cut -d: -f1)
            if [ -n "$ic_first_h1" ]; then
                awk -v line="$ic_first_h1" -v version="$ic_version" -v content_file="$ic_content_file" '
                        function slurp(file,   l, s) { while ((getline l < file) > 0) s = s l "\n"; close(file); return s }
                        NR == line {
                            print
                            print ""
                            print "## " version
                            printf "%s", slurp(content_file)
                            next
                        }
                        { print }
                    ' "$ic_file" >"${ic_file}.tmp" && mv "${ic_file}.tmp" "$ic_file"
            else
                printf "## %s\n" "$ic_version" >>"$ic_file"
                printf '%s\n' "$ic_content" >>"$ic_file"
            fi
            ;;
        esac
    fi

    rm -f "$ic_content_file"

    awk '
    BEGIN { prev = "" }
    {
        if ($0 ~ /^# /) {
            if (!seen1[$0]++) {
                if (prev != "") print ""
                print
                print ""
                prev = ""
            }
        }
        else if ($0 ~ /^## /) {
            if (!seen2[$0]++) {
                if (prev != "") print ""
                print
                print ""
                prev = ""
            }
        }
        else if ($0 ~ /^###/) {
            if (prev != "") print ""
            print
            print ""
            prev = ""
        }
        else {
            print
            prev = $0
        }
    }
    ' "$ic_file" >"${ic_file}.tmp" && mv "${ic_file}.tmp" "$ic_file"

    if ! tail -n5 "$ic_file" | grep -q "Managed by changeish"; then
        printf '\n[Managed by changeish](https://github.com/itlackey/changeish)\n\n' >>"$ic_file"
    fi

    if command -v gsed >/dev/null 2>&1; then
        gsed -i ':a;N;$!ba;s/\n\{3,\}/\n\n/g' "$ic_file"
    else
        awk 'BEGIN{blank=0} {
            if ($0 ~ /^$/) { blank++; if (blank < 2) print $0 }
            else { blank=0; print $0 }
        }' "$ic_file" >"${ic_file}.tmp" && mv "${ic_file}.tmp" "$ic_file"
    fi
}

get_current_version_from_file() {
    file="$1"
    if [ ! -f "$file" ]; then
        echo ""
        return 1
    fi
    if [ "$file" = "changes.sh" ]; then
        version=$(grep -Eo 'Version: [0-9]+\.[0-9]+(\.[0-9]+)?' "$file" | head -n3 | grep -Eo 'v?[0-9]+\.[0-9]+(\.[0-9]+)?')
        if [ -n "$version" ]; then
            echo "$version"
            return 0
        fi
    fi
    version=$(grep -Eo 'version[[:space:]]*[:=][[:space:]]*["'"'"']?([0-9]+\.[0-9]+(\.[0-9]+)?)' "$file" | head -n1 | grep -Eo '([0-9]+\.[0-9]+(\.[0-9]+)?)')
    if [ -n "$version" ]; then
        echo "$version"
        return 0
    fi
    version=$(grep -Eo '__version__[[:space:]]*=[[:space:]]*["'"'"']([0-9]+\.[0-9]+(\.[0-9]+)?)' "$file" | head -n1 | grep -Eo '([0-9]+\.[0-9]+(\.[0-9]+)?)')
    if [ -n "$version" ]; then
        echo "$version"
        return 0
    fi
    version=$(grep -Eo '"version"[[:space:]]*:[[:space:]]*"[0-9]+\.[0-9]+(\.[0-9]+)?"' "$file" | head -n1 | grep -Eo '([0-9]+\.[0-9]+(\.[0-9]+)?)')
    if [ -n "$version" ]; then
        echo "$version"
        return 0
    fi
    version=$(grep -Eo '[vV]?([0-9]+\.[0-9]+(\.[0-9]+)?)' "$file" | head -n1 | grep -Eo '([0-9]+\.[0-9]+(\.[0-9]+)?)')
    if [ -n "$version" ]; then
        echo "$version"
        return 0
    fi
    echo ""
    return 1
}

extract_changelog_section() {
    ecs_section="$1"
    ecs_file="$2"
    if [ ! -f "$ecs_file" ]; then
        echo ""
        return 0
    fi
    ecs_esc=$(echo "$ecs_section" | sed 's/[][\\/.*^$]/\\&/g')
    ecs_pattern="^##[[:space:]]*\[?$ecs_esc\]?"
    start_line=$(grep -nE "$ecs_pattern" "$ecs_file" | head -n1 | cut -d: -f1)
    if [ -z "$start_line" ]; then
        echo ""
        return 0
    else
        start_line=$((start_line + 1))
    fi
    end_line=$(tail -n +"$((start_line + 1))" "$ecs_file" | grep -n '^## ' | head -n1 | cut -d: -f1)
    if [ -n "$end_line" ]; then
        end_line=$((start_line + end_line - 1))
    else
        end_line=$(wc -l <"$ecs_file")
    fi
    sed -n "${start_line},${end_line}p" "$ecs_file"
}

config_file=""
model="qwen2.5-coder"

while [ $# -gt 0 ]; do
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
        save_prompt="true"
        shift
        ;;
    --save-history)
        save_history="true"
        shift
        ;;
    --version-file)
        version_file="$2"
        shift 2
        ;;
    --current)
        current_changes="true"
        shift
        ;;
    --staged)
        staged_changes="true"
        shift
        ;;
    --all)
        all_history="true"
        shift
        ;;
    --debug)
        debug="true"
        shift
        ;;
    --update)
        update        
        ;;
    --available-releases)
        show_available_releases        
        ;;
    --help)
        show_help
        ;;
    --version)
        show_version        
        ;;
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

if [ -n "${make_prompt_template_path-}" ]; then
    printf '%s\n' "$default_prompt" >"$make_prompt_template_path"
    echo "Default prompt template written to $make_prompt_template_path."
    exit 0
fi


CHANGEISH_API_URL=""
CHANGEISH_API_KEY=""
CHANGEISH_API_MODEL=""

if [ -n "$config_file" ]; then
    if [ -f "$config_file" ]; then
        . "$config_file"
    else
        echo "Error: config file '$config_file' not found." >&2
        exit 1
    fi
elif [ -f .env ]; then
    . .env
fi

if [ -z "$model" ] && [ -n "$CHANGEISH_API_MODEL" ]; then
    model="${CHANGEISH_MODEL}"
fi

api_url="${CHANGEISH_API_URL:-}"
api_key="${CHANGEISH_API_KEY:-}"
api_model="${CHANGEISH_API_MODEL:-}"

found_version_file=""
if [ -n "$version_file" ]; then
    if [ -f "$version_file" ]; then
        found_version_file="$version_file"
    else
        echo "Error: Specified version file '$version_file' does not exist." >&2
        exit 1
    fi
else
    for vf in $default_version_files; do
        if [ -f "$vf" ]; then
            found_version_file="$vf"
            break
        fi
    done
fi

if [ -z "$section_name" ] || [ "$section_name" = "auto" ]; then
    if [ -n "$found_version_file" ]; then
        current_version=$(get_current_version_from_file "$found_version_file")
        if [ -n "$current_version" ]; then
            section_name="$current_version"
        else
            section_name="Current Changes"
        fi
    else
        section_name="Current Changes"
    fi
fi
echo "Using section name: $section_name"

existing_changelog_section=$(extract_changelog_section "$section_name" "$changelog_file")

if [ "$save_history" = "true" ]; then
    outfile="history.md"
else
    outfile=$(mktemp)
fi
if [ "$save_prompt" = "true" ]; then
    prompt_file="prompt.md"
else
    prompt_file=$(mktemp)
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Error: Not a git repository. Please run this script inside a git repository." >&2
    exit 1
fi
if ! git rev-parse HEAD >/dev/null 2>&1; then
    echo "No commits found in repository. Nothing to show." >&2
    exit 1
fi

if [ "$staged_changes" = "false" ] && [ "$all_history" = "false" ] && [ -z "$to_rev" ] && [ -z "$from_rev" ]; then
    current_changes="true"
fi

should_generate_changelog="true"
case "$model_provider" in
none)
    should_generate_changelog="false"
    ;;
local)
    remote="false"
    ;;
remote | api)
    remote="true"
    ;;
auto)
    if ! command -v ollama >/dev/null 2>&1; then
        if [ "$debug" = "true" ]; then
            echo "ollama not found, falling back to remote API."
        fi
        remote="true"
        if [ -z "$api_key" ]; then
            echo "Warning: Falling back to remote but CHANGEISH_API_KEY is not set." >&2
            remote="false"
            should_generate_changelog="false"
        fi
        if [ -z "$api_url" ]; then
            echo "Warning: Falling back to remote but no API URL provided (use --api-url or CHANGEISH_API_URL)." >&2
            remote="false"
            should_generate_changelog="false"
        fi
    fi
    ;;
*)
    echo "Unknown --model-provider: $model_provider" >&2
    exit 1
    ;;
esac

if [ "$should_generate_changelog" = "true" ]; then
    case "$update_mode" in
    auto | prepend | append | update) ;;
    *)
        echo "Error: --update-mode must be one of auto, prepend, append, update." >&2
        exit 1
        ;;
    esac
fi

if [ "$remote" = "true" ]; then
    if [ -z "$api_model" ]; then
        api_model="$model"
    fi
    if [ -z "$api_key" ]; then
        echo "Error: --remote specified but CHANGEISH_API_KEY is not set." >&2
        exit 1
    fi
    if [ -z "$api_url" ]; then
        echo "Error: --remote specified but no API URL provided (use --api-url or CHANGEISH_API_URL)." >&2
        exit 1
    fi
fi

# if [ -n "$CHANGEISH_MODEL" ] && [ "$model" = "qwen2.5-coder" ]; then
#     model="$CHANGEISH_MODEL"
# fi

if [ "$debug" = "true" ]; then
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

if [ "$current_changes" = "true" ]; then
    build_entry "Working Tree" ""
    echo "Generated git history for uncommitted changes in $outfile."
elif [ "$staged_changes" = "true" ]; then
    build_entry "Staged Changes" "--cached"
    echo "Generated git history for staged changes in $outfile."
else
    if [ -z "$to_rev" ]; then to_rev="HEAD"; fi
    if [ -z "$from_rev" ]; then from_rev="HEAD"; fi
    if [ "$all_history" = "true" ]; then
        echo "Using commit range: --all (all history)"
        commits_list=$(git rev-list --reverse --all)
    else
        range_spec="${to_rev}^..${from_rev}"
        echo "Using commit range: ${range_spec}"
        commits_list=$(git rev-list --reverse "${range_spec}")
    fi
    if [ -z "$commits_list" ]; then
        echo "No commits found in range ${range_spec}" >&2
        exit 1
    fi
    start_commit=$(echo "$commits_list" | head -n1)
    end_commit=$(echo "$commits_list" | tail -n1)
    start_date=$(git show -s --format=%ci "$start_commit")
    end_date=$(git show -s --format=%ci "$end_commit")
    total_commits=$(echo "$commits_list" | wc -l)
    echo "Generating git history for $total_commits commits from $start_commit ($start_date) to $end_commit ($end_date) on branch $(git rev-parse --abbrev-ref HEAD)..."
    OLDIFS="$IFS"
    IFS='
'
    for commit in $commits_list; do
        build_entry "$commit" "$commit^!"
    done
    IFS="$OLDIFS"
    echo "Generated git history in $outfile."
fi

generate_prompt "$outfile" "$prompt_template" "$existing_changelog_section"

if [ "$should_generate_changelog" = "true" ]; then
    if [ ! -f "$changelog_file" ]; then
        echo "Creating new changelog file: $changelog_file"
        echo "# Changelog" >"$changelog_file"
        echo "" >>"$changelog_file"
    fi
    generate_changelog "$model" "$changelog_file" "$section_name" "$update_mode" "$existing_changelog_section"
else
    echo "Changelog generation skipped. Use --model-provider to enable it."
fi

if [ "$save_history" != "true" ]; then
    rm -f "$outfile"
fi
if [ "$save_prompt" != "true" ]; then
    rm -f "$prompt_file"
fi
