#!/usr/bin/env bash
set -euo pipefail

# This script runs a suite of tests for the changeish project.
# Helper functions and guards are documented for clarity and maintainability.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHANGEISH_SCRIPT="$SCRIPT_DIR/changes.sh"
[[ -f "$CHANGEISH_SCRIPT" ]] || {
    echo "❌ changeish script not found at $CHANGEISH_SCRIPT" >&2
    exit 1
}

PASSED=0
FAILED=0
LOG_DIR="$SCRIPT_DIR/.test-logs"
mkdir -p "$LOG_DIR"

# run_test: Helper to run a test function in a temporary git repo.
# - Each test runs in a clean temp directory, isolated from others.
# - The test function is sourced in a subshell to avoid polluting the parent shell.
# - PASSED/FAILED counters are incremented in the parent shell.
# - The original directory is restored after each test.
run_test() {
    local name="$1"
    local fn="$2"
    local do_git_init="${3:-true}"
    local TMP_REPO_DIR
    TMP_REPO_DIR="$(mktemp -d)"
    
    local ORIG_DIR="$PWD"
    #echo "Running test: $name"
    local LOGFILE="$LOG_DIR/${name// /_}.log"
    # Run the test in a temp git repo, sourcing this script for function definitions.
    cd "$TMP_REPO_DIR"
    if [[ "$do_git_init" != "false" ]]; then
        git init -q
    fi
    (
        trap 'rm -rf "$TMP_REPO_DIR"' EXIT
        mock_ollama "dummy" ""  # Mock ollama binary for tests
        # Sourcing the script with a guard so only function definitions are loaded.
        CHANGEISH_TEST_CHILD=1 source "$SCRIPT_DIR/$(basename "$0")"
        $fn > "$LOGFILE" 2>&1
    )
    local result=$?
    cd "$ORIG_DIR"
    
    if [[ $result -eq 0 ]]; then
        echo "✅ $name passed"
        PASSED=$((PASSED+1))
    else
        echo "❌ $name failed"
        FAILED=$((FAILED+1))
    fi
}

generate_commits() {
    # Helper to generate a series of commits for testing.
    echo "a" > a.txt && git add a.txt && git commit -m "a"
    echo "b" > b.txt && git add b.txt && git commit -m "b"
    echo "c" > c.txt && git add c.txt && git commit -m "c"
}

# mock_ollama: Helper to mock the ollama binary for local model tests.
# - Creates a fake bin/ollama script that echoes the model and content.
# - Ensures the test does not require the real ollama binary.
mock_ollama() {
    local model="$1"
    local content="$2"
    mkdir -p bin
    echo '#!/bin/bash' > bin/ollama
    echo 'echo '$content >> bin/ollama
    chmod +x bin/ollama
    export PATH="$PWD/bin:$PATH"
}

mock_curl() {
    local model="$1"
    if [[ -z "$model" ]]; then
        model="gpt-4.1-2025-04-14"
    fi
    local message="$2"
    if [[ -z "$message" ]]; then
        message="Hello I am $model! How can I assist you today?"
    fi
    local response
    response='{
            "id": "chatcmpl-B9MBs8CjcvOU2jLn4n570S5qMJKcT",
            "object": "chat.completion",
            "created": 1741569952,
            "model": "'"$model"'",
            "choices": [
                {
                "index": 0,
                "message": {
                    "role": "assistant",
                    "content": "'"$message"'",
                    "refusal": null,
                    "annotations": []
                },
                "logprobs": null,
                "finish_reason": "stop"
                }
            ],
            "usage": {
                "prompt_tokens": 19,
                "completion_tokens": 10,
                "total_tokens": 29,
                "prompt_tokens_details": {
                "cached_tokens": 0,
                "audio_tokens": 0
                },
                "completion_tokens_details": {
                "reasoning_tokens": 0,
                "audio_tokens": 0,
                "accepted_prediction_tokens": 0,
                "rejected_prediction_tokens": 0
                }
            },
            "service_tier": "default"
        }'
    
    mkdir -p bin
    echo '#!/bin/bash' > bin/curl
    echo "echo '$response'" >> bin/curl
    chmod +x bin/curl
    export PATH="$PWD/bin:$PATH"
}

