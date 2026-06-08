#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. tests/buyersuperpower/assert.sh

for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json .cursor-plugin/plugin.json; do
  jq -e . "$f" >/dev/null 2>&1 || fail "$f is not valid JSON"
done
assert_json_eq .claude-plugin/plugin.json '.name' 'buyersuperpower'
assert_json_eq .claude-plugin/plugin.json '.version' '0.1.0'
assert_json_eq .claude-plugin/marketplace.json '.plugins[0].name' 'buyersuperpower'
assert_json_eq .claude-plugin/marketplace.json '.plugins[0].version' '0.1.0'
assert_json_eq .cursor-plugin/plugin.json '.name' 'buyersuperpower'
assert_json_eq .cursor-plugin/plugin.json '.version' '0.1.0'
pass "plugin metadata rebranded"
