#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

export ERROR_LOG="$BATS_TEST_DIRNAME/.logs/main.error.log"

setup_file() {
  : >"$ERROR_LOG"
}

setup() {
  ORIG_DIR="$PWD"
  TMP_DIR="$(mktemp -d)/changeish-tests"
  mkdir -p "$TMP_DIR"
  mkdir -p "$BATS_TEST_DIRNAME/.logs"
  cd "$TMP_DIR"
  git init -q
  git config user.name "Test"
  git config user.email "test@example.com"
  CHANGEISH_SCRIPT="$BATS_TEST_DIRNAME/../src/changes.sh"
  mock_ollama "dummy" "Ollama run"
  mock_curl "dummy" "Hello from remote!"
}

teardown() {
  cd "${ORIG_DIR:-$PWD}" 2>/dev/null || true
}

# ---- Helpers ----

# mock_ollama() {
#   local content="$2"
#   mkdir -p bin
#   cat >bin/ollama <<EOF
# #!/bin/bash
# echo '$content'
# EOF
#   chmod +x bin/ollama
#   export PATH="$PWD/bin:$PATH"
# }

mock_ollama(){
    mkdir -p bin
  cat >bin/ollama <<EOF
#!/bin/bash
cat \$1
EOF
  chmod +x bin/ollama
  export PATH="$PWD/bin:$PATH"
}

mock_curl() {
  local message="${2:-"Hello from curl!"}"
  local response
  response="{ \"id\": \"id\", \"choices\": [ { \"message\": { \"content\": \"$message\" } } ] }"
  mkdir -p bin
  cat >bin/curl <<EOF
#!/bin/bash
echo '$response'
EOF
  chmod +x bin/curl
  export PATH="$PWD/bin:$PATH"
}

gen_commits() {
  for f in a b c; do
    echo "$f" >"$f.txt" && git add "$f.txt" && git commit -m "add $f.txt"
  done
}

# ---- Global Options & Help ----

@test "Prints version" {
  run "$CHANGEISH_SCRIPT" --version
  assert_success
  echo "$output" | grep -E "[0-9]+\.[0-9]+\.[0-9]+"
}

@test "Prints help with subcommands" {
  run "$CHANGEISH_SCRIPT" --help
  assert_success
  echo "$output" | grep -q "Usage: changeish"
  echo "$output" | grep -q "message"
  echo "$output" | grep -q "changelog"
  echo "$output" | grep -q "release-notes"
  echo "$output" | grep -q "available-releases"
}

@test "Unknown flag errors" {
  run "$CHANGEISH_SCRIPT" --nope
  assert_failure
  assert_output --partial "First argument must be a subcommand or -h/--help/-v/--version"
}

# ---- MESSAGE SUBCOMMAND ----

@test "Generate message for HEAD (default)" {
  echo "msg" >m.txt && git add m.txt && git commit -m "commit for message"
  run "$CHANGEISH_SCRIPT" message HEAD
  assert_success
  echo "$output" | grep -iq "commit"
}

@test "Generate message for working tree --current" {
  echo "foo" >wt.txt
  mock_ollama "dummy" "Working Tree changes"
  run "$CHANGEISH_SCRIPT" message --current --verbose
  assert_success
  assert_output --partial "Working Tree"
}

@test "Message: for commit range" {
  gen_commits
  mock_ollama "dummy" "Commit range message"
  run "$CHANGEISH_SCRIPT" message HEAD~2..HEAD --verbose
  assert_success
  assert_output --partial "add b.txt"
}

@test "Message: with file pattern" {
  mock_ollama "dummy" "Patterned message"
  echo "bar" >bar.py && git add bar.py && git commit -m "python file"
  run "$CHANGEISH_SCRIPT" message HEAD "*.py" --verbose
  assert_success
  assert_output --partial "bar.py"
}

# ---- SUMMARY SUBCOMMAND ----

@test "Generate summary for HEAD" {

  echo "summary" >s.txt && git add s.txt && git commit -m "sum"
  run "$CHANGEISH_SCRIPT" summary HEAD --verbose
  assert_success
  assert_output --partial "sua"
}

@test "Summary for commit range with pattern" {
  gen_commits
  run "$CHANGEISH_SCRIPT" summary HEAD~2..HEAD "*.txt"
  assert_success
  echo "$output" | grep -q "a.txt"
}

# ---- CHANGELOG SUBCOMMAND ----

@test "Changelog for last commit (HEAD)" {
  echo "clog" >c.txt && git add c.txt && git commit -m "clogmsg"
  mock_ollama "dummy" "- feat: clog"
  run "$CHANGEISH_SCRIPT" changelog HEAD
  assert_success
  grep -q "clog" CHANGELOG.md
}

@test "Changelog for commit range" {
  gen_commits
  mock_ollama "dummy" "- update a b c"
  run "$CHANGEISH_SCRIPT" changelog HEAD~2..HEAD
  assert_success
  grep -q "a.txt" CHANGELOG.md
}

@test "Changelog for staged (--cached)" {
  echo "stage" >stage.txt && git add stage.txt
  mock_ollama "dummy" "- staged"
  run "$CHANGEISH_SCRIPT" changelog --cached
  assert_success
  grep -q "stage.txt" CHANGELOG.md
}

@test "Changelog with file pattern" {
  echo "bar" >bar.md && git add bar.md && git commit -m "docs"
  mock_ollama "dummy" "- bar.md"
  run "$CHANGEISH_SCRIPT" changelog HEAD "*.md"
  assert_success
  grep -q "bar.md" CHANGELOG.md
}

