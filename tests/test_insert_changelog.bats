#!/usr/bin/env bats

mkdir -p "$BATS_TEST_DIRNAME/.logs"
source "$BATS_TEST_DIRNAME/../changes.sh"
export ERROR_LOG="$BATS_TEST_DIRNAME/.logs/error.log"
load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
#echo >$ERROR_LOG
setup_file() {
    # Ensure the error log is empty before each test
    : >"$ERROR_LOG"
}
export debug=true
setup() {
    TMP_DIR=$(mktemp -d)
    cd "$TMP_DIR"
    echo "===========================" >>"$ERROR_LOG"
    echo "Running $BATS_TEST_NAME" >>"$ERROR_LOG"
}

teardown() {
    echo "Completed $BATS_TEST_NAME" >>"$ERROR_LOG"
    echo "===========================" >>"$ERROR_LOG"

    cd /
    rm -rf "$TMP_DIR"
}

# Helper to call update_changelog with all required args
run_update_changelog() {
    local file="$1"
    local content="$2"
    local section_name="$3"
    local update_mode="$4"
    local existing_section="$5"
    update_changelog "$file" "$content" "$section_name" "$update_mode" "$existing_section"
}

@test "update mode: updates existing section" {

    cat >CHANGELOG.md <<EOF
# Changelog

## v1.0.0
- old content

## v0.9.0
- previous
EOF
    run run_update_changelog CHANGELOG.md "- new content" "v1.0.0" update "## v1.0.0\n- old content"
    [ "$status" -eq 0 ] || {
        echo "update_changelog failed with status $status" >>"$ERROR_LOG"
        cat CHANGELOG.md >>"$ERROR_LOG"
        false
    }

    grep -Fq -- "- new content" CHANGELOG.md || {
        echo "Expected '- new content' in CHANGELOG.md" >>"$ERROR_LOG"
        cat CHANGELOG.md >>"$ERROR_LOG"
        false
    }
    ! grep -q "- old content" CHANGELOG.md || {
        echo "Did not expect '- old content' in CHANGELOG.md" >>"$ERROR_LOG"
        cat CHANGELOG.md >>"$ERROR_LOG"
        false
    }
    echo "Changelog created successfully" >>"$ERROR_LOG"
    cat CHANGELOG.md >>"$ERROR_LOG"
}

@test "auto mode: updates existing section" {

    cat >CHANGELOG.md <<EOF
# Changelog

## v2.0.0
- old auto
EOF
    run run_update_changelog CHANGELOG.md "- auto new" "v2.0.0" auto "## v2.0.0\n- old auto"
    cat CHANGELOG.md >>"$ERROR_LOG"
    assert_success
    grep -Fq -- "- auto new" CHANGELOG.md || {
        echo "Expected '- auto new' in CHANGELOG.md" >>"$ERROR_LOG"
        cat CHANGELOG.md >>"$ERROR_LOG"
        false
    }
    ! grep -q "- old auto" CHANGELOG.md || {
        echo "Did not expect '- old auto' in CHANGELOG.md" >>"$ERROR_LOG"
        cat CHANGELOG.md >>"$ERROR_LOG"
        false
    }
    echo "Changelog created successfully" >>"$ERROR_LOG"
    cat CHANGELOG.md >>"$ERROR_LOG"

}

@test "prepend mode: inserts before section" {

    cat >CHANGELOG.md <<EOF
# Changelog

## v3.0.0
- keep
EOF
    run update_changelog CHANGELOG.md "- prepended" "v3.0.0" prepend "## v3.0.0\n- keep"
    [ "$status" -eq 0 ] || {
        echo "update_changelog failed with status $status" >>"$ERROR_LOG"
        cat CHANGELOG.md >>"$ERROR_LOG"
        false
    }
    # Remove trailing blank lines for comparison
    expected_content=$'# Changelog\n\n## v3.0.0\n\n- prepended\n\n## v3.0.0\n\n- keep\n\n[Managed by changeish](https://github.com/itlackey/changeish)'
    actual_content=$(sed '${/^$/d;}' CHANGELOG.md)
    [ "$actual_content" = "$expected_content" ] || {
        echo "CHANGELOG.md content did not match expected:" >>"$ERROR_LOG"
        echo "Expected:" >>"$ERROR_LOG"
        printf "%s" "$expected_content" >>"$ERROR_LOG"
        echo "Actual:" >>"$ERROR_LOG"
        printf "%s\n" "$actual_content" >>"$ERROR_LOG"
        false
    }
    echo "Changelog created successfully" >>"$ERROR_LOG"
    cat CHANGELOG.md >>"$ERROR_LOG"

}

