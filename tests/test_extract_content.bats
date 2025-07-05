#!/usr/bin/env bats

mkdir -p "$BATS_TEST_DIRNAME/.logs"
export ERROR_LOG="$BATS_TEST_DIRNAME/.logs/error.log"
load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

SCRIPT="$BATS_TEST_DIRNAME/../src/helpers.sh"

setup() {
    # adjust the path as needed
    load "$SCRIPT"
}

@test "extracts simple single-line content" {
    json='{"message":{"content":"Hello World"}}'
    run extract_content "$json"
    [ "$status" -eq 0 ]
    [ "$output" = "Hello World" ]
}

@test "extracts multi-line content with \\n escapes" {
    json='{"message":{"content":"Line1\nLine2\nLine3"}}'
    run extract_content "$json"
    [ "$status" -eq 0 ]
    expected=$'Line1\nLine2\nLine3'
    [ "$output" = "$expected" ]
}

@test "extracts content containing escaped quotes" {
    json='{"message":{"content":"He said: \"Hi there\""}}'
    run extract_content "$json"
    [ "$status" -eq 0 ]
    [ "$output" = 'He said: "Hi there"' ]
}

@test "extracts content with backslashes" {
    json='{"message":{"content":"Path C:\\\\Windows\\\\System32"}}'
    run extract_content "$json"
    [ "$status" -eq 0 ]
    [ "$output" = 'Path C:\Windows\System32' ]
}

@test "returns empty string when content key is missing" {
    json='{"foo":"bar"}'
    run extract_content "$json"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "extracts content when other keys present" {
    json='{"choices":[{"foo":123,"message":{"content":"# Announcement\nUpdate complete."},"other":true}]}'
    run extract_content "$json"
    [ "$status" -eq 0 ]
    expected=$'# Announcement\nUpdate complete.'
    [ "$output" = "$expected" ]
}

@test "extracts content from example_response.json file" {
    json=$(cat "$BATS_TEST_DIRNAME/assets/example_response.json")
    tmp_output=$(mktemp)
    response=$(extract_content "${json}")
    $response > "$tmp_output"  
    output=$(cat "$tmp_output")
    [ -n "$output" ]    
    assert_output --partial '### Announcement: Version 0.2.0'
    assert_output --partial 'We are pleased to announce the release of **Version 0.2.0** of our project.'
}
