#!/usr/bin/env bats

mkdir -p "$BATS_TEST_DIRNAME/.logs"
export ERROR_LOG="$BATS_TEST_DIRNAME/.logs/commands.log"
load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

SCRIPT="$BATS_TEST_DIRNAME/../src/changes.sh"

setup() {
  # create a temp git repo
  REPO="$(mktemp -d)"
  cd "$REPO"
  git  init -q
  # make two commits
  echo "one" >file.txt
  git add file.txt
  git commit -q -m "first commit"
  echo "two" >>file.txt
  git commit -q -am "second commit"

  # make helper stubs
  build_history() { printf "HIST:%s\n" "$2" >"$1"; }
  generate_response() { echo "RESP"; }
  portable_mktemp() { mktemp; }
  get_current_version() { echo "1.2.3"; }

  # prompts and file globals
  default_summary_prompt="DEF_SUM"
  commit_message_prompt="DEF_MSG"
  # release_file="release.out"
  # announce_file="announce.out"
  # changelog_file="changelog.out"

  # no dry_run by default
  unset dry_run
  export debug=1

  # load the script under test
  source "$SCRIPT"
}

teardown() {
  rm -rf "$REPO"
  rm -f *.out
}

#----------------------------------------
# summarize_commit
#----------------------------------------
@test "summarize_commit writes RESP to out_file and cleans temps" {
  # force portable_mktemp to yield deterministic files
  COUNT=0
  portable_mktemp() {
    if [ "$COUNT" -eq 0 ]; then
      COUNT=1
      echo hist.tmp
    else
      echo pr.tmp
    fi
  }

  rm -f hist.tmp pr.tmp out.txt
  summarize_commit abc PROMPT out.txt

  # should have RESP in out.txt
  run cat out.txt
  assert_output "RESP"

  # temps should be gone
  [ ! -f hist.tmp ]
  [ ! -f pr.tmp ]
}

#----------------------------------------
# summarize_target
#----------------------------------------
@test "summarize_target on single-commit range" {
  tmp="$(mktemp)"
  # override summarize_commit to echo commit into file
  summarize_commit() { printf "C:%s\n" "$1" >>"$3"; }

  # call inside the real repo
  summarize_target HEAD~1..HEAD PL tmp
  run sed -e 's/\r//g' "$tmp"
  # expect two commits, each followed by two blank lines
  expected=$'C:HEAD~1\n\n\nC:HEAD\n\n'
  [ "$output" = "$expected" ]
  rm -f "$tmp"
}

@test "summarize_target on --current" {
  tmp="$(mktemp)"
  summarize_commit() { echo "CUR" >>"$3"; }
  summarize_target --current PL "$tmp"
  run cat "$tmp"
  # one invocation + two newlines
  assert_output $'CUR'
  rm -f "$tmp"
}

#----------------------------------------
# cmd_message
#----------------------------------------
@test "cmd_message with no id errors" {
  run cmd_message ""
  assert_success
  assert_output --partial "Error: No commit ID"
}
@test "cmd_message --current prints message" {
  echo "change" > "$REPO/file.txt"
  run cmd_message "--current"
  [ "$status" -eq 0 ]
  echo "$output"
  assert_output --partial "change"
}
@test "cmd_message single‐commit prints message" {
  run git -C "$REPO" rev-parse HEAD~1  # ensure HEAD~1 exists
  run cmd_message HEAD~1
  [ "$status" -eq 0 ]
  assert_output "first commit"
}

@test "cmd_message invalid commit errors" {
  run cmd_message deadbeef
  [ "$status" -eq 1 ]
  assert_output --partial "Error: Invalid commit ID"
}

@test "cmd_message range prints both messages" {
  run cmd_message HEAD~1..HEAD
  [ "$status" -eq 0 ]
  assert_output $'first commit\nsecond commit'
}

#----------------------------------------
# cmd_summary
#----------------------------------------
@test "cmd_summary prints to stdout" {
  summarize_target() { echo "SUM"; }
  run cmd_summary --dry-run
  [ "$status" -eq 0 ]
  assert_output "SUM"
}

@test "cmd_summary HEAD~1 prints to stdout" {
 
  #summarize_target() { echo "SUM"; }
  ollama(){
    echo "SUM"
  }
  run cmd_summary HEAD~1 --dry-run
  [ "$status" -eq 0 ]
  assert_output --partial "SUM"
}

@test "cmd_summary writes to file when output_file set" {
  output_file="out.sum"
  summarize_target() { echo "SUM"; }
  run cmd_summary
  [ "$status" -eq 0 ]
  assert_file_exist out.sum
  assert_output --partial "Summary written to out.sum"
  rm -f out.sum
}

#----------------------------------------
# cmd_release_notes / announcement / changelog
#----------------------------------------

@test "cmd_release_notes writes to its default file" {
  summarize_target() { :; }
  generate_from_summaries() {
    printf "GEN\n"
    printf 'Document written to %s\n' "$3"
  }

  run cmd_release_notes
  [ "$status" -eq 0 ]
  assert_output --partial "Document written to release.out"
}

@test "cmd_announcement writes to its default file" {
  summarize_target() { :; }
  generate_from_summaries() {
    printf "GEN\n"
    printf 'Document written to %s\n' "$3"
  }

  run cmd_announcement
  [ "$status" -eq 0 ]
  assert_output --partial "Document written to ANNOUNCEMENT.md"
}

@test "cmd_changelog writes to its default file" {
  summarize_target() { :; }
  generate_from_summaries() {
    printf "GEN\n"
    printf 'Document written to %s\n' "$3"
  }

  run cmd_changelog
  assert_success
  assert_output --partial "Document written to CHANGELOG.md"
}
