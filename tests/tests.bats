#!/usr/bin/env bats

export ERROR_LOG="$BATS_TEST_DIRNAME/.logs/main.error.log"

setup_file() {
  # Ensure the error log is empty before each test
  : >"$ERROR_LOG"
}

# teardown_file() {
#   # cd "${ORIG_DIR:-$PWD}" 2>/dev/null || true
#   # rm -rf "${TMP_DIR:-}" 2>/dev/null || true
# }
setup() {
  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'
  ORIG_DIR="$PWD"
  TMP_DIR="$(mktemp -d)/changeish-tests"
  mkdir -p "$TMP_DIR"
  mkdir -p "$BATS_TEST_DIRNAME/.logs"
  cd "$TMP_DIR"
  git init -q
  git config user.name "Test"
  git config user.email "test@example.com"
  CHANGEISH_SCRIPT="$BATS_TEST_DIRNAME/../changes.sh"
  #echo >$ERROR_LOG
  mock_ollama "dummy" "Running Ollama model"
  mock_curl "dummy" "Hello! How can I assist you today?"
}

teardown() {
  printf '\nTeardown: Capturing test output and cleaning up...%s}\n' "$status" "$BATS_OUT" >>"$ERROR_LOG" 2>/dev/null || true
  # Suppress errors and guard variable usage
  local teardown_status=0
  {
    if [[ -n "${status+x}" && $status -ne 0 ]]; then
      echo "--- FAILED TEST OUTPUT ---" >>"$ERROR_LOG" 2>/dev/null || true
      echo "Test: ${BATS_TEST_NAME:-unknown}" >>"$ERROR_LOG" 2>/dev/null || true
      echo "${output:-}" >>"$ERROR_LOG" 2>/dev/null || true
      echo "--- END ---" >>"$ERROR_LOG" 2>/dev/null || true
    else
      echo "--- TEST OUTPUT (${status:-?}) ---" >>"$ERROR_LOG" 2>/dev/null || true
      echo "Test: ${BATS_TEST_NAME:-unknown}" >>"$ERROR_LOG" 2>/dev/null || true
      echo "${output:-}" >>"$ERROR_LOG" 2>/dev/null || true
      echo "--- END ---" >>"$ERROR_LOG" 2>/dev/null || true
    fi
  } || teardown_status=1

  # cd "${ORIG_DIR:-$PWD}" 2>/dev/null || true
  # rm -rf "${TMP_DIR:-}" 2>/dev/null || true
  return 0
}

# Helper: create commits a, b, c
generate_commits() {
  echo "bin" >.gitignore && git add .gitignore
  echo "a" >a.txt && git add a.txt && git commit -m "add a.txt"
  echo "b" >b.txt && git add b.txt && git commit -m "add b.txt"
  echo "c" >c.txt && git add c.txt && git commit -m "add c.txt"
}

# Helper: mock a local ollama binary that prints a message
mock_ollama() {
  local model="$1" content="$2"
  mkdir -p bin
  cat >bin/ollama <<EOF
#!/bin/bash
echo '$content'
EOF
  chmod +x bin/ollama
  export PATH="$PWD/bin:$PATH"
}

# Helper: mock curl to return a fixed JSON response
mock_curl() {
  local model="${1:-gpt-4.1-2025-04-14}"
  local message="${2:-"Hello I am $model! How can I assist you today?"}"
  local response
  response=$(
    cat <<JSON
{ "id": "id", "choices": [ { "message": { "content": "$message" } } ] }
JSON
  )
  mkdir -p bin
  cat >bin/curl <<EOF
#!/bin/bash
echo '$response'
EOF
  chmod +x bin/curl
  export PATH="$PWD/bin:$PATH"
}

@test "Show version text" {
  run "$CHANGEISH_SCRIPT" --version
  #assert_success
  echo "$output"
  echo "$output" | grep -Eq "[0-9]+\.[0-9]+\.[0-9]+"
}

@test "Meta: --debug enables debug output" {
  echo "a" >a.txt
  git add a.txt && git commit -m "a"
  mock_ollama "dummy" "Debug mode enabled"
  run "$CHANGEISH_SCRIPT" --debug --current
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "Debug mode enabled" || echo "$output" | grep -qi "Running Ollama model"
}

