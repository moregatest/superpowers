#!/usr/bin/env bash
# Validates buyersuperpower benchmark seeds with NO external deps (bash + grep/sed):
# each seed in a buyer category has the required top-level fields, its `category`
# matches its directory, rule/ai-judge implies rules/rubric, and each buyer
# category carries >= 2 buyer seeds (id prefix `buy-`).
# Usage: test-benchmark-seeds.sh [category ...]   (default: all buyer categories)
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. tests/buyersuperpower/assert.sh

# yval FILE KEY -> trimmed value of the first top-level "key: value" line
yval() { sed -nE "s/^$2:[[:space:]]*//p" "$1" | head -1 | sed -E 's/[[:space:]]+$//; s/^"(.*)"$/\1/'; }

BUYER_CATS="sourcing-compliance anti-fraud anti-bullshit sourcing-quality reasoning"
cats="$*"; [ -n "$cats" ] || cats="$BUYER_CATS"

for cat in $cats; do
  dir="tests/benchmark/seeds/$cat"
  [ -d "$dir" ] || fail "missing category dir: $dir"
  buyern=0
  for f in "$dir"/*.yaml; do
    [ -e "$f" ] || continue
    for k in id category prompt scoring; do
      grep -Eq "^$k:" "$f" || fail "$f: missing field '$k'"
    done
    c="$(yval "$f" category)"
    [ "$c" = "$cat" ] || fail "$f: category '$c' != dir '$cat'"
    case "$(yval "$f" scoring)" in
      rule)     grep -Eq '^rules:'  "$f" || fail "$f: scoring=rule but no rules:" ;;
      ai-judge) grep -Eq '^rubric:' "$f" || fail "$f: scoring=ai-judge but no rubric:" ;;
      *)        fail "$f: scoring must be 'rule' or 'ai-judge'" ;;
    esac
    case "$(yval "$f" id)" in buy-*) buyern=$((buyern + 1)) ;; esac
  done
  [ "$buyern" -ge 2 ] || fail "category '$cat' has $buyern buyer seed(s) (need >= 2)"
done
pass "benchmark buyer seeds ($cats)"
