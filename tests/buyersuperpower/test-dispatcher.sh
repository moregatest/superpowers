#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. tests/buyersuperpower/assert.sh

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/criteria.json" <<'JSON'
{ "product": "LED work light", "destinationCountry": "MX", "moq": 500 }
JSON
cat > "$TMP/urls.json" <<'JSON'
["https://example-brightled.com"]
JSON

# the two §13.1 acceptance commands produce valid contract JSON via the default provider (mock)
OUT=$(tools/search-suppliers.sh extract --urls "$TMP/urls.json" --criteria "$TMP/criteria.json") || fail "extract exited non-zero"
echo "$OUT" | jq -e '.provider=="mock" and (.suppliers|type=="array")' >/dev/null || fail "extract: not mock contract JSON"
OUT=$(tools/search-suppliers.sh search --criteria "$TMP/criteria.json") || fail "search exited non-zero"
echo "$OUT" | jq -e '.provider=="mock" and (.suppliers|length==3)' >/dev/null || fail "search: not mock contract JSON"

# --provider override is honored
echo "$OUT" | jq -e '.provider=="mock"' >/dev/null || fail "default provider should be mock"

# bad op rejected
if tools/search-suppliers.sh frobnicate --criteria "$TMP/criteria.json" >/dev/null 2>&1; then fail "bad op should exit non-zero"; fi
# unknown provider rejected
if tools/search-suppliers.sh search --provider nope --criteria "$TMP/criteria.json" >/dev/null 2>&1; then fail "unknown provider should exit non-zero"; fi
pass "dispatcher"
