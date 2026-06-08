#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. tests/buyersuperpower/assert.sh

# always: both modules are valid JS
node --check lib/providers/extract.mjs   || fail "extract.mjs syntax error"
node --check lib/providers/playwright.mjs || fail "playwright.mjs syntax error"

# always: the PR2 dispatcher routes --provider playwright to this module
printf '%s' '["https://example.com"]' > /tmp/bsp-urls.json
if node -e "require.resolve('playwright')" 2>/dev/null; then
  : # installed — full path tested below
else
  # not installed: provider must fail cleanly (exit 3) with an actionable message,
  # which proves the dispatcher reached playwright.mjs
  err=$(tools/search-suppliers.sh extract --provider playwright --urls /tmp/bsp-urls.json 2>&1 >/dev/null; true)
  echo "$err" | grep -qi "playwright not installed" || fail "dispatcher did not route to playwright (got: $err)"
  echo "SKIP: playwright not installed — extractor is covered by test-extract.sh; run 'npm install && npx playwright install chromium' to exercise the browser path"
  pass "playwright provider (checks; integration skipped)"
  exit 0
fi

# installed: run a real extract over file:// fixtures and assert the §5.3 contract
F="$(pwd)/tests/buyersuperpower/fixtures"
printf '%s' "[\"file://$F/home.html\"]" > /tmp/bsp-urls.json
printf '%s' '{ "product":"LED work light" }' > /tmp/bsp-crit.json
OUT=$(BSP_RATE_MS=1 tools/search-suppliers.sh extract --provider playwright --urls /tmp/bsp-urls.json --criteria /tmp/bsp-crit.json) || fail "playwright extract failed"
echo "$OUT" | jq -e '.provider=="playwright"' >/dev/null || fail "provider field"
echo "$OUT" | jq -e '.suppliers|type=="array" and length==1' >/dev/null || fail "one supplier expected"
echo "$OUT" | jq -e '.suppliers[0].evidence|type=="array"' >/dev/null || fail "evidence array"
echo "$OUT" | jq -e '[.suppliers[0].products[].name]|any(test("LED Work Light 50W"))' >/dev/null || fail "did not extract the product via the browser"
pass "playwright provider (integration)"