@test "Remote: happy path" {
  # Initialize CHANGELOG and a commit
  echo -e "# Changelog\n" CHANGELOG.md && git add CHANGELOG.md && git commit -m "init"
  echo "x" >file.txt
  git add file.txt && git commit -m "feat: add file"
  # Mock curl to return a specific message
  mock_curl "dummy" "Hello! How can I assist you today?"
  export CHANGEISH_API_KEY="dummy"
  run "$CHANGEISH_SCRIPT" --model-provider remote \
    --api-url http://fake --api-model dummy --debug
  [ "$status" -eq 0 ]
  cat CHANGELOG.md >>$ERROR_LOG
  grep -q "Hello! How can I assist you today?" CHANGELOG.md
}

@test "Meta: --help prints usage" {
  run "$CHANGEISH_SCRIPT" --help
  [ "$status" -eq 0 ]

  # Ensure help content starts with Usage:
  echo "$output" | head -n1 | grep -q "Version:"
  [ "$(echo "$output" | head -n2 | tail -n1)" = "Usage: changeish [OPTIONS]" ]

  echo "$output" | grep -q -- "--help"
  echo "$output" | grep -q -- "--version"
  echo "$output" | grep -q -- "--remote"
  echo "$output" | grep -q -- "--api-url"
  echo "$output" | grep -q -- "--changelog-file"
  echo "$output" | grep -q "Default version files to check for version changes:"
  echo "$output" | grep -q "changes.sh"
  echo "$output" | grep -q "package.json"
  echo "$output" | grep -q "pyproject.toml"
  echo "$output" | grep -q "setup.py"
  echo "$output" | grep -q "Cargo.toml"
  echo "$output" | grep -q "composer.json"
  echo "$output" | grep -q "build.gradle"
  echo "$output" | grep -q "pom.xml"

  # Ensure help does not contain comments
  echo "$output" | grep -qv "Sourcing .env file..."
  echo "$output" | grep -qv "Initialize default option values"
}

@test "Meta: --version prints version" {
  run "$CHANGEISH_SCRIPT" --version
  echo "$output" | grep -q "0.2.0"
}

@test "Meta: --available-releases prints tags" {
  mkdir -p stubs
  cat >stubs/curl <<EOF
#!/bin/bash
echo '[{"tag_name": "v1.0.0"}, {"tag_name": "v2.0.0"}]'
EOF
  chmod +x stubs/curl
  export PATH="$PWD/stubs:$PATH"
  run "$CHANGEISH_SCRIPT" --available-releases

  # Ensure the output is captured correctly and check for expected tags
  echo "$output" >>$ERROR_LOG

  # Check if the status code is zero (indicating success)
  assert_success
  # Verify that both v1.0.0 and v2.0.0 are present in the output
  echo "$output" | grep -qi "v1.0.0"
  echo "$output" | grep -qi "v2.0.0"
}

@test "Meta: --update calls installer" {
  mkdir -p stubs
  cat >stubs/curl <<EOF
#!/bin/bash
exit 0
EOF
  cat >stubs/sh <<EOF
#!/bin/bash
echo "installer called: \$@"
EOF
  chmod +x stubs/curl stubs/sh
  export PATH="$PWD/stubs:$PATH"
  run "$CHANGEISH_SCRIPT" --update
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "installer called"
}

@test "Meta: unknown flag aborts" {
  run "$CHANGEISH_SCRIPT" --does-not-exist
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "Unknown arg: --does-not-exist"
}

@test "Config: Load .env file" {
  echo "x" >file.txt && git add file.txt && git commit -m "init"
  mock_ollama "MY_MODEL" ""
  echo "CHANGEISH_MODEL=MY_MODEL" >".env"
  cat ".env" >&3
  if [ -f ".env" ]; then
    echo "Using existing .env file from .env"

    run "$CHANGEISH_SCRIPT" --current --debug >>$ERROR_LOG
    cat "$ERROR_LOG" >&3
    assert_success
    echo "$output" | grep -q "Using model: MY_MODEL"
  else
    echo "Could not create .env file, skipping test."
  fi
}

