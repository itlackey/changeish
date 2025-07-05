#!/usr/bin/env bats

mkdir -p "$BATS_TEST_DIRNAME/.logs"
export ERROR_LOG="$BATS_TEST_DIRNAME/.logs/error.log"
load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

SCRIPT="$BATS_TEST_DIRNAME/../src/changes.sh"

setup() {
  # stub out external commands so parse_args doesn't actually exec them
  show_help()    { printf 'HELP\n'; }
  show_version() { printf 'VERSION\n'; }
  #is_valid_git_range() { return 0; }

  # stub ollama/command-v checks so we never fall into the remote-mode branches
  command_ollama() { return 0; }
  alias ollama='command_ollama'

  # make a dummy config file
  echo "CHANGEISH_API_KEY=XYZ" > tmp.cfg
  echo "CHANGEISH_API_URL=TEST_URL" >> tmp.cfg
  echo "CHANGEISH_API_MODEL=TEST_MODEL" >> tmp.cfg
  chmod +r tmp.cfg

  # source the script under test
  source "$SCRIPT"
}

teardown() {
  rm -f tmp.cfg
}

# 1. no args → prints “No arguments provided.” and exits 0
@test "no arguments prints message and exits zero" {
  run parse_args
  echo "$output"
  assert_failure
  assert_output --partial "No arguments provided"
}

# 2. help flags
@test "help flag triggers show_help and exits 0" {
  run parse_args --help
  assert_success
  assert_output --partial "Usage: changeish <subcommand> [target] [pattern] [OPTIONS]"
}

@test "help via -h triggers show_help and exits 0" {

  run parse_args -h
  assert_success
  assert_output --partial "Usage: changeish <subcommand> [target] [pattern] [OPTIONS]"
}

# 3. version flags
@test "version flag triggers show_version and exits 0" {
  run parse_args --version
  assert_success
  assert_output --partial "$__VERSION"
}

@test "version via -v triggers show_version and exits 0" {
  run parse_args -v
  assert_success
  assert_output --partial "$__VERSION"
}

# 4. invalid first argument
@test "invalid subcommand errors out with exit 1" {
  run parse_args foobar
  [ "$status" -eq 1 ]
  assert_output --partial "First argument must be a subcommand"
}

# 5. valid subcommands
@test "subcommand 'message' is accepted and printed" {
  run parse_args message --verbose
  [ "$status" -eq 0 ]
  assert_output --partial "Subcommand: message"
}

@test "subcommand 'summary' is accepted and printed" {
  run parse_args summary --verbose
  [ "$status" -eq 0 ]
  assert_output --partial "Subcommand: summary"
}

@test "subcommand 'changelog' is accepted and printed" {
  run parse_args changelog --verbose
  [ "$status" -eq 0 ]
  assert_output --partial "Subcommand: changelog"
}

@test "subcommand 'release-notes' is accepted and printed" {
  run parse_args release-notes --verbose
  [ "$status" -eq 0 ]
  assert_output --partial "Subcommand: release-notes"
}

@test "subcommand 'announcement' is accepted and printed" {
  run parse_args announcement --verbose
  [ "$status" -eq 0 ]
  assert_output --partial "Subcommand: announcement"
}

@test "subcommand 'available-releases' is accepted and printed" {
  run parse_args available-releases --verbose
  [ "$status" -eq 0 ]
  assert_output --partial "Subcommand: available-releases"
}

@test "subcommand 'update' is accepted and printed" {
  run parse_args update --verbose
  [ "$status" -eq 0 ]
  assert_output --partial "Subcommand: update"
}

# 6. early --config-file parsing (nonexistent)
@test "early --config-file=bad prints error but continues" {
  run parse_args message --config-file bad --verbose

  assert_success
  assert_output --partial 'Error: config file "bad" not found.'
  assert_output --partial "Subcommand: message"
}

# 7. early --config-file parsing (exists)
@test "early --config-file tmp.cfg loads and prints it" {
  run parse_args summary --config-file tmp.cfg --verbose
  [ "$status" -eq 0 ]
  assert_output --partial "Config Loaded: true"
  assert_output --partial "Config File: tmp.cfg"
  assert_output --partial "API URL: TEST_URL"
  assert_output --partial "API Model: TEST_MODEL"
  assert_output --partial "Subcommand: summary"
}

# 8. default TARGET → --current
@test "no target given defaults to --current" {
  run parse_args message --verbose
  [ "$status" -eq 0 ]
  assert_output --partial "Target: --current"
}

# 9. --staged maps to --cached
@test "--staged becomes --cached internally" {
  run parse_args message --staged --verbose
  [ "$status" -eq 0 ]
  # note: code prints the raw "$1" again, but your logic sets TARGET="--cached"
  assert_output --partial "Target: --cached"
}

# 10. explicit git-range target
@test "valid git range as target" {
  run parse_args changelog v1..v2 --verbose
  assert_success
  # cat $output >> "$ERROR_LOG" # capture output for debugging (uncomment only when debugging)
  assert_output --partial "Target: v1..v2"
}

# 11. pattern collection
@test "positional args after target become PATTERN" {
  run parse_args summary v1..v2 src/**/*.js --verbose
  [ "$status" -eq 0 ]
  assert_output --partial "Pattern: src/**/*.js"
}

# 12. global flags: --dry-run
@test "--dry-run sets dry_run=true" {
  run parse_args release-notes --dry-run --verbose
  [ "$status" -eq 0 ]
  assert_output --partial "Pattern:"
  # dry_run itself isn’t printed, but no error means flag was accepted
}

# 13. unknown option after subcommand
@test "unknown option errors out" {
  run parse_args message --no-such-flag
  [ "$status" -eq 1 ]
  assert_output --partial "Unknown option or argument: --no-such-flag"
}

# 14. --template-dir, --output-file, --todo-pattern etc.
@test "all known global options parse without error" {
  run parse_args summary \
    --template-dir TPL \
    --output-file OUT \
    --todo-pattern TODO \
    --version-file VER \
    --model M \
    --model-provider P \
    --api-model AM \
    --api-url AU \
    --update-mode UM \
    --section-name SN \
    --verbose
  [ "$status" -eq 0 ]
  # spot-check a couple
  assert_output --partial "Template Directory: TPL"
  assert_output --partial "Config File:"
  assert_output --partial "Section Name: SN"
}

# 15. double dash stops option parsing (should error on unknown argument)
@test "-- stops option parsing (unknown argument after -- triggers error)" {
  run parse_args message -- target-and-pattern --verbose
  [ "$status" -eq 1 ]
  assert_output --partial "Unknown option or argument: --"
}
