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



mock_ollama() {
  arg1="${1:-dummy}"
  arg2="${2:-Ollama message}"
  mkdir -p bin
  cat >bin/ollama <<EOF
#!/bin/bash
echo "Ollama command: \$1"
echo "Using model: \$2"
echo "Ollama arg1: $arg1"
echo "Ollama arg2: $arg2"
echo "Ollama run complete"
if [ "\$3" ]; then
  echo "\$3"
fi
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
@test "SCRIPT runs successfully with specified options" {

  export CONFIG_FILE="$BATS_TEST_DIRNAME/../.env"
  # Run the script with the specified options
  run "$CHANGEISH_SCRIPT" "message" --config-file "${CONFIG_FILE}" --verbose

  echo "Output: $output"
  # Assert that the script ran successfully
  assert_success

  # Validate the parsed options
  assert_output --partial "Debug: true"
  assert_output --partial "Subcommand: message"
  assert_output --partial "Target: --current"
  assert_output -e "Template Directory.*/prompts"
  assert_output --partial "Config File: ../.env"
  assert_output --partial "Config Loaded: true"
  assert_output --partial "TODO Pattern: *todo*"
  assert_output --partial "Model: qwen2.5-coder"
  assert_output --partial "Model Provider: remote"
  assert_output --partial "API Model: gpt-4o-mini"
  assert_output --partial "API URL: https://i2db-chat-sandboxaizehuif2whye3c.openai.azure.com/openai/deployments/gpt-4o-mini/chat/completions?api-version=2024-04-01-preview"
  assert_output --partial "Update Mode: auto"
  assert_output --partial "Section Name: auto"
}
@test "Generate message for HEAD (default)" {
  echo "msg" >m.txt && git add m.txt && git commit -m "commit for message"
  run "$CHANGEISH_SCRIPT" message HEAD
  assert_success
  echo "$output" | grep -iq "commit"
}

@test "Generate message for working tree --current" {
  mock_ollama "dummy" "Working Tree changes"

  echo "foo" >"wt.txt"
  git add .
  git commit -m "wt commit"
  echo "updated" >"wt.txt"
  echo "bar" >"wt2.txt"

  run "$CHANGEISH_SCRIPT" message --current --verbose
  assert_success
  assert_output --partial "Working Tree changes"
  assert_output --partial "wt.txt"
  assert_output --partial "wt2.txt"
}

@test "Message: for commit range" {
  gen_commits
  mock_ollama "dummy" "Commit range message"
  run "$CHANGEISH_SCRIPT" message HEAD~2..HEAD --verbose
  assert_success
  assert_output --partial "add b.txt"
}

@test "Message: with file pattern" {
  mock_ollama "dummy" "Patterned message for bar.py"
  echo "bar" >bar.py && git add bar.py && git commit -m "python file"
  run "$CHANGEISH_SCRIPT" message HEAD "*.py" --verbose
  assert_success
  assert_output --partial "python file"
}

# ---- SUMMARY SUBCOMMAND ----

@test "Generate summary for HEAD" {

  echo "summary" >s.txt && git add s.txt && git commit -m "sum"
  run "$CHANGEISH_SCRIPT" summary HEAD --verbose
  assert_success
  assert_output --partial "sum"
}

@test "Summary for commit range with pattern" {
  gen_commits
  run "$CHANGEISH_SCRIPT" summary HEAD~2..HEAD "*.txt"
  assert_success
  assert_output --partial "a.txt"
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
  cat CHANGELOG.md
  assert_success
  grep -q "update a b c" CHANGELOG.md
}

@test "Changelog for staged (--cached)" {
  echo "stage" >stage.txt && git add stage.txt
  mock_ollama "dummy" "- staged"
  run "$CHANGEISH_SCRIPT" changelog --cached
  assert_success
  grep -q "staged" CHANGELOG.md
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

@test "Release notes for range dry-run" {
  gen_commits
  mock_ollama "dummy" "relnote"
  echo "" > ".env"
  run "$CHANGEISH_SCRIPT" release-notes HEAD~2..HEAD --dry-run
  assert_success
  assert_output --partial "relnote"
}
# ---- ANNOUNCEMENT SUBCOMMAND ----

@test "Announcement for HEAD" {
  echo "announce" >an.txt && git add an.txt && git commit -m "an"
  mock_ollama "dummy" "- announce"
  run "$CHANGEISH_SCRIPT" announcement HEAD
  assert_success
  [ -f "ANNOUNCEMENT.md" ]
  grep -q "announce" ANNOUNCEMENT.md
}

# ---- AVAILABLE-RELEASES & UPDATE ----

@test "Available releases outputs tags" {
  mkdir -p stubs
  cat >stubs/curl <<EOF
#!/bin/bash
echo '[
  {
    "url": "https://api.github.com/repos/itlackey/changeish/releases/228995989",
    "assets_url": "https://api.github.com/repos/itlackey/changeish/releases/228995989/assets",
    "upload_url": "https://uploads.github.com/repos/itlackey/changeish/releases/228995989/assets{?name,label}",
    "html_url": "https://github.com/itlackey/changeish/releases/tag/0.2.0",
    "id": 228995989,
    "author": {
      "login": "itlackey",
      "id": 6414031,
      "node_id": "MDQ6VXNlcjY0MTQwMzE=",
      "avatar_url": "https://avatars.githubusercontent.com/u/6414031?v=4",
      "gravatar_id": "",
      "url": "https://api.github.com/users/itlackey",
      "html_url": "https://github.com/itlackey",
      "followers_url": "https://api.github.com/users/itlackey/followers",
      "following_url": "https://api.github.com/users/itlackey/following{/other_user}",
      "gists_url": "https://api.github.com/users/itlackey/gists{/gist_id}",
      "starred_url": "https://api.github.com/users/itlackey/starred{/owner}{/repo}",
      "subscriptions_url": "https://api.github.com/users/itlackey/subscriptions",
      "organizations_url": "https://api.github.com/users/itlackey/orgs",
      "repos_url": "https://api.github.com/users/itlackey/repos",
      "events_url": "https://api.github.com/users/itlackey/events{/privacy}",
      "received_events_url": "https://api.github.com/users/itlackey/received_events",
      "type": "User",
      "user_view_type": "public",
      "site_admin": false
    },
    "node_id": "RE_kwDOO8Gcbs4NpjOV",
    "tag_name": "0.2.0",
    "target_commitish": "main",
    "name": "0.2.0",
    "draft": false,
    "prerelease": false,
    "created_at": "2025-07-01T02:39:16Z",
    "published_at": "2025-07-01T05:59:26Z",
    "assets": [],
    "tarball_url": "https://api.github.com/repos/itlackey/changeish/tarball/0.2.0",
    "zipball_url": "https://api.github.com/repos/itlackey/changeish/zipball/0.2.0",
    "body": "## What'\''s New in v0.2.0"
  },
  {
    "url": "https://api.github.com/repos/itlackey/changeish/releases/226567952",
    "assets_url": "https://api.github.com/repos/itlackey/changeish/releases/226567952/assets",
    "upload_url": "https://uploads.github.com/repos/itlackey/changeish/releases/226567952/assets{?name,label}",
    "html_url": "https://github.com/itlackey/changeish/releases/tag/v0.1.10",
    "id": 226567952,
    "author": {
      "login": "itlackey",
      "id": 6414031,
      "node_id": "MDQ6VXNlcjY0MTQwMzE=",
      "avatar_url": "https://avatars.githubusercontent.com/u/6414031?v=4",
      "gravatar_id": "",
      "url": "https://api.github.com/users/itlackey",
      "html_url": "https://github.com/itlackey",
      "followers_url": "https://api.github.com/users/itlackey/followers",
      "following_url": "https://api.github.com/users/itlackey/following{/other_user}",
      "gists_url": "https://api.github.com/users/itlackey/gists{/gist_id}",
      "starred_url": "https://api.github.com/users/itlackey/starred{/owner}{/repo}",
      "subscriptions_url": "https://api.github.com/users/itlackey/subscriptions",
      "organizations_url": "https://api.github.com/users/itlackey/orgs",
      "repos_url": "https://api.github.com/users/itlackey/repos",
      "events_url": "https://api.github.com/users/itlackey/events{/privacy}",
      "received_events_url": "https://api.github.com/users/itlackey/received_events",
      "type": "User",
      "user_view_type": "public",
      "site_admin": false
    },
    "node_id": "RE_kwDOO8Gcbs4NgScQ",
    "tag_name": "v0.1.10",
    "target_commitish": "main",
    "name": "v0.1.10",
    "draft": false,
    "prerelease": false,
    "created_at": "2025-06-20T03:05:11Z",
    "published_at": "2025-06-20T03:07:47Z",
    "assets": [],
    "tarball_url": "https://api.github.com/repos/itlackey/changeish/tarball/v0.1.10",
    "zipball_url": "https://api.github.com/repos/itlackey/changeish/zipball/v0.1.10",
    "body": "## What'\''s Changed"
  }
]'
EOF
  chmod +x stubs/curl
  export PATH="$PWD/stubs:$PATH"
  run "$CHANGEISH_SCRIPT" available-releases
  assert_success
  assert_output --partial "0.2.0"
  assert_output --partial "v0.1.10"
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
  assert_output --partial "installer called"
}

# ---- MODEL/CONFIG/ENV OVERRIDES ----

@test "Model options override config/env for message" {
  export CHANGEISH_MODEL=llama2
  mock_ollama "dummy" "- mocked"
  echo "CHANGEISH_MODEL=llama2" >.env
  run "$CHANGEISH_SCRIPT" message HEAD --model phi --verbose
  gen_commits
  assert_success
  assert_output --partial "phi"
}
@test "Config defaults to PWD/.env" {
  echo "CHANGEISH_MODEL=llama3" >.env
  
  mock_ollama "dummy" "- llama3"

  gen_commits
  run "$CHANGEISH_SCRIPT" message HEAD
  assert_success
  assert_output --partial "add c.txt"
  assert_output --partial "Using model: llama3"
}
@test "Config file overrides .env" {
  echo "CHANGEISH_MODEL=llama3" >.env
  echo "CHANGEISH_MODEL=phi3" >my.env
  gen_commits
  run "$CHANGEISH_SCRIPT" message HEAD --config-file my.env --verbose
  assert_success
  assert_output --partial "phi3"
}

@test "Env API key required for remote" {
  unset CHANGEISH_API_KEY
  gen_commits
  run "$CHANGEISH_SCRIPT" changelog HEAD --model-provider remote --api-url http://fake --api-model dummy
  assert_output --partial "CHANGEISH_API_KEY"
}

# ---- ERROR CASES ----

@test "Fails gracefully outside git repo" {
  
  run "$CHANGEISH_SCRIPT" changelog HEAD
  assert_failure
  assert_output --partial "Error: Invalid target: HEAD"
}

@test "Fails on unknown subcommand" {
  run "$CHANGEISH_SCRIPT" doesnotexist
  assert_failure
  assert_output --partial "First argument must be a subcommand or -h/--help/-v/--version"
}

@test "Fails for bad config file path" {
  run "$CHANGEISH_SCRIPT" message HEAD --config-file doesnotexist.env
  assert_output --partial "Warning: config file \"doesnotexist.env\" not found."
}

## TODO: Fix this test
# @test "Fails for bad version file path" {
#   run "$CHANGEISH_SCRIPT" changelog HEAD --version-file doesnotexist.ver
#   assert_output --partial "version file"
# }

@test "Fails for repo with no commits" {
  rm -rf .git
  git init -q
  run "$CHANGEISH_SCRIPT" changelog HEAD --verbose
  assert_failure
  assert_output --partial "Error: Invalid target: HEAD"
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
  assert_output --partial "Response written to RELEASE_NOTES.md" 
}

@test "Announce outputs ANNOUNCEMENT.md" {
  echo "ann" >ann.txt && git add ann.txt && git commit -m "ann"
  mock_ollama "dummy" "- announce"
  run "$CHANGEISH_SCRIPT" announcement HEAD
  assert_success
  [ -f ANNOUNCEMENT.md ]
  grep -q "announce" ANNOUNCEMENT.md
}