@test "append mode: inserts after section" {

    cat >CHANGELOG.md <<EOF
# Changelog

## v4.0.0

- keep

## v3.0.0

- old
EOF
    run update_changelog CHANGELOG.md "- appended" "v4.0.0" append "## v4.0.0\n- keep"
    [ "$status" -eq 0 ] || {
        echo "update_changelog failed with status $status" >>"$ERROR_LOG"
        cat CHANGELOG.md >>"$ERROR_LOG"
        false
    }
    expected_content=$'# Changelog\n\n## v4.0.0\n\n- keep\n\n## v3.0.0\n\n- old\n\n## v4.0.0\n\n- appended\n\n[Managed by changeish](https://github.com/itlackey/changeish)'
    actual_content=$(sed '${/^$/d;}' CHANGELOG.md)
    [ "$actual_content" = "$expected_content" ] || {
        echo "CHANGELOG.md content did not match expected:" >>"$ERROR_LOG"
        echo "Expected:" >>"$ERROR_LOG"
        printf "%s\n" "$expected_content" >>"$ERROR_LOG"
        echo "Actual:" >>"$ERROR_LOG"
        printf "%s\n" "$actual_content" >>"$ERROR_LOG"
        false
    }
    echo "Changelog created successfully" >>"$ERROR_LOG"
    cat CHANGELOG.md >>"$ERROR_LOG"

}



@test "prepend mode: adds new section if not found" {

    cat >CHANGELOG.md <<EOF
# Changelog

## v7.0.0
- keep
EOF
    run update_changelog CHANGELOG.md "- prepended new" "v8.0.0" prepend ""
    [ "$status" -eq 0 ] || {
        echo "update_changelog failed with status $status" >>"$ERROR_LOG"
        cat CHANGELOG.md >>"$ERROR_LOG"
        false
    }
    grep -q "## v8.0.0" CHANGELOG.md || {
        echo "Expected '## v8.0.0' in CHANGELOG.md" >>"$ERROR_LOG"
        cat CHANGELOG.md >>"$ERROR_LOG"
        false
    }
    grep -qF -- "- prepended new" CHANGELOG.md || {
        echo "Expected '- prepended new' in CHANGELOG.md" >>"$ERROR_LOG"
        cat CHANGELOG.md >>"$ERROR_LOG"
        false
    }
    echo "Changelog created successfully" >>"$ERROR_LOG"
    cat CHANGELOG.md >>"$ERROR_LOG"

}

@test "append mode: adds new section at end if not found" {

    cat >CHANGELOG.md <<EOF
# Changelog

## v9.0.0
- keep
EOF
    run update_changelog CHANGELOG.md "- appended new" "v10.0.0" append ""
    [ "$status" -eq 0 ] || {
        echo "update_changelog failed with status $status" >>"$ERROR_LOG"
        cat CHANGELOG.md >>"$ERROR_LOG"
        false
    }
    tail -n6 CHANGELOG.md | grep -q "## v10.0.0" || {
        echo "Expected '## v10.0.0' at end of CHANGELOG.md" >>"$ERROR_LOG"
        cat CHANGELOG.md >>"$ERROR_LOG"
        false
    }
    tail -n5 CHANGELOG.md | grep -qF -- "- appended new" || {
        echo "Expected '- appended new' at end of CHANGELOG.md" >>"$ERROR_LOG"
        cat CHANGELOG.md >>"$ERROR_LOG"
        false
    }
    echo "Changelog created successfully" >>"$ERROR_LOG"
    cat CHANGELOG.md >>"$ERROR_LOG"

}

@test "handles empty changelog file (creates section)" {

    rm -f CHANGELOG.md
    run update_changelog CHANGELOG.md "- first entry" "v0.1.0" update ""
    [ "$status" -eq 0 ] || {
        echo "update_changelog failed with status $status" >>"$ERROR_LOG"
        #cat CHANGELOG.md >>"$ERROR_LOG"
        false
    }
    grep -q "## v0.1.0" CHANGELOG.md || {
        echo "Expected '## v0.1.0' in CHANGELOG.md" >>"$ERROR_LOG"
        #cat CHANGELOG.md >>"$ERROR_LOG"
        false
    }
    grep -qF -- "- first entry" CHANGELOG.md || {
        echo "Expected '- first entry' in CHANGELOG.md" >>"$ERROR_LOG"
        #cat CHANGELOG.md >>"$ERROR_LOG"
        false
    }
    echo "Changelog created successfully" >>"$ERROR_LOG"
    cat CHANGELOG.md >>"$ERROR_LOG"

}