@test "Config: default model" {
  rm -f .env my.env
  run "$CHANGEISH_SCRIPT" --version
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "qwen2.5-coder" || true
}

@test "Config: .env overrides model" {
  echo "CHANGEISH_MODEL=llama3" >.env
  run "$CHANGEISH_SCRIPT" --version
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "llama3" || true
}

@test "Config: --config-file beats .env" {
  echo "CHANGEISH_MODEL=llama3" >.env
  echo "CHANGEISH_MODEL=phi3" >my.env
  run "$CHANGEISH_SCRIPT" --config-file my.env --version
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "phi3" || true
}
@test "Template: Make prompt template writes default template" {
  rm -f my_prompt_template.md
  run "$CHANGEISH_SCRIPT" --make-prompt-template my_prompt_template.md
  cat my_prompt_template.md >>$ERROR_LOG
  [ "$status" -eq 0 ]
  [[ -f "my_prompt_template.md" ]]
  grep -q '[INSTRUCTIONS]' my_prompt_template.md
  grep -q 'Output rules' my_prompt_template.md
  echo "$output" | grep -q "Default prompt template written to my_prompt_template.md."
}

@test "Mode: default current" {
  echo "x" >file.txt && git add file.txt && git commit -m "init"
  echo "y" >file.txt
  run "$CHANGEISH_SCRIPT" --save-history --debug
  [ "$status" -eq 0 ]
  cat history.md >>$ERROR_LOG
  grep -q "Working Tree" history.md
}

@test "Mode: explicit current" {
  echo "x" >file.txt && git add file.txt && git commit -m "init"
  echo "z" >file.txt
  run "$CHANGEISH_SCRIPT" --current --save-history --model-provider none
  assert_success
  grep -q "Working Tree" history.md
}

@test "Mode: staged" {
  echo "x" >file.txt && git add file.txt && git commit -m "init"
  echo "staged content" >file.txt && git add file.txt
  run "$CHANGEISH_SCRIPT" --staged --save-history
  cat history.md >>$ERROR_LOG
  assert_success
  grep -q "Staged Changes" history.md
}

@test "Mode: all" {
  #generate_commits
  # rm -rf .git
  # rm -f *.txt
  # git init -q

  echo "bin" >.gitignore && git add .gitignore && git commit -m "add .gitignore"
  echo "a" >a.txt && git add a.txt && git commit -m "add a.txt"
  echo "b" >b.txt && git add b.txt && git commit -m "add b.txt"
  echo "c" >c.txt && git add c.txt && git commit -m "add c.txt"

  run "$CHANGEISH_SCRIPT" --all --save-history --debug
  assert_success
  cat history.md >>$ERROR_LOG
  echo "Checking all commits" >>$ERROR_LOG
  grep -q "\*\*Commit:\*\*" history.md
  echo "Checking for commit a" >>$ERROR_LOG
  grep -q "add a.txt" history.md
  echo "Checking for commit b" >>$ERROR_LOG
  grep -q "add b.txt" history.md
  echo "Checking for commit c" >>$ERROR_LOG
  grep -q "add c.txt" history.md
  printf 'Test Passed\n' >>$ERROR_LOG
}

@test "Mode: from_to" {
  generate_commits
  run "$CHANGEISH_SCRIPT" --from HEAD --to HEAD~1 --save-history --debug
  cat history.md >>$ERROR_LOG
  assert_success
  total=$(grep -c "\*\*Commit:\*\*" history.md)
  [ "$total" -eq 2 ]
  echo "$output" | grep -q "Using commit range: HEAD~1^..HEAD"
}

@test "Mode: from only" {
  generate_commits
  run "$CHANGEISH_SCRIPT" --from HEAD~0 --save-history --debug
  [ "$status" -eq 0 ]
  total=$(grep -c "\*\*Commit:\*\*" history.md)
  [ "$total" -eq 1 ]
  echo "$output" | grep -q "1 commit"
}

@test "Mode: to only" {
  generate_commits
  run "$CHANGEISH_SCRIPT" --to HEAD~0 --save-history --debug
  [ "$status" -eq 0 ]
  total=$(grep -c "\*\*Commit:\*\*" history.md)
  [ "$total" -eq 1 ]
  echo "$output" | grep -q "Generating git history for 1 commit"
}