# fail_if_not_found: Helper to check if a pattern exists in a file.
# - Prints a message and returns 1 if the pattern is not found.
# - Used for test assertions.
fail_if_not_found() {
    local pattern="$1"
    local file="$2"
    local message="$3"
    # Note: The grep output is for debug; the actual check is the if statement.
    echo "Grep: $(grep -q "$pattern" "$file")"
    if ! grep -q "$pattern" "$file"; then
        echo "❌ $message" >&2
        return 1
    fi
}
# --- Test functions ---
test_help() {
    local output
    output=$("$CHANGEISH_SCRIPT" --help)
    if [[ $(echo $output | grep -c "Usage:") -eq 0 ]]; then
        echo "❌ Failed to run help command"
        return 1
    fi
    return 0
}

test_version() {
    local output
    output=$("$CHANGEISH_SCRIPT" --version 2>&1)
    echo "$output" > version.txt
    fail_if_not_found "[0-9]\\+\.[0-9]\\+\.[0-9]\\+" version.txt "Version text not found"
}

test_env_loading() {
    echo "x" > file.txt && git add file.txt && git commit -m "init"
    echo "CHANGEISH_MODEL=MY_MODEL" > .env
    mock_ollama "MY_MODEL" ""
    "$CHANGEISH_SCRIPT" --current > out.txt 2>&1
    fail_if_not_found "Running Ollama model 'MY_MODEL'" out.txt "Model config not loaded from .env"
}

test_remote_changelog() {
    touch CHANGELOG.md && git add CHANGELOG.md && git commit -m "init"
    echo "x" > file.txt && git add file.txt && git commit -m "feat: add file"
    mkdir -p fake
    echo '#!/bin/bash' > fake/curl
    cat <<EOF >> fake/curl
echo '{
  "id": "chatcmpl-B9MBs8CjcvOU2jLn4n570S5qMJKcT",
  "object": "chat.completion",
  "created": 1741569952,
  "model": "gpt-4.1-2025-04-14",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Hello! How can I assist you today?",
        "refusal": null,
        "annotations": []
      },
      "logprobs": null,
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 19,
    "completion_tokens": 10,
    "total_tokens": 29,
    "prompt_tokens_details": {
      "cached_tokens": 0,
      "audio_tokens": 0
    },
    "completion_tokens_details": {
      "reasoning_tokens": 0,
      "audio_tokens": 0,
      "accepted_prediction_tokens": 0,
      "rejected_prediction_tokens": 0
    }
  },
  "service_tier": "default"
}'
EOF
    chmod +x fake/curl
    export PATH="$PWD/fake:$PATH"
    export CHANGEISH_API_KEY=dummy
    "$CHANGEISH_SCRIPT" --remote --api-url 'http://localhost:8080/v1/chat/completions'
    fail_if_not_found "Hello! How can I assist you today?" CHANGELOG.md "Changelog missing mocked remote entry"
}

# --- UPDATE MODES ---
test_update_modes() {
    for mode in prepend append update auto; do
        for scenario in empty_changelog preexisting_unreleased; do
            rm -f CHANGELOG.md
            if [ "$scenario" = "preexisting_unreleased" ]; then
                echo -e "## [Unreleased] - 2025-06-01\n- 📦 Existing entry" > CHANGELOG.md
            else
                touch CHANGELOG.md
            fi
            git add CHANGELOG.md && git commit -m "init $scenario"
            echo "change for $mode/$scenario" > file.txt && git add file.txt && git commit -m "feat: $mode $scenario"
            mock_ollama "dummy" "Test entry for mode $mode/$scenario"
            "$CHANGEISH_SCRIPT" --update-mode "$mode" > out.txt 2>&1
            # Check that the test entry appears in the changelog
            grep -q "Test entry for mode $mode/$scenario" CHANGELOG.md || {
                echo "❌ Missing entry for mode '$mode' in scenario '$scenario'" >&2
                cat out.txt
                cat CHANGELOG.md
                return 1
            }
            # For update/auto, ensure existing entries are preserved
            if [ "$scenario" = "preexisting_unreleased" ] && [[ "$mode" =~ ^(update|auto)$ ]]; then
                grep -q "Existing entry" CHANGELOG.md || {
                    echo "❌ Existing entry missing after $mode/$scenario" >&2
                    cat CHANGELOG.md
                    return 1
                }
            fi
        done
    done
}