@test "handles multiline content" {

    cat >CHANGELOG.md <<EOF
# Changelog

## v11.0.0
- keep
EOF
    run update_changelog CHANGELOG.md $'- line1\n- line2\n- line3' "v11.0.0" update
    cat CHANGELOG.md >>"$ERROR_LOG"
    assert_success
    grep -qF -- "- line1" CHANGELOG.md || {
        echo "Expected '- line1' in CHANGELOG.md" >>"$ERROR_LOG"
        cat CHANGELOG.md >>"$ERROR_LOG"
        false
    }
    grep -qF -- "- line2" CHANGELOG.md || {
        echo "Expected '- line2' in CHANGELOG.md" >>"$ERROR_LOG"
        cat CHANGELOG.md >>"$ERROR_LOG"
        false
    }
    grep -qF -- "- line3" CHANGELOG.md || {
        echo "Expected '- line3' in CHANGELOG.md" >>"$ERROR_LOG"
        cat CHANGELOG.md >>"$ERROR_LOG"
        false
    }
    echo "Changelog created successfully" >>"$ERROR_LOG"
    cat CHANGELOG.md >>"$ERROR_LOG"
}

# @test "no duplicate headers and only one first-level heading" {
#     cat >CHANGELOG.md <<EOF
# # Changelog

# ## v1.2.3
# - old
# EOF
#     run update_changelog CHANGELOG.md $'- new1\n- new2' "v1.2.3" prepend "## v1.2.3\n- old"
#     assert_success
#     cat CHANGELOG.md >>"$ERROR_LOG"

#     # Check for any duplicate header lines
#     duplicates=$(grep '^#' CHANGELOG.md | sort | uniq -d)
#     [ -z "$duplicates" ] || {
#         echo "Duplicate header(s) found:"
#         echo "$duplicates"
#         return 1
#     }

#     # Ensure there is exactly one first‐level heading (H1)
#     h1_count=$(grep -c '^# ' CHANGELOG.md)
#     [ "$h1_count" -eq 1 ] || {
#         echo "Expected exactly one first-level heading, but found $h1_count"
#         return 1
#     }
# }

@test "all headers are surrounded by blank lines and file ends with newline" {
    cat >CHANGELOG.md <<EOF
# Changelog


## v1.2.3
- old

EOF
    run update_changelog CHANGELOG.md $'- new1\n- new2' "v1.2.3" prepend "## v1.2.3\n- old"
    cat CHANGELOG.md >>"$ERROR_LOG"
    # for each header line, ensure blank line before and after
    while read -r line; do
        lineno="${line%%:*}"
        header="${line#*:}"
        echo "Checking header at line $lineno ||" >>"$ERROR_LOG"
        if [ "$lineno" -gt 1 ]; then
            prev=$(sed -n "$((lineno - 1))p" CHANGELOG.md)
            echo "Previous line before header at $lineno: '$prev'" >>"$ERROR_LOG"
            [ -z "$prev" ] || {
                echo "Header at line $lineno not preceded by blank line" >>"$ERROR_LOG"
                return 1
            }
        fi
        next=$(sed -n "$((lineno + 1))p" CHANGELOG.md)
        echo "Next line after header at $lineno: '$next'" >>"$ERROR_LOG"
        # Only check next if not past end of file
        if [ "$((lineno + 1))" -le "$(wc -l <CHANGELOG.md)" ]; then
            [ -z "$next" ] || {
                echo "Header at line $lineno not followed by blank line" >>"$ERROR_LOG"
                return 1
            }
        fi
    done < <(grep -n '^#' CHANGELOG.md)

    # ensure the file ends with a newline
    last_char=$(tail -c1 CHANGELOG.md)
    [ -z "$last_char" ] || {
        echo "CHANGELOG.md does not end with a newline" >>"$ERROR_LOG"
        return 1
    }
}

@test "auto mode: section exists: replaces section" {
    cat >CHANGELOG.md <<EOF
# Changelog

## v2.1.0
- old auto
EOF
    run update_changelog CHANGELOG.md "- auto new" "v2.1.0" auto "## v2.1.0\n- old auto"
    assert_success
    grep -Fq -- "- auto new" CHANGELOG.md
    ! grep -q "- old auto" CHANGELOG.md
}