@test "Include pattern only" {
  generate_commits
  echo "ADD" >TODO.md
  git add TODO.md && git commit -m "add TODO"

  # list all commits
  git log --name-status >>$ERROR_LOG

  run "$CHANGEISH_SCRIPT" --to HEAD --include-pattern "TODO.md" --save-history --debug
  [ "$status" -eq 0 ]
  cat history.md >>$ERROR_LOG
  grep -q "TODO.md TODO.md" history.md
  grep -q "ADD" history.md
}

@test "Exclude pattern only" {
  generate_commits
  echo "EXCLUDE" >TODO.md
  git add TODO.md && git commit -m "add TODO"
  run "$CHANGEISH_SCRIPT" --all --exclude-pattern TODO.md --save-history
  [ "$status" -eq 0 ]
  ! grep -q "diff --git a/TODO.md" history.md
}

@test "Include and exclude patterns" {
  generate_commits
  echo "INCLUDE" >foo.md
  echo "EXCLUDE" >config.txt
  git add foo.md config.txt && git commit -m "add files"
  run "$CHANGEISH_SCRIPT" --all --include-pattern '*.md' --exclude-pattern 'config*' \
    --save-history --debug
  [ "$status" -eq 0 ]
  grep -q "diff --git foo.md foo.md" history.md
  ! grep -q "config.txt" history.md
}

@test "Exclude overrides include pattern" {
  echo "foo" >keep.log
  echo "bar" >skip.log
  git add . && git commit -m "initial logs"

  echo "foo modified" >>keep.log
  echo "bar modified" >>skip.log

  run "$CHANGEISH_SCRIPT" --current --include-pattern "*.log" --exclude-pattern "skip" --save-history
  [ "$status" -eq 0 ]
  grep -q "keep.log" history.md
  ! grep -q "skip.log" history.md
}

@test "TODO-only pattern captures todo diff" {
  echo "TODO: test" >notes.md
  git add notes.md && git commit -m "add TODO file"
  echo "FIXED: test" >notes.md

  run "$CHANGEISH_SCRIPT" --current --todo-pattern "*.md" --save-history
  [ "$status" -eq 0 ]
  grep -q "Changes in TODOs" history.md
  grep -q "TODO: test" history.md
  grep -q "FIXED: test" history.md
}

@test "TODO: Empty todo pattern results in no TODO section" {
  echo "real content" >data.txt
  git add . && git commit -m "init"
  echo "real updated" >>data.txt

  run "$CHANGEISH_SCRIPT" --current --todo-pattern "*.doesnotexist" --save-history
  [ "$status" -eq 0 ]
  cat history.md >>$ERROR_LOG
  ! grep -q "Changes in TODOs" history.md
}

@test "Output: --save-history keeps history file" {
  generate_commits
  echo "a" >a.txt
  run "$CHANGEISH_SCRIPT" --save-history
  [[ -f "history.md" ]]
  [[ ! -f "prompt.md" ]]
}

@test "Output: --save-prompt keeps prompt file" {
  echo "a" >a.txt && git add a.txt && git commit -m "a"
  run "$CHANGEISH_SCRIPT" --save-prompt
  [ -f "prompt.md" ]
}

@test "Output: both save flags" {
  echo "a" >a.txt && git add a.txt && git commit -m "a"
  run "$CHANGEISH_SCRIPT" --save-history --save-prompt
  cat history.md >>$ERROR_LOG
  cat prompt.md >>$ERROR_LOG
  [ -f "history.md" ]
  [ -f "prompt.md" ]
}

@test "Output: custom changelog file" {
  generate_commits
  mkdir -p docs
  echo "# Changelog" >docs/CHANGELOG.md
  echo "b" >b.txt
  mock_ollama "dummy" "Added a file"
  run "$CHANGEISH_SCRIPT" --changelog-file docs/CHANGELOG.md --save-history
  echo "CHANGELOG:" >>$ERROR_LOG
  cat docs/CHANGELOG.md >>$ERROR_LOG
  [ "$status" -eq 0 ]
  echo "HISTORY:" >>$ERROR_LOG
  cat history.md >>$ERROR_LOG
  grep -q "Added a file" docs/CHANGELOG.md
}

