#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. tests/buyersuperpower/assert.sh

# 1) session-start runs, emits valid JSON, injects buyersuperpower bootstrap
OUT=$(bash hooks/session-start) || fail "session-start exited non-zero"
echo "$OUT" | jq -e . >/dev/null 2>&1 || fail "session-start output is not valid JSON"
CTX=$(echo "$OUT" | jq -r '.hookSpecificOutput.additionalContext')
echo "$CTX" | grep -Fq "You have buyersuperpower" || fail "hook missing 'You have buyersuperpower'"
echo "$CTX" | grep -Fq "international sourcing advisor" || fail "hook missing advisor persona (bootstrap body)"

# 2) OpenCode plugin is valid JS and points at the new bootstrap
node --check .opencode/plugins/superpowers.js || fail "opencode plugin has a syntax error"
assert_contains .opencode/plugins/superpowers.js "using-buyersuperpower"
assert_contains .opencode/plugins/superpowers.js "You have buyersuperpower."
assert_absent  .opencode/plugins/superpowers.js "using-superpowers"
pass "injectors point at using-buyersuperpower"