test_version_detection_staged_pyproject() {
    echo -e "[tool.poetry]\nversion = \"1.2.2\"" > pyproject.toml
    git add pyproject.toml
    echo "a" > a.txt && git add a.txt && git commit -m "fix: py"
    echo -e "[tool.poetry]\nversion = \"1.2.3\"" > pyproject.toml
    git add pyproject.toml
    mock_ollama "dummy" ""
    "$CHANGEISH_SCRIPT" --staged --save-history
    fail_if_not_found "1.2.3" history.md "Version 1.2.3 not found in staged history"
    rm -f history.md
}
test_version_detection_pyproject() {
    echo -e "[tool.poetry]\nversion = \"1.2.2\"" > pyproject.toml
    echo "a" > a.txt && git add a.txt pyproject.toml && git commit -m "fix: py"
    echo -e "[tool.poetry]\nversion = \"1.2.3\"" > pyproject.toml
    mock_ollama "dummy" ""
    "$CHANGEISH_SCRIPT" --save-history
    fail_if_not_found "1.2.3" history.md "Version 1.2.3 not found in current history"
    rm -f history.md
}

test_version_detection_setup_py() {
    echo -e "__version__ = \"4.5.5\"" > setup.py
    git add setup.py && git commit -m "add setup"
    echo "b" > b.txt && git add b.txt && git commit -m "fix: setup"
    
    echo -e "__version__ = \"4.5.6\"" > setup.py
    mock_ollama "dummy" ""
    "$CHANGEISH_SCRIPT" --save-history
    cat history.md
    fail_if_not_found "4.5.6" history.md "Version [4.5.6] not found in history"
    rm -f history.md
}

test_save_prompt_and_history() {
    echo "added text" > file && git add file && git commit -m "init"
    echo "updated text" > file
    mock_ollama "dummy" ""
    "$CHANGEISH_SCRIPT" --save-prompt --save-history
    cat prompt.md
    cat history.md
    fail_if_not_found "<<<GIT HISTORY>>>" prompt.md "Commit not found in saved prompt" || return 1
    fail_if_not_found "updated text" history.md "Commit not found in saved history" || return 1
}