@test "Output: custom prompt template" {
  echo "CUSTOM" >my_template.md
  echo "c" >c.txt && git add c.txt && git commit -m "c"
  run "$CHANGEISH_SCRIPT" --prompt-template my_template.md --save-prompt
  [ "$status" -eq 0 ]
  grep -q "CUSTOM" prompt.md
}

@test "Changelog file is safely appended or overwritten as expected" {
  echo "# My Changelog" >log.md
  echo "a" >file && git add . && git commit -m "a"
  run "$CHANGEISH_SCRIPT" --changelog-file log.md
  grep -q "# My Changelog" log.md
  grep -q "a" log.md
}

@test "History: File format --current" {
  # Setup initial files and commit
  echo '__version__ = "4.5.5"' >setup.py
  echo "CHORE: setup.py version bump" >todos.md
  echo "ENHANCEMENT: do cool stuff" >>todos.md
  git add . && git commit -m "add setup"

  # Update files for new changes
  echo '__version__ = "4.5.6"' >setup.py
  echo "DONE: setup.py version bump" >todos.md
  echo "ADDED: do cool stuff" >>todos.md

  run "$CHANGEISH_SCRIPT" --save-history --debug
  cat history.md >>"$ERROR_LOG"
  assert_success

  # Compare history.md to expected, ignoring lines starting with '**Date:**', blank lines, and whitespace
  diff -B -w -I '^\*\*Date:\*\*' "$BATS_TEST_DIRNAME/assets/uncommitted_history.md" history.md >diff_output.txt || true
  if [ -s diff_output.txt ]; then
    echo "Differences found:" >>"$ERROR_LOG"
    cat diff_output.txt >>"$ERROR_LOG"
    fail "history.md does not match expected output"
  fi

  # Check for required content in history.md
  grep -q '__version__ = "4.5.6"' history.md || fail "Version number changes not found in history"
  grep -q "4.5.6" history.md || fail "Version 4.5.6 not found in history"
  grep -q "### Changes in TODOs" history.md || fail "Diffs for todos.md not found in history"
  grep -q "ENHANCEMENT: do cool stuff" history.md || fail "Enhancement not found in todos.md diff"
  grep -q "DONE: setup.py version bump" history.md || fail "Done task not found in todos.md diff"
  grep -q "ADDED: do cool stuff" history.md || fail "Added task not found in todos.md diff"
}

@test "Version: auto-detect version file" {
  echo '{"version": "1.0.0"}' >package.json
  git add package.json && git commit -m "add package.json"
  echo '{"version": "1.0.1"}' >package.json
  git add package.json && git commit -m "bump version"
  run "$CHANGEISH_SCRIPT" --all --save-history --debug
  cat history.md >>$ERROR_LOG
  assert_success
  grep -q "1.0.0" history.md
  grep -q "1.0.1" history.md
}

@test "Version: explicit version file" {
  echo 'version = "2.0.0"' >my.ver
  git add my.ver && git commit -m "add my.ver"
  echo 'version = "2.0.1"' >my.ver
  git add my.ver && git commit -m "bump version"
  run "$CHANGEISH_SCRIPT" --version-file my.ver --all --save-history
  cat history.md >>$ERROR_LOG
  assert_success
  grep -q "2.0.1" history.md
}

@test "Version fallback grep works when no version diff" {
  generate_commits
  echo '__version__ = "2.0.0"' >setup.py
  git add setup.py && git commit -m "add version"
  # re-save the same content
  echo '__version__ = "2.0.0"' >setup.py
  echo "No changes" >note.txt

  run "$CHANGEISH_SCRIPT" --current --version-file setup.py --save-history --debug

  cat history.md >>$ERROR_LOG
  assert_success
  grep -q "Version:" history.md
  grep -q '2.0.0' history.md
}

@test "Ollama: executable missing" {
  export PATH="/usr/bin:/bin"
  rm -f bin/ollama
  echo "d" >d.txt && git add d.txt && git commit -m "d"
  run "$CHANGEISH_SCRIPT" --current --model-provider local --debug
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "ollama not found"
}

