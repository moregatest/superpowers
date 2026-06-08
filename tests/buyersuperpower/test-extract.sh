#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. tests/buyersuperpower/assert.sh
F=tests/buyersuperpower/fixtures
X="node lib/providers/extract.mjs"

# links: product-ish links found, social/about excluded, returned absolute
L=$($X links "$F/home.html" "https://factory.example/") || fail "links run failed"
echo "$L" | jq -e 'type=="array" and length>=1' >/dev/null || fail "links: expected >=1"
echo "$L" | jq -e 'any(test("products\\.html$"))' >/dev/null || fail "links: products.html not found"
echo "$L" | jq -e 'all(startswith("https://factory.example/"))' >/dev/null || fail "links: not absolute"
echo "$L" | jq -e 'any(test("twitter|about"))|not' >/dev/null || fail "links: social/about leaked"

# products (rich page): name/price/moq/specs/image extracted
P=$($X products "$F/products.html" "https://factory.example/products.html") || fail "products run failed"
echo "$P" | jq -e '.[0].name|test("LED Work Light 50W")' >/dev/null || fail "product name"
echo "$P" | jq -e '.[0].priceHint|test("12\\.50")' >/dev/null || fail "price not extracted"
echo "$P" | jq -e '.[0].moq==500' >/dev/null || fail "moq != 500"
echo "$P" | jq -e '.[0].specs.Power=="50W"' >/dev/null || fail "specs.Power"
echo "$P" | jq -e '.[0].image=="https://factory.example/img/bl-50.jpg"' >/dev/null || fail "image not absolute"
echo "$P" | jq -e '.[0].evidence[0].type=="product_page"' >/dev/null || fail "evidence type"

# thin page: name present, price/moq null (NEVER fabricated)
T=$($X products "$F/thin.html" "https://factory.example/w") || fail "thin run failed"
echo "$T" | jq -e '.[0].priceHint==null and .[0].moq==null' >/dev/null || fail "thin: must be null, not fabricated"
pass "html extractor"
