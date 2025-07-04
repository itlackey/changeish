#!/usr/bin/env bats

mkdir -p "$BATS_TEST_DIRNAME/.logs"
export ERROR_LOG="$BATS_TEST_DIRNAME/.logs/error.log"
load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

SCRIPT="$BATS_TEST_DIRNAME/../src/helpers.sh"

setup() {
    # Create a temporary git repo
    REPO="$(mktemp -d)"
    cd "$REPO"
    git init -q

    # Commit version 1.0.0
    printf '{ "version": "1.0.0" }\n' >package.json
    git add package.json
    git commit -q -m "Initial version 1.0.0"

    # Commit other file
    printf 'some other file\n' >file.txt
    git add file.txt
    git commit -q -m "Add some other file"

    # Commit version 1.1.0
    printf '{ "version": "1.1.0" }\n' >package.json
    git add package.json
    git commit -q -m "Bump to 1.1.0"

    # Stub helper functions
    parse_version() {
        # Extract the version number from a diff line
        echo "$1" | sed -E 's/.*"version":[[:space:]]*"([^"]+)".*/\1/'
    }
    get_current_version_from_file() {
        # Read the version directly from the file
        grep -E '"version":' "$1" | sed -E 's/.*"version":[[:space:]]*"([^"]+)".*/\1/'
    }
    extract_todo_changes() {
        # By default, no TODO changes
        return 0
    }
    debug=true

    # Source the script under test
    # (Make sure this path points to where build_history() lives)
    source "$SCRIPT"
}

teardown() {
    rm -rf "$REPO"
}

@test "build_history for HEAD shows updated version and diff block" {
    hist="$(mktemp)"
    run build_history "$hist" HEAD

    cat "$hist"
    # Should contain the updated version header
    run grep -F "**Version:** 1.1.0" "$hist"
    assert_success
    run cat "$hist"
    assert_output --partial '```diff'
}

@test "build_history for HEAD~2 shows previous version" {
    hist="$(mktemp)"
    build_history "$hist" HEAD~2
    run cat "$hist"
    assert_output --partial "**Version:** 1.0.0"
    assert_success
}

@test "build_history with no version file emits only diff block" {
    # Remove the version file and commit that change
    rm package.json
    git add -u
    git commit -q -m "Remove version file"

    hist="$(mktemp)"
    build_history "$hist" HEAD

    # Should NOT contain any Version: header
    ! grep -q "\*\*Version:\*\*" "$hist"

    # Should still contain a diff block
    run grep -F '```diff' "$hist"
    [ "$status" -eq 0 ]
}

@test "build_history appends TODO section when extract_todo_changes returns data" {
    # Override extract_todo_changes to simulate TODOs
    extract_todo_changes() {
        echo "+ TODO: fix this"
    }

    hist="$(mktemp)"
    build_history "$hist" HEAD

    # Should include the TODO section header
    run grep -F "### TODO Changes" "$hist"
    [ "$status" -eq 0 ]

    # And the mock TODO line
    run grep -F "+ TODO: fix this" "$hist"
    [ "$status" -eq 0 ]
}

@test "build_history respects PATTERN environment variable" {
    # Only include package.json in diff
    export PATTERN="package.json"
    export debug="1"
    echo $(git --no-pager diff HEAD^! --minimal --no-prefix --unified=0 --no-color -b -w --compact-summary --color-moved=no -- "package.json")
    echo "end of diff"
    hist="$(mktemp)"
    build_history "$hist" HEAD "todo" "$PATTERN"
    cat "$hist"
    # The diff block should reference package.json
    run grep -F '```diff' "$hist"
    assert_success

    run grep -F 'package.json' "$hist"
    assert_success
}

@test "build_history respects no pattern" {

    printf '{ "version": "1.2.0" }\n' >package.json
    hist="$(mktemp)"
    build_history "$hist" "--current"
    assert_success
    cat "$hist"
    run grep -F '1.2.0' "$hist"
    assert_success

}


@test "build_history includes untracked files" {

    printf '{ "version": "1.2.0" }\n' >package.json
    printf 'untracked file content\n' >untracked.txt
    hist="$(mktemp)"
    build_history "$hist" "--current"
    assert_success
    cat "$hist"
    run grep -F '1.2.0' "$hist"
    assert_success
    run grep -F 'untracked.txt' "$hist"
    assert_success

}
