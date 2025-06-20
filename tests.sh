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
    local TMP_REPO_DIR
    TMP_REPO_DIR="$(mktemp -d)"
    trap 'rm -rf "$TMP_REPO_DIR"' EXIT
    
    local ORIG_DIR="$PWD"
    #echo "Running test: $name"
    local LOGFILE="$LOG_DIR/${name// /_}.log"
    # Run the test in a temp git repo, sourcing this script for function definitions.
    cd "$TMP_REPO_DIR"
    git init -q
    (
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

# mock_ollama: Helper to mock the ollama binary for local model tests.
# - Creates a fake bin/ollama script that echoes the model and content.
# - Ensures the test does not require the real ollama binary.
mock_ollama() {
    local model="$1"
    local content="$2"
    echo "Running Ollama model '$model'..."
    mkdir -p bin
    echo '#!/bin/bash' > bin/ollama
    echo 'echo "$content"' >> bin/ollama
    chmod +x bin/ollama
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

test_update_modes() {
    for mode in prepend append update auto; do
        for scenario in no_section has_section; do
            if [ "$scenario" = "has_section" ]; then
                echo -e "## [Unreleased] - 2025-06-01\n- 📦 Existing entry" > CHANGELOG.md
            else
                touch CHANGELOG.md
            fi
            git add CHANGELOG.md && git commit -m "init"
            echo "change" > file.txt && git add file.txt && git commit -m "feat: $mode test"

            export PATH="$PWD/bin:$PATH"
            "$CHANGEISH_SCRIPT" --update-mode "$mode" 
            fail_if_not_found "Test entry for mode $mode" CHANGELOG.md "Missing entry for mode '$mode'" || return 1
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

# Guard: only run the test suite if not in child mode
if [[ "${CHANGEISH_TEST_CHILD:-}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi

set +e  # Allow all tests to run even if some fail.

# Run all tests
run_test "Show help text" test_help
run_test "Show version text" test_version
run_test "Load .env file" test_env_loading
run_test "Remote changelog generation" test_remote_changelog
#Not Implemented: run_test "Update modes (prepend, append, update, auto)" test_update_modes
run_test "Version detection (pyproject.toml)" test_version_detection_pyproject
run_test "Version detection (pyproject.toml - staged)" test_version_detection_staged_pyproject
run_test "Version detection (setup.py)" test_version_detection_setup_py
run_test "Save prompt and history files" test_save_prompt_and_history
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