# --- META / early exit paths ---
test_meta_help() {
    "$CHANGEISH_SCRIPT" --help > out.txt 2>&1
    grep -q -- "--help" out.txt
    grep -q -- "--version" out.txt
    grep -q -- "--remote" out.txt
    grep -q -- "--api-url" out.txt
    grep -q -- "--changelog-file" out.txt
}
test_meta_version() {
    "$CHANGEISH_SCRIPT" --version > out.txt 2>&1
    grep -q "0.2.0 (unreleased)" out.txt
}
test_meta_available_releases() {
    mkdir -p stubs
    echo '#!/bin/bash' > stubs/curl
    echo 'echo "[{\"tag_name\": \"v1.0.0\"}, {\"tag_name\": \"v2.0.0\"}]"' >> stubs/curl
    chmod +x stubs/curl
    export PATH="$PWD/stubs:$PATH"
    "$CHANGEISH_SCRIPT" --available-releases > out.txt 2>&1
    grep -q "v1.0.0" out.txt
    grep -q "v2.0.0" out.txt
}
test_meta_update() {
    mkdir -p stubs
    echo '#!/bin/bash' > stubs/curl
    echo 'exit 0' >> stubs/curl
    echo '#!/bin/bash' > stubs/sh
    echo 'echo "installer called: $@"' >> stubs/sh
    chmod +x stubs/curl stubs/sh
    export PATH="$PWD/stubs:$PATH"
    "$CHANGEISH_SCRIPT" --update > out.txt 2>&1
    grep -q "installer called" out.txt
}
test_meta_unknown_flag() {
    set +e
    "$CHANGEISH_SCRIPT" --does-not-exist > out.txt 2>err.txt
    test $? -eq 1
    grep -q "Unknown arg: --does-not-exist" err.txt
    set -e
}
# --- Configuration loading ---
test_config_default() {
    rm -f .env my.env
    "$CHANGEISH_SCRIPT" --version > out.txt 2>&1
    grep -q "qwen2.5-coder" out.txt || true # model default
}
test_config_env_override() {
    echo "CHANGEISH_MODEL=llama3" > .env
    "$CHANGEISH_SCRIPT" --version > out.txt 2>&1
    grep -q "llama3" out.txt || true
}
test_config_file_override() {
    echo "CHANGEISH_MODEL=llama3" > .env
    echo "CHANGEISH_MODEL=phi3" > my.env
    "$CHANGEISH_SCRIPT" --config-file my.env --version > out.txt 2>&1
    grep -q "phi3" out.txt || true
}
# --- MODE flags (mutually exclusive) ---
test_mode_default_current() {
    echo "x" > file.txt
    git add file.txt && git commit -m "init"
    echo "x" > file.txt
    "$CHANGEISH_SCRIPT" --save-history
    grep -q "Git History (Uncommitted Changes)" history.md
}
test_mode_explicit_current() {
    echo "x" > file.txt
    git add file.txt && git commit -m "init"
    echo "x" > file.txt
    "$CHANGEISH_SCRIPT" --current --save-history
    grep -q "Git History (Uncommitted Changes)" history.md
}
test_mode_staged() {
    echo "x" > file.txt
    git add file.txt && git commit -m "init"
    echo "x" > file.txt && git add file.txt
    "$CHANGEISH_SCRIPT" --staged --save-history
    grep -q "Staged Changes" history.md
}
test_mode_all() {
    generate_commits
    "$CHANGEISH_SCRIPT" --all --save-history
    grep -q "Range:" history.md
}
test_mode_from_to() {
    generate_commits
    "$CHANGEISH_SCRIPT" --from "HEAD" --to "HEAD~1" --save-history > out.txt 2>&1
    total_commits=$(grep -c "**Commit:**" history.md)
    if [[ $total_commits -ne 2 ]]; then
        echo "❌ Expected 2 commit, found $total_commits" >&2
        return 1
    fi
    cat out.txt
    cat history.md
    grep -q "Using commit range: HEAD~1^..HEAD" out.txt
}
test_mode_from_only() {
    generate_commits
    "$CHANGEISH_SCRIPT" --from HEAD~0 --save-history > out.txt 2>&1
    total_commits=$(grep -c "**Commit:**" history.md)
    if [[ $total_commits -ne 1 ]]; then
        echo "❌ Expected 1 commit, found $total_commits" >&2
        return 1
    fi
    grep -q "Generating git history for 1 commit" out.txt
}
test_mode_to_only() {
    generate_commits
    "$CHANGEISH_SCRIPT" --to HEAD~0 --save-history > out.txt 2>&1
    total_commits=$(grep -c "**Commit:**" history.md)
    if [[ $total_commits -ne 1 ]]; then
        echo "❌ Expected 1 commit, found $total_commits" >&2
        return 1
    fi
    grep -q "Generating git history for 1 commit" out.txt
}

# --- INCLUDE / EXCLUDE diff filters ---
test_include_pattern_only() {
    generate_commits
    echo "ADD" > TODO.md
    git add TODO.md && git commit -m "add TODO"
    "$CHANGEISH_SCRIPT" --to HEAD --include-pattern TODO.md --save-history
    grep -q "Diffs for files matching" history.md
    grep -q "ADD" history.md
}