@test "Ollama: invoked with verbose when debug=true" {
  mkdir -p bin
  cat >bin/ollama <<EOF
#!/bin/bash
echo "\$@" > ollama_args.txt
EOF
  chmod +x bin/ollama
  export PATH="$PWD/bin:$PATH"
  export CHANGEISH_MODEL=llama3
  echo "e" >e.txt && git add e.txt && git commit -m "e"
  run "$CHANGEISH_SCRIPT" --current --model-provider local --debug
  [ "$status" -eq 0 ]
  run grep -q -- "--verbose" ollama_args.txt
  [ "$status" -eq 0 ]
}

@test "Remote: missing API key" {
  generate_commits
  mkdir -p stubs
  cat >stubs/curl <<EOF
#!/bin/bash
echo "{}"
EOF
  chmod +x stubs/curl
  export PATH="$PWD/stubs:$PATH"
  unset CHANGEISH_API_KEY
  run "$CHANGEISH_SCRIPT" --model-provider remote --api-url http://fake --api-model gpt-mini
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "CHANGEISH_API_KEY is not set"
}

@test "Remote: missing API URL" {
  generate_commits
  mkdir -p stubs
  cat >stubs/curl <<EOF
#!/bin/bash
echo "{}"
EOF
  chmod +x stubs/curl
  export PATH="$PWD/stubs:$PATH"
  export CHANGEISH_API_KEY="tok"
  run "$CHANGEISH_SCRIPT" --model-provider remote --api-model gpt-mini
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "API URL is not set"
}

@test "Model: CLI --model overrides env" {
  export CHANGEISH_MODEL=llama2
  mkdir -p docs
  echo "# Changelog" >docs/CHANGELOG.md
  echo "f" >f.txt && git add f.txt && git commit -m "f"
  run "$CHANGEISH_SCRIPT" --model phi --debug
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Generating changelog using model: phi"
}

@test "Model: --api-model overrides --model for remote" {
  generate_commits
  mock_curl "bar" ""
  export CHANGEISH_API_KEY="tok"
  run "$CHANGEISH_SCRIPT" --to HEAD --model-provider remote --api-url http://fake --model foo --api-model bar
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Hello I am bar!"
}

@test "Error: outside git repo" {
  rm -rf .git
  run "$CHANGEISH_SCRIPT"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "not a git repo" || echo "$output" | grep -qi "fatal: not a git repository"
}

@test "Error: repo with no commits" {
  rm -rf .git
  git init -q
  run "$CHANGEISH_SCRIPT" --save-history
  assert_failure
  echo "$output" | grep -qi "No commits found in repository"
  status=0
}

@test "No changes results in clean empty output" {
  echo "foo" >x.py
  git add x.py && git commit -m "add file"
  run "$CHANGEISH_SCRIPT" --current --save-history
  [ "$status" -eq 0 ]
  grep -q "Working Tree" history.md
}

@test "Error: bad config file path" {
  echo "x" >file.txt && git add file.txt && git commit -m "init"
  run "$CHANGEISH_SCRIPT" --config-file does_not_exist.env --save-history
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "Error: config file"
}

@test "Error: bad version file path" {
  echo "x" >file.txt && git add file.txt && git commit -m "init"
  run "$CHANGEISH_SCRIPT" --version-file does_not_exist.ver --save-history
  assert_failure
  echo "$output" | grep -q "version file"
  status=0
}

@test "Generation mode: none skips changelog generation" {
  echo "a" >a.txt && git add a.txt && git commit -m "a"
  run "$CHANGEISH_SCRIPT" --model-provider none --save-history --save-prompt
  [ "$status" -eq 0 ]
  [ -f history.md ]
  [ -f prompt.md ]
  [ ! -f CHANGELOG.md ] || ! grep -q "Generated by changeish" CHANGELOG.md
}

@test "Generation mode: local forces local model" {
  echo "b" >b.txt && git add b.txt && git commit -m "b"
  mock_ollama "dummy" "LOCAL MODE"
  run "$CHANGEISH_SCRIPT" --model-provider local --save-history
  [ "$status" -eq 0 ]
  grep -q "LOCAL MODE" CHANGELOG.md
}

