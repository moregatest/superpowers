#!/usr/bin/env bash
# buyersuperpower supplier-search dispatcher.
# Usage: search-suppliers.sh <extract|search> [--provider NAME] [--criteria FILE] [--urls FILE]
# Selects a provider (--provider, else default_provider from providers.config.yaml),
# runs lib/providers/<provider>.mjs with the op + remaining args, and passes its
# JSON through on stdout. Relative --criteria/--urls paths resolve against the
# caller's cwd (node is run without changing directory). Bash-3.2 safe.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG="${REPO_ROOT}/tools/providers.config.yaml"

die() { echo "search-suppliers: $1" >&2; exit 2; }

op="${1:-}"
case "$op" in
  extract|search) shift ;;
  *) die "first argument must be 'extract' or 'search' (got '${op}')" ;;
esac

provider=""
passthru=()
while [ $# -gt 0 ]; do
  case "$1" in
    --provider)
      [ $# -ge 2 ] || die "--provider requires a value"
      provider="$2"; shift 2 ;;
    *) passthru+=("$1"); shift ;;
  esac
done

if [ -z "$provider" ]; then
  provider="$(grep -E '^default_provider:' "$CONFIG" 2>/dev/null | head -1 | sed -E 's/^default_provider:[[:space:]]*//; s/#.*$//' | tr -d '\042\047[:space:]')"
  [ -n "$provider" ] || die "no --provider given and default_provider not found in ${CONFIG}"
fi

case "$provider" in
  */*|*..*) die "invalid provider name '${provider}' (must be a bare name in lib/providers/)" ;;
esac

script="${REPO_ROOT}/lib/providers/${provider}.mjs"
[ -f "$script" ] || die "unknown provider '${provider}' (no such file: ${script})"

command -v node >/dev/null 2>&1 || die "node not found on PATH"
# ${passthru[@]+...} keeps this safe under `set -u` with an empty array on bash 3.2.
exec node "$script" "$op" ${passthru[@]+"${passthru[@]}"}