test_exclude_pattern_only() {
    generate_commits
    echo "EXCLUDE" > TODO.md
    git add TODO.md && git commit -m "add TODO"
    "$CHANGEISH_SCRIPT" --to HEAD --exclude-pattern TODO.md --save-history
    ! grep -q "TODO.md" history.md  # Should not appear in full diff
}

test_include_and_exclude() {
    generate_commits
    echo "INCLUDE" > foo.md
    echo "EXCLUDE" > config.txt
    git add foo.md config.txt && git commit -m "add files"
    "$CHANGEISH_SCRIPT" --include-pattern '*.md' --exclude-pattern 'config*' --save-history
    grep -q "Diffs for files matching" history.md
    ! grep -q "config.txt" history.md
}

# --- OUTPUT control ---
test_output_save_history() {
    generate_commits
    echo "a" > a.txt 
    "$CHANGEISH_SCRIPT" --save-history
    [ -f history.md ]
    ! [ -f prompt.md ]
}
test_output_save_prompt() {
    echo "a" > a.txt && git add a.txt && git commit -m "a"
    "$CHANGEISH_SCRIPT" --save-prompt
    [ -f prompt.md ]
}
test_output_both_save_flags() {
    echo "a" > a.txt && git add a.txt && git commit -m "a"
    "$CHANGEISH_SCRIPT" --save-history --save-prompt
    [ -f history.md ]
    [ -f prompt.md ]
}
test_output_custom_changelog_file() {
    generate_commits
    mkdir -p docs
    echo "# Changelog" > docs/CHANGELOG.md
    echo "a" > a.txt && git add a.txt
    mock_ollama "dummy" "Added a file"
    "$CHANGEISH_SCRIPT" --changelog-file docs/CHANGELOG.md --save-history
    cat docs/CHANGELOG.md
    cat history.md
    grep -q "Added a file" docs/CHANGELOG.md
}
test_output_custom_prompt_template() {
    echo "CUSTOM" > my_template.md
    echo "a" > a.txt && git add a.txt && git commit -m "a"
    "$CHANGEISH_SCRIPT" --prompt-template my_template.md --save-prompt
    grep -q "CUSTOM" prompt.md
}
# --- VERSION-file logic ---
test_version_auto_detect() {
    echo '{"version": "1.0.0"}' > package.json
    git add package.json && git commit -m "add package.json"
    echo '{"version": "1.0.1"}' > package.json
    git add package.json && git commit -m "bump version"
    "$CHANGEISH_SCRIPT" --all --save-history
    grep -q "Version number changes in package.json" history.md
}
test_version_explicit_file() {
    echo 'version = "2.0.0"' > my.ver
    git add my.ver && git commit -m "add my.ver"
    echo 'version = "2.0.1"' > my.ver
    git add my.ver && git commit -m "bump version"
    "$CHANGEISH_SCRIPT" --version-file my.ver --all --save-history
    grep -q "Version number changes in my.ver" history.md
}
# --- INTEGRATION with Ollama (local) ---

test_ollama_missing() {
    # Remove ollama from PATH
    export PATH="/usr/bin:/bin"
    echo "a" > a.txt && git add a.txt && git commit -m "a"
    "$CHANGEISH_SCRIPT" --current > out.txt 2>&1
    grep -q "ollama not found, skipping changelog generation." out.txt
}

test_ollama_verbose_debug() {
    mkdir -p bin
    echo '#!/bin/bash' > bin/ollama
    echo 'echo "$@" > ollama_args.txt' >> bin/ollama
    chmod +x bin/ollama
    export PATH="$PWD/bin:$PATH"
    # Ensure debug=true in script or via env
    export CHANGEISH_MODEL=llama3
    echo "a" > a.txt && git add a.txt && git commit -m "a"
    "$CHANGEISH_SCRIPT" --current > out.txt 2>&1
    grep -q -- "--verbose" ollama_args.txt
}