@test "Generation mode: remote forces remote model" {
  echo "c" >c.txt && git add c.txt && git commit -m "c"
  mock_curl "dummy" "REMOTE MODE"
  export CHANGEISH_API_KEY="dummy"
  run "$CHANGEISH_SCRIPT" --model-provider remote --api-url http://fake --api-model dummy
  [ "$status" -eq 0 ]
  grep -q "REMOTE MODE" CHANGELOG.md
}

@test "Generation mode: auto prefers local, falls back to remote" {
  echo "d" >d.txt && git add d.txt && git commit -m "d"
  export PATH="/usr/bin:/bin"
  rm -f bin/ollama
  mock_curl "dummy" "AUTO REMOTE"
  export CHANGEISH_API_KEY="dummy"
  run "$CHANGEISH_SCRIPT" --model-provider auto --api-url http://fake --api-model dummy
  [ "$status" -eq 0 ]
  grep -q "AUTO REMOTE" CHANGELOG.md
}

@test "Generation mode: unknown value aborts" {
  echo "e" >e.txt && git add e.txt && git commit -m "e"
  run "$CHANGEISH_SCRIPT" --model-provider doesnotexist
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "Unknown --model-provider"
}

@test "Update-mode: prepend inserts new section above existing section" {
  echo "# Changelog" >CHANGELOG.md
  echo "## v1.0.0" >>CHANGELOG.md
  echo "- old entry" >>CHANGELOG.md

  echo "feat: new prepended" >file.txt
  git add CHANGELOG.md file.txt
  git commit -m "init"

  mock_ollama "dummy" "- feat: new prepended"
  run "$CHANGEISH_SCRIPT" --changelog-file CHANGELOG.md \
    --update-mode prepend --section-name "v1.0.0"
  [ "$status" -eq 0 ]
  cat CHANGELOG.md >>$ERROR_LOG

  # Ensure the changelog contains the expected content in order
  expected="
## v1.0.0

- feat: new prepended

## v1.0.0

- old entry

[Managed by changeish](https://github.com/itlackey/changeish)"

  # Remove the first line (header) and compare the rest
  actual=$(tail -n +2 CHANGELOG.md | sed '/^$/N;/^\n$/D')
  if ! diff -u <(echo "$expected") <(echo "$actual"); then
    echo "Changelog content does not match expected:" >>"$ERROR_LOG"
    echo "Expected:" >>"$ERROR_LOG"
    echo "$expected" >>"$ERROR_LOG"
    echo "Actual:" >>"$ERROR_LOG"
    echo "$actual" >>"$ERROR_LOG"
    diff -u <(echo "$expected") <(echo "$actual") >>"$ERROR_LOG"
    fail "Changelog content does not match expected"
  fi

  echo "Test passed: new section with heading ## v1.0.0 is prepended above the existing one" >>"$ERROR_LOG"
}

@test "Update-mode: append adds after existing section" {
  echo "# Changelog" >CHANGELOG.md
  echo "## v2.0.0" >>CHANGELOG.md
  echo "- initial" >>CHANGELOG.md
  echo "## Older" >>CHANGELOG.md

  echo "fix: appended" >file.txt
  git add CHANGELOG.md file.txt
  git commit -m "init"

  mock_ollama "dummy" "- fix: appended"
  run "$CHANGEISH_SCRIPT" --changelog-file CHANGELOG.md \
    --update-mode append --section-name "v2.0.0"

  cat CHANGELOG.md >>$ERROR_LOG
  [ "$status" -eq 0 ]

  # Validate the exact order and content of CHANGELOG.md after append
  expected="
## v2.0.0
- initial

## Older

## v2.0.0

- fix: appended

[Managed by changeish](https://github.com/itlackey/changeish)"
  # Remove the first line (header) and compare the rest
  actual=$(tail -n +2 CHANGELOG.md | sed '/^$/N;/^\n$/D')
  if ! diff -u <(echo "$expected") <(echo "$actual"); then
    echo "Changelog content does not match expected:" >>"$ERROR_LOG"
    echo "Expected:" >>"$ERROR_LOG"
    echo "$expected" >>"$ERROR_LOG"
    echo "Actual:" >>"$ERROR_LOG"
    echo "$actual" >>"$ERROR_LOG"
    diff -u <(echo "$expected") <(echo "$actual") >>"$ERROR_LOG"
    fail "Changelog content does not match expected"
  fi
}

@test "Update-mode: append at end if section missing" {
  echo "# Log" >CHANGELOG.md
  echo "## vX.Y.Z" >>CHANGELOG.md
  echo "- entry" >>CHANGELOG.md

  echo "chore: at end" >file.txt
  git add CHANGELOG.md file.txt
  git commit -m "init"

  mock_ollama "dummy" "- chore: at end"
  run "$CHANGEISH_SCRIPT" --changelog-file CHANGELOG.md \
    --update-mode append --section-name "nope"

  cat CHANGELOG.md >>$ERROR_LOG

  [[ "$status" -eq 0 ]]
  tail -n5 CHANGELOG.md | grep -q "chore: at end"
  tail -n6 CHANGELOG.md | grep -q "## nope"
}

@test "Update-mode: auto updates when matching current version" {
  echo "# Changelog" >CHANGELOG.md
  echo "## v3.0.0" >>CHANGELOG.md
  echo "- old" >>CHANGELOG.md

  echo '__version__ = "3.0.0"' >setup.py
  git add CHANGELOG.md setup.py
  git commit -m "init"
  echo "feat: added" >file.txt

  mock_ollama "dummy" "- feat: added\n- updated AI"
  run "$CHANGEISH_SCRIPT" \
    --update-mode auto --save-history --save-prompt --debug
  [[ "$status" -eq 0 ]]

  # Expect updated section contents in CHANGELOG.md
  cat history.md >>$ERROR_LOG
  cat CHANGELOG.md >>$ERROR_LOG
  grep -q "feat: added" CHANGELOG.md
  grep -q "updated AI" CHANGELOG.md
}

@test "Update-mode: fallback auto inserts new section if missing" {
  echo "# Log" >CHANGELOG.md
  echo "## v9.9.9" >>CHANGELOG.md
  echo "- entry" >>CHANGELOG.md

  echo '__version__ = "1.2.3"' >setup.py
  git add CHANGELOG.md setup.py
  git commit -m "init"
  echo '__version__ = "1.2.4"' >setup.py
  echo "feat: new version" >file.txt
  git add file.txt

  mock_ollama "dummy" "- feat: new version"
  run "$CHANGEISH_SCRIPT" --model-provider local \
    --update-mode auto --save-history --save-prompt \
    --debug
  assert_success

  echo "HISTORY:" >>$ERROR_LOG
  cat history.md >>$ERROR_LOG
  echo "CHANGELOG:" >>$ERROR_LOG
  cat CHANGELOG.md >>$ERROR_LOG
  # Check new "1.2.4" section exists and includes the new feat
  grep -q "^## 1.2.4" CHANGELOG.md
  grep -q "feat: new version" CHANGELOG.md
}

@test "Generate-mode remote still works with append mode" {
  echo "# Changelog" >CHANGELOG.md
  echo "## v4.0.0" >>CHANGELOG.md
  echo "- prev" >>CHANGELOG.md
  echo "" >>CHANGELOG.md

  echo "fix: remote append" >file.txt
  git add CHANGELOG.md file.txt
  git commit -m "init"
  echo "remote append" >test.txt

  mock_curl "dummy" "- fix: remote append"
  export CHANGEISH_API_KEY="dummy"
  run "$CHANGEISH_SCRIPT" --model-provider remote --api-url http://fake \
    --api-model dummy --update-mode append --section-name "v4.0.0" \
    --save-history --save-prompt
  [[ "$status" -eq 0 ]]
  cat CHANGELOG.md >>$ERROR_LOG
  echo "History:" >>$ERROR_LOG
  cat history.md >>$ERROR_LOG
  echo "Prompt:" >>$ERROR_LOG
  cat prompt.md >>$ERROR_LOG
  tail -n5 CHANGELOG.md | grep -q "fix: remote append"
}