@test "Changelog for working tree (--current)" {
  echo "z" >z.md
  mock_ollama "dummy" "- z.md"
  run "$CHANGEISH_SCRIPT" changelog --current
  assert_success
  grep -q "z.md" CHANGELOG.md
}

@test "Changelog with update-mode and section-name" {
  echo "# Changelog" >CHANGELOG.md
  echo "## v1.0.0" >>CHANGELOG.md
  echo "- old" >>CHANGELOG.md
  echo "new" >n.txt && git add n.txt && git commit -m "new commit"
  mock_ollama "dummy" "- new change"
  run "$CHANGEISH_SCRIPT" changelog HEAD --update-mode prepend --section-name "v1.0.0"
  assert_success
  grep -q "new change" CHANGELOG.md
  grep -q "v1.0.0" CHANGELOG.md
}

# ---- RELEASE-NOTES SUBCOMMAND ----

@test "Release notes for range" {
  gen_commits
  mock_ollama "dummy" "- relnote"
  run "$CHANGEISH_SCRIPT" release-notes HEAD~2..HEAD
  assert_success
  grep -q "relnote" RELEASE_NOTES.md
}

# ---- ANNOUNCE SUBCOMMAND ----

@test "Announce for HEAD" {
  echo "announce" >an.txt && git add an.txt && git commit -m "an"
  mock_ollama "dummy" "- announce"
  run "$CHANGEISH_SCRIPT" announce HEAD
  assert_success
  grep -q "announce" ANNOUNCE.md
}

# ---- AVAILABLE-RELEASES & UPDATE ----

@test "Available releases outputs tags" {
  mkdir -p stubs
  cat >stubs/curl <<EOF
#!/bin/bash
echo '[{"tag_name": "v1.0.0"}, {"tag_name": "v2.0.0"}]'
EOF
  chmod +x stubs/curl
  export PATH="$PWD/stubs:$PATH"
  run "$CHANGEISH_SCRIPT" available-releases
  assert_success
  echo "$output" | grep -q "v1.0.0"
  echo "$output" | grep -q "v2.0.0"
}

@test "Update subcommand calls installer" {
  mkdir -p stubs
  cat >stubs/sh <<EOF
#!/bin/bash
echo "installer called: \$@"
EOF
  chmod +x stubs/sh
  export PATH="$PWD/stubs:$PATH"
  run "$CHANGEISH_SCRIPT" update
  assert_success
  echo "$output" | grep -q "installer called"
}

# ---- MODEL/CONFIG/ENV OVERRIDES ----

@test "Model options override config/env for message" {
  export CHANGEISH_MODEL=llama2
  run "$CHANGEISH_SCRIPT" message HEAD --model phi
  assert_success
  echo "$output" | grep -q "phi"
}

@test "Config file overrides .env" {
  echo "CHANGEISH_MODEL=llama3" >.env
  echo "CHANGEISH_MODEL=phi3" >my.env
  run "$CHANGEISH_SCRIPT" message HEAD --config-file my.env
  assert_success
  echo "$output" | grep -q "phi3"
}

@test "Env API key required for remote" {
  unset CHANGEISH_API_KEY
  run "$CHANGEISH_SCRIPT" changelog HEAD --model-provider remote --api-url http://fake --api-model dummy
  assert_failure
  echo "$output" | grep -q "CHANGEISH_API_KEY is not set"
}

# ---- ERROR CASES ----

@test "Fails gracefully outside git repo" {
  cd /
  run "$CHANGEISH_SCRIPT" changelog HEAD
  assert_failure
  echo "$output" | grep -qi "not a git repo"
}

@test "Fails on unknown subcommand" {
  run "$CHANGEISH_SCRIPT" doesnotexist
  assert_failure
  echo "$output" | grep -q "Unknown subcommand"
}

@test "Fails for bad config file path" {
  run "$CHANGEISH_SCRIPT" message HEAD --config-file doesnotexist.env
  assert_failure
  echo "$output" | grep -q "Error: config file"
}

@test "Fails for bad version file path" {
  run "$CHANGEISH_SCRIPT" changelog HEAD --version-file doesnotexist.ver
  assert_failure
  echo "$output" | grep -q "version file"
}

@test "Fails for repo with no commits" {
  rm -rf .git
  git init -q
  run "$CHANGEISH_SCRIPT" changelog HEAD
  assert_failure
  echo "$output" | grep -qi "No commits"
}

# ---- OUTPUT FILES ----

@test "Changelog outputs CHANGELOG.md" {
  echo "foo" >foo.txt && git add foo.txt && git commit -m "cl"
  mock_ollama "dummy" "- changelog"
  run "$CHANGEISH_SCRIPT" changelog HEAD
  assert_success
  [ -f CHANGELOG.md ]
  grep -q "changelog" CHANGELOG.md
}

@test "Release notes outputs RELEASE_NOTES.md" {
  echo "rel" >rel.txt && git add rel.txt && git commit -m "rel"
  mock_ollama "dummy" "- relnote"
  run "$CHANGEISH_SCRIPT" release-notes HEAD
  assert_success
  [ -f RELEASE_NOTES.md ]
  grep -q "relnote" RELEASE_NOTES.md
}

@test "Announce outputs ANNOUNCE.md" {
  echo "ann" >ann.txt && git add ann.txt && git commit -m "ann"
  mock_ollama "dummy" "- announce"
  run "$CHANGEISH_SCRIPT" announce HEAD
  assert_success
  [ -f ANNOUNCE.md ]
  grep -q "announce" ANNOUNCE.md
}
