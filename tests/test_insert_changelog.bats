#!/usr/bin/env bats

mkdir -p "$BATS_TEST_DIRNAME/.logs"
source "$BATS_TEST_DIRNAME/../changes.sh"
export ERROR_LOG="$BATS_TEST_DIRNAME/.logs/error.log"
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

# Helper to call insert_changelog with all required args
run_insert_changelog() {
    local file="$1"
    local content="$2"
    local section_name="$3"
    local update_mode="$4"
    local existing_section="$5"
    insert_changelog "$file" "$content" "$section_name" "$update_mode" "$existing_section"
}

@test "update mode: updates existing section" {
    
    cat >CHANGELOG.md <<EOF
# Changelog

## v1.0.0
- old content

## v0.9.0
- previous
EOF
    run run_insert_changelog CHANGELOG.md "- new content" "v1.0.0" update "## v1.0.0\n- old content"
    [ "$status" -eq 0 ] || {
        echo "insert_changelog failed with status $status" >>"$ERROR_LOG"
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
    run run_insert_changelog CHANGELOG.md "- auto new" "v2.0.0" auto "## v2.0.0\n- old auto"
    [ "$status" -eq 0 ] || {
        echo "insert_changelog failed with status $status" >>"$ERROR_LOG"
        cat CHANGELOG.md >>"$ERROR_LOG"
        false
    }
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
    run insert_changelog CHANGELOG.md "- prepended" "v3.0.0" prepend "## v3.0.0\n- keep"
    [ "$status" -eq 0 ] || {
        echo "insert_changelog failed with status $status" >>"$ERROR_LOG"
        cat CHANGELOG.md >>"$ERROR_LOG"
        false
    }
    pos1=$(grep -Fn -- "- prepended" CHANGELOG.md | cut -d: -f1)
    pos2=$(grep -n "## v3.0.0" CHANGELOG.md | cut -d: -f1)
    [ "$pos1" -lt "$pos2" ] || {
        echo "Expected '- prepended' before '## v3.0.0' (lines $pos1 < $pos2)" >>"$ERROR_LOG"
        cat CHANGELOG.md >>"$ERROR_LOG"
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
    run insert_changelog CHANGELOG.md "- appended" "v4.0.0" append "## v4.0.0\n- keep"
    [ "$status" -eq 0 ] || {
        echo "insert_changelog failed with status $status" >>"$ERROR_LOG"
        cat CHANGELOG.md >>"$ERROR_LOG"
        false
    }
    pos1=$(grep -Fn -- "- appended" CHANGELOG.md | cut -d: -f1)
    pos2=$(grep -n "## v4.0.0" CHANGELOG.md | cut -d: -f1)
    pos3=$(grep -n "## v3.0.0" CHANGELOG.md | cut -d: -f1)
    [ "$pos1" -gt "$pos2" ] || {
        echo "Expected '- appended' after '## v4.0.0' (lines $pos1 > $pos2)" >>"$ERROR_LOG"
        cat CHANGELOG.md >>"$ERROR_LOG"
        false
    }
    [ "$pos1" -lt "$pos3" ] || {
        echo "Expected '- appended' before '## v3.0.0' (lines $pos1 < $pos3)" >>"$ERROR_LOG"
        cat CHANGELOG.md >>"$ERROR_LOG"
        false
    }
    echo "Changelog created successfully" >>"$ERROR_LOG"
    cat CHANGELOG.md >>"$ERROR_LOG"

}

@test "update mode: adds new section if not found" {
    cat >CHANGELOG.md <<EOF
# Changelog

## v5.0.0
- keep
EOF
    run insert_changelog CHANGELOG.md "- new section" "v6.0.0" update ""
    [ "$status" -eq 0 ] || {
        echo "insert_changelog failed with status $status" >>"$ERROR_LOG"
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
    cat CHANGELOG.md >>"$ERROR_LOG"

}

@test "prepend mode: adds new section if not found" {
    
    cat >CHANGELOG.md <<EOF
# Changelog

## v7.0.0
- keep
EOF
    run insert_changelog CHANGELOG.md "- prepended new" "v8.0.0" prepend ""
    [ "$status" -eq 0 ] || {
        echo "insert_changelog failed with status $status" >>"$ERROR_LOG"
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
    run insert_changelog CHANGELOG.md "- appended new" "v10.0.0" append ""
    [ "$status" -eq 0 ] || {
        echo "insert_changelog failed with status $status" >>"$ERROR_LOG"
        cat CHANGELOG.md >>"$ERROR_LOG"
        false
    }
    tail -n5 CHANGELOG.md | grep -q "## v10.0.0" || {
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
    run insert_changelog CHANGELOG.md "- first entry" "v0.1.0" update ""
    [ "$status" -eq 0 ] || {
        echo "insert_changelog failed with status $status" >>"$ERROR_LOG"
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
    run insert_changelog CHANGELOG.md $'- line1\n- line2\n- line3' "v11.0.0" update "## v11.0.0\n- keep"
    [ "$status" -eq 0 ] || {
        echo "insert_changelog failed with status $status" >>"$ERROR_LOG"
        cat CHANGELOG.md >>"$ERROR_LOG"
        false
    }
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

@test "content is surrounded by newlines in changelog" {
    cat >CHANGELOG.md <<EOF
# Changelog

## v1.2.3
- old
EOF
    run insert_changelog CHANGELOG.md $'- new1\n- new2' "v1.2.3" prepend "## v1.2.3\n- old"
    [ "$status" -eq 0 ] || {
        echo "insert_changelog failed with status $status" >>"$ERROR_LOG"
        cat CHANGELOG.md >>"$ERROR_LOG"
        false
    }
    cat CHANGELOG.md >>"$ERROR_LOG"
    # Extract the section
    start=$(grep -n '^## Current Changes' CHANGELOG.md | cut -d: -f1)
    end=$(tail -n +$((start+1)) CHANGELOG.md | grep -n '^## ' | head -n1 | cut -d: -f1)
    if [ -n "$end" ]; then
        end=$((start + end - 1))
    else
        end=$(wc -l <CHANGELOG.md)
    fi
    section=$(sed -n "$start,${end}p" CHANGELOG.md)
    # Check for leading and trailing newlines around content
    # Remove the header line
    content_only=$(echo "$section" | tail -n +2)
    # Should start and end with a blank line
    first_line=$(echo "$content_only" | head -n1)
    last_line=$(echo "$content_only" | tail -n1)
    [ -z "$first_line" ] || {
        echo "Expected blank line before content in section" >>"$ERROR_LOG"
        echo "$section" >>"$ERROR_LOG"
        false
    }
    [ -z "$last_line" ] || {
        echo "Expected blank line after content in section" >>"$ERROR_LOG"
        echo "$section" >>"$ERROR_LOG"
        false
    }
    echo "Changelog section is surrounded by newlines" >>"$ERROR_LOG"
    echo "$section" >>"$ERROR_LOG"
}

