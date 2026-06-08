#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. tests/buyersuperpower/assert.sh

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/criteria.json" <<'JSON'
{ "product": "LED work light", "keywords": ["LED","work light"], "destinationCountry": "MX",
  "sourceCountries": ["CN"], "moq": 500, "certs": ["NOM"],
  "targetPrice": { "min": 8, "max": 15, "currency": "USD" }, "limit": 10 }
JSON
cat > "$TMP/urls.json" <<'JSON'
["https://example-brightled.com","https://globaldeal-trading.tk"]
JSON

# contract-shape checker (design §5.3)
assert_contract() { # JSON expected_provider
  echo "$1" | jq -e . >/dev/null 2>&1 || fail "not valid JSON"
  echo "$1" | jq -e --arg p "$2" '.provider==$p' >/dev/null || fail "provider != $2"
  echo "$1" | jq -e 'has("notes")' >/dev/null || fail "missing notes"
  echo "$1" | jq -e '.suppliers|type=="array"' >/dev/null || fail "suppliers not array"
  echo "$1" | jq -e '.suppliers|all(.name and .officialSite and (.evidence|type=="array") and (.products|type=="array"))' >/dev/null || fail "supplier missing required fields"
  echo "$1" | jq -e '[.suppliers[].products[]]|all(.evidence|type=="array")' >/dev/null || fail "product missing evidence array"
}

# search op
OUT=$(node lib/providers/mock.mjs search --criteria "$TMP/criteria.json") || fail "mock search exited non-zero"
assert_contract "$OUT" "mock"
[ "$(echo "$OUT" | jq '.suppliers|length')" -eq 3 ] || fail "expected 3 mock suppliers"

# extract op (consumes urls)
OUT2=$(node lib/providers/mock.mjs extract --urls "$TMP/urls.json" --criteria "$TMP/criteria.json") || fail "mock extract exited non-zero"
assert_contract "$OUT2" "mock"

# 3 risk tiers present (so PR3 anti-fraud / anti-bullshit have material)
echo "$OUT" | jq -e '[.suppliers[].evidence[].text]|any(test("personal account"))' >/dev/null || fail "missing fraud signal: personal account"
echo "$OUT" | jq -e '[.suppliers[].evidence[].text]|any(test("gmail"))' >/dev/null || fail "missing fraud signal: free email"
echo "$OUT" | jq -e 'any(.suppliers[].products[]; .moq==null)' >/dev/null || fail "missing thin/unknown supplier (null moq)"
pass "mock provider"