@test "auto mode: section does not exist: prepends new section" {
    cat >CHANGELOG.md <<EOF
# Changelog

## v2.2.0
- keep
EOF
    run update_changelog CHANGELOG.md "- auto new" "v2.3.0" auto ""
    assert_success
    first_section=$(grep -n '^## ' CHANGELOG.md | head -1 | cut -d: -f2)
    [ "$first_section" = "## v2.3.0" ]
    grep -Fq -- "- auto new" CHANGELOG.md
}

@test "update mode: section exists: replaces section" {
    cat >CHANGELOG.md <<EOF
# Changelog

## v3.0.0
- old content
EOF
    run update_changelog CHANGELOG.md "- new content" "v3.0.0" update "## v3.0.0\n- old content"
    assert_success
    grep -Fq -- "- new content" CHANGELOG.md
    ! grep -q "- old content" CHANGELOG.md
}

@test "update mode: adds new section if not found" {
    cat >CHANGELOG.md <<EOF
# Changelog

## v5.0.0
- keep
EOF
    run update_changelog CHANGELOG.md "- new section" "v6.0.0" update ""
    cat CHANGELOG.md >>"$ERROR_LOG"
    [ "$status" -eq 0 ] || {
        echo "update_changelog failed with status $status" >>"$ERROR_LOG"
        cat CHANGELOG.md >>"$ERROR_LOG"
        false
    }
    grep -q "## v6.0.0" CHANGELOG.md || {
        echo "Expected '## v6.0.0' in CHANGELOG.md" >>"$ERROR_LOG"
        cat CHANGELOG.md >>"$ERROR_LOG"
        false
    }
    grep -qF -- "- new section" CHANGELOG.md || {
        echo "Expected '- new section' in CHANGELOG.md" >>"$ERROR_LOG"
        cat CHANGELOG.md >>"$ERROR_LOG"
        false
    }
    echo "Changelog created successfully" >>"$ERROR_LOG"

}

@test "prepend mode: section exists: inserts duplicate at top" {
    cat >CHANGELOG.md <<EOF
# Changelog

## v4.0.0
- old
EOF
    run update_changelog CHANGELOG.md "- new prepended" "v4.0.0" prepend "## v4.0.0\n- old"
    assert_success
    # Should have two v4.0.0 sections, new one at top
    [ $(grep -c '^## v4.0.0' CHANGELOG.md) -eq 2 ]
    first_section=$(grep -n '^## ' CHANGELOG.md | head -1 | cut -d: -f2)
    [ "$first_section" = "## v4.0.0" ]
    grep -Fq -- "- new prepended" CHANGELOG.md
}

@test "prepend mode: section does not exist: inserts at top" {
    cat >CHANGELOG.md <<EOF
# Changelog

## v4.1.0
- keep
EOF
    run update_changelog CHANGELOG.md "- new prepended" "v4.2.0" prepend ""
    assert_success
    first_section=$(grep -n '^## ' CHANGELOG.md | head -1 | cut -d: -f2)
    [ "$first_section" = "## v4.2.0" ]
    grep -Fq -- "- new prepended" CHANGELOG.md
}

@test "append mode: section exists: inserts duplicate at bottom" {
    cat >CHANGELOG.md <<EOF
# Changelog

## v5.0.0
- old
EOF
    run update_changelog CHANGELOG.md "- new appended" "v5.0.0" append "## v5.0.0\n- old"
    assert_success
    [ $(grep -c '^## v5.0.0' CHANGELOG.md) -eq 2 ]
    last_section=$(grep -n '^## ' CHANGELOG.md | tail -1 | cut -d: -f2)
    [ "$last_section" = "## v5.0.0" ]
    grep -Fq -- "- new appended" CHANGELOG.md
}

@test "append mode: section does not exist: inserts at bottom" {
    cat >CHANGELOG.md <<EOF
# Changelog

## v5.1.0
- keep
EOF
    run update_changelog CHANGELOG.md "- new appended" "v5.2.0" append ""
    assert_success
    last_section=$(grep -n '^## ' CHANGELOG.md | tail -1 | cut -d: -f2)
    [ "$last_section" = "## v5.2.0" ]
    grep -Fq -- "- new appended" CHANGELOG.md
}
