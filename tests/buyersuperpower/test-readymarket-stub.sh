#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. tests/buyersuperpower/assert.sh

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
echo '{ "product": "LED work light" }' > "$TMP/criteria.json"

OUT=$(tools/search-suppliers.sh search --provider readymarket-api --criteria "$TMP/criteria.json") || fail "stub exited non-zero"
echo "$OUT" | jq -e . >/dev/null 2>&1 || fail "stub output not valid JSON"
echo "$OUT" | jq -e '.provider=="readymarket-api"' >/dev/null || fail "stub provider field wrong"
echo "$OUT" | jq -e '.suppliers|length==0' >/dev/null || fail "stub should return empty suppliers"
echo "$OUT" | jq -e '.notes|test("not implemented")' >/dev/null || fail "stub should note not-implemented"
pass "readymarket-api stub"
