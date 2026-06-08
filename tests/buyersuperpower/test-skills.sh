#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. tests/buyersuperpower/assert.sh

# every buyer skill: valid frontmatter, description starts with "Use when"
for s in clarifying-sourcing-need vetting-suppliers finding-suppliers placing-order; do
  F="skills/$s/SKILL.md"
  assert_file_exists "$F"
  assert_matches "$F" "^name: $s$"
  assert_matches "$F" '^description: Use when'
done

# clarifying: collects criteria, asks one at a time
assert_contains skills/clarifying-sourcing-need/SKILL.md "certifications"
assert_contains skills/clarifying-sourcing-need/SKILL.md "one question at a time"

# vetting: risk+confidence, the 4-level matrix, evidence
V=skills/vetting-suppliers/SKILL.md
assert_contains "$V" "riskLevel"
assert_contains "$V" "confidence"
assert_contains "$V" "unknown"
assert_contains "$V" "personal account"
assert_contains "$V" "evidence"

# finding: discover-then-extract, vetting-as-rule, provider command, honesty
Fd=skills/finding-suppliers/SKILL.md
assert_contains "$Fd" "tools/search-suppliers.sh extract"
assert_contains "$Fd" "load and apply vetting-suppliers"
assert_contains "$Fd" "Filter OUT"
assert_contains "$Fd" "Never invent"

# placing-order: english RFQ, never send / never auto-pay
P=skills/placing-order/SKILL.md
assert_contains "$P" "inquiry"
assert_contains "$P" "explicit confirmation"
assert_contains "$P" "Never auto-pay"
pass "4 buyer skills"
