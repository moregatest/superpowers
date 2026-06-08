#!/usr/bin/env bash
# Tiny assertion helpers for buyersuperpower tests.
set -uo pipefail

fail() { echo "ASSERT FAIL: $1" >&2; exit 1; }

assert_file_exists() { [ -f "$1" ] || fail "missing file: $1"; }

# assert_contains FILE LITERAL
assert_contains() { grep -Fq -- "$2" "$1" || fail "'$1' missing literal: $2"; }

# assert_matches FILE EXTENDED_REGEX
assert_matches() { grep -Eq -- "$2" "$1" || fail "'$1' missing pattern: $2"; }

# assert_absent FILE LITERAL
assert_absent() { ! grep -Fq -- "$2" "$1" || fail "'$1' should NOT contain: $2"; }

# assert_json_eq FILE JQ_FILTER EXPECTED
assert_json_eq() {
  local got; got=$(jq -r "$2" "$1") || fail "jq failed: $1 $2"
  [ "$got" = "$3" ] || fail "$1 :: $2 = '$got' (expected '$3')"
}

pass() { echo "PASS: ${1:-ok}"; }