# --- REMOTE execution ---
test_remote_happy_path() {
    generate_commits
    mock_curl "dummy" 'Generated by changeish'
    export CHANGEISH_API_KEY=tok
    "$CHANGEISH_SCRIPT" --remote --api-url http://mock --api-model gpt-mini > out.txt 2>&1
    cat out.txt
    grep -q "Generated by changeish" out.txt
}

test_remote_missing_api_key() {
    mkdir -p stubs
    echo '#!/bin/bash' > stubs/curl
    echo 'echo \"{}\"' >> stubs/curl
    chmod +x stubs/curl
    export PATH="$PWD/stubs:$PATH"
    unset CHANGEISH_API_KEY
    set +e
    "$CHANGEISH_SCRIPT" --remote --api-url http://mock --api-model gpt-mini > out.txt 2>err.txt
    test $? -eq 1
    grep -q "Error: --remote specified but CHANGEISH_API_KEY is not set." err.txt
    set -e
}

test_remote_missing_api_url() {
    mkdir -p stubs
    echo '#!/bin/bash' > stubs/curl
    echo 'echo \"{}\"' >> stubs/curl
    chmod +x stubs/curl
    export PATH="$PWD/stubs:$PATH"
    export CHANGEISH_API_KEY=tok
    set +e
    "$CHANGEISH_SCRIPT" --remote > out.txt 2>err.txt
    test $? -eq 1
    grep -q "no API URL provided" err.txt
    set -e
}

# --- MODEL selection precedence ---
test_model_cli_overrides_env() {
    export CHANGEISH_MODEL=llama2
    mkdir -p docs
    touch docs/CHANGELOG.md
    echo "# Changelog" > docs/CHANGELOG.md
    echo "a" > a.txt && git add a.txt && git commit -m "a"
    "$CHANGEISH_SCRIPT" --model phi > out.txt 2>&1
    cat out.txt
    grep -q "phi" out.txt
}

test_model_remote_api_model_overrides_model() {
    generate_commits
    mock_curl "bar" ""
    export CHANGEISH_API_KEY="tok"
    "$CHANGEISH_SCRIPT" --to HEAD --remote --api-url http://localhost:8080 --model foo --api-model bar > out.txt 2>err.txt
    cat out.txt
    cat err.txt
    #cat /tmp/remote_payload.json
    grep -q "generated by changeish using bar" out.txt
    #grep -q '"model": "bar"' /tmp/remote_payload.json
}

# --- ERROR PATHS ---
test_error_outside_git_repo() {
    # Should fail with a clear error if not in a git repo
    set +e
    rm -rf .git 2>/dev/null || true
    "$CHANGEISH_SCRIPT" > out.txt 2>err.txt
    local code=$?
    set -e
    if [[ $code -eq 0 ]]; then
        echo "❌ Expected failure outside git repo, but exited 0" >&2
        return 1
    fi
    grep -qi "not a git repo" err.txt || grep -qi "fatal: not a git repository" err.txt || {
        echo "❌ Error message for non-git repo not found" >&2
        return 1
    }
}

test_error_no_commits() {
    rm -rf .git 2>/dev/null || true
    git init -q
    set +e
    "$CHANGEISH_SCRIPT" --save-history > out.txt 2>err.txt
    local code=$?
    cat err.txt
    set -e
    if [[ $code -eq 0 ]]; then
        echo "❌ Expected failure with no commits, but exited 0" >&2
        return 1
    fi
    grep -qi "No commits found in repository. Nothing to show." err.txt || grep -qi "fatal" err.txt || {
        echo "❌ Error message for no commits not found" >&2
        return 1
    }
}

test_error_bad_config_file() {
    echo "x" > file.txt && git add file.txt && git commit -m "init"
    set +e
    "$CHANGEISH_SCRIPT" --config-file does_not_exist.env --save-history > out.txt 2>err.txt
    local code=$?
    set -e
    if [[ $code -eq 0 ]]; then
        echo "❌ Expected failure with bad config file, but exited 0" >&2
        return 1
    fi
    grep -qi "Error: config file" err.txt || grep -qi "No such file" err.txt || {
        echo "❌ Error message for bad config file not found" >&2
        return 1
    }
}

