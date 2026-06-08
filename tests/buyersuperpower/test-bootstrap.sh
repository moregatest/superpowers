#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. tests/buyersuperpower/assert.sh

F=skills/using-buyersuperpower/SKILL.md
assert_file_exists "$F"
# frontmatter
assert_matches "$F" '^name: using-buyersuperpower$'
assert_matches "$F" '^description: Use when'
# persona + 5 safety rules (the agent's safety boundary)
assert_contains "$F" "international sourcing advisor"
assert_contains "$F" "Clarify before"
assert_contains "$F" "fraud"
assert_contains "$F" "Never invent"
assert_contains "$F" "explicit confirmation"
assert_contains "$F" "Never auto-pay"
# language rule
assert_contains "$F" "buyer's language"
# skill-trigger table names all four buyer skills
for s in clarifying-sourcing-need finding-suppliers vetting-suppliers placing-order; do
  assert_contains "$F" "$s"
done
pass "using-buyersuperpower bootstrap"
