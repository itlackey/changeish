#!/usr/bin/env bats

load "$BATS_TEST_DIRNAME/../src/helpers.sh"

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    TMPFILE="$(mktemp)"
    export TMPFILE
}
teardown() {
    if [ -n "$TMPFILE" ]; then
        rm -f "$TMPFILE"
    fi
}

@test "get_current_version_from_file detects Version v1.2.3" {
    TMPFILE="$(mktemp)"
    echo "# Version: v1.2.3" >"$TMPFILE"
    run get_current_version_from_file "$TMPFILE"
    assert_success
    assert_equal "$output" "v1.2.3"
}

@test "extract_changelog_section extracts correct section" {
    cat >"$TMPFILE" <<EOF
# Changelog

## v1.2.3

- Added feature X

## v1.2.2

- Fixed bug Y
EOF
    run extract_changelog_section "v1.2.3" "$TMPFILE"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Added feature X"
}

@test "get_current_version_from_file detects version = '1.2.3'" {
    echo "version = '1.2.3'" >"$TMPFILE"
    run get_current_version_from_file "$TMPFILE"
    assert_success
    assert_equal "$output" "1.2.3"
}

@test "get_current_version_from_file detects version: " {
    echo 'version: "1.2.3"' >"$TMPFILE"
    run get_current_version_from_file "$TMPFILE"
    assert_success
    assert_equal "$output" "1.2.3"
}

@test "get_current_version_from_file detects __version__ = " {
    echo '__version__ = "1.2.3"' >"$TMPFILE"
    run get_current_version_from_file "$TMPFILE"
    assert_success
    assert_equal "$output" "1.2.3"
}

@test "get_current_version_from_file detects JSON version field" {
    echo '{"version": "1.2.3"}' >"$TMPFILE"
    run get_current_version_from_file "$TMPFILE"
    assert_success
    assert_equal "$output" "1.2.3"
}

@test "get_current_version_from_file detects v-prefixed version in JSON" {
    echo '{"version": "v1.2.3"}' >"$TMPFILE"
    run get_current_version_from_file "$TMPFILE"
    assert_success
    assert_equal "$output" "v1.2.3"
}

# @test "get_current_version_from_file detects fallback version string" {
#     echo "Release notes for v2.0.0" >"$TMPFILE"
#     run get_current_version_from_file "$TMPFILE"
#     assert_success
#     assert_equal "$output" "v2.0.0"
# }

@test "get_current_version_from_file returns empty string if no version found" {
    echo "No version here" >"$TMPFILE"
    run get_current_version_from_file "$TMPFILE"
    assert_success
    assert_equal "$output" ""
}