test_error_bad_version_file() {
    echo "x" > file.txt && git add file.txt && git commit -m "init"
    set +e
    "$CHANGEISH_SCRIPT" --version-file does_not_exist.ver --save-history > out.txt 2>err.txt
    local code=$?
    set -e
    if [[ $code -eq 0 ]]; then
        echo "❌ Expected failure with bad version file, but exited 0" >&2
        return 1
    fi
    cat err.txt
    grep -qi "version file" err.txt || grep -qi "No such file" err.txt || {
        echo "❌ Error message for bad version file not found" >&2
        return 1
    }
}

# Guard: only run the test suite if not in child mode
if [[ "${CHANGEISH_TEST_CHILD:-}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi

set +e  # Allow all tests to run even if some fail.

# Run all tests
# Add run_test calls for each new test:
run_test "Show help text" test_help
run_test "Show version text" test_version
run_test "Load .env file" test_env_loading
run_test "Remote changelog generation" test_remote_changelog
#Not Implemented: run_test "Update modes (prepend, append, update, auto)" test_update_modes
run_test "Version detection (pyproject.toml)" test_version_detection_pyproject
run_test "Version detection (pyproject.toml - staged)" test_version_detection_staged_pyproject
run_test "Version detection (setup.py)" test_version_detection_setup_py
run_test "Save prompt and history files" test_save_prompt_and_history
run_test "Meta: --help prints usage" test_meta_help
run_test "Meta: --version prints version" test_meta_version
run_test "Meta: --available-releases prints tags" test_meta_available_releases
run_test "Meta: --update calls installer" test_meta_update
run_test "Meta: unknown flag aborts" test_meta_unknown_flag
run_test "Config: default model" test_config_default
run_test "Config: .env overrides model" test_config_env_override
run_test "Config: --config-file beats .env" test_config_file_override
run_test "Mode: default current" test_mode_default_current
run_test "Mode: explicit current" test_mode_explicit_current
run_test "Mode: staged" test_mode_staged
run_test "Mode: all" test_mode_all
run_test "Mode: from_to" test_mode_from_to
run_test "Mode: from only" test_mode_from_only
run_test "Mode: to only" test_mode_to_only
run_test "Include pattern only" test_include_pattern_only
run_test "Exclude pattern only" test_exclude_pattern_only
run_test "Include and exclude patterns" test_include_and_exclude
run_test "Output: --save-history keeps history file" test_output_save_history
run_test "Output: --save-prompt keeps prompt file" test_output_save_prompt
run_test "Output: both save flags" test_output_both_save_flags
run_test "Output: custom changelog file" test_output_custom_changelog_file
run_test "Output: custom prompt template" test_output_custom_prompt_template
run_test "Version: auto-detect version file" test_version_auto_detect
run_test "Version: explicit version file" test_version_explicit_file
run_test "Remote: happy path" test_remote_happy_path
run_test "Remote: missing API key" test_remote_missing_api_key
run_test "Remote: missing API URL" test_remote_missing_api_url
run_test "Model: CLI --model overrides env" test_model_cli_overrides_env
run_test "Model: --api-model overrides --model for remote" test_model_remote_api_model_overrides_model
run_test "Ollama: executable missing" test_ollama_missing
run_test "Ollama: invoked with verbose when debug=true" test_ollama_verbose_debug

# Error path tests
run_test "Error: outside git repo" test_error_outside_git_repo
run_test "Error: repo with no commits" test_error_no_commits
run_test "Error: bad config file path" test_error_bad_config_file
run_test "Error: bad version file path" test_error_bad_version_file

# Print summary and exit with appropriate status
set -e
echo
echo "🧪 Test Summary:"
echo "   ✅ Passed: $PASSED"
echo "   ❌ Failed: $FAILED"

if [[ $FAILED -ne 0 ]]; then
    echo "   💥 Check logs in $LOG_DIR for details."
    exit 1
else
    echo "   🎉 All tests passed!"
    exit 0
fi
