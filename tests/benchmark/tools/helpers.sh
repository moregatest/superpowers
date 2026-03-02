#!/usr/bin/env bash
# Shared helpers for the benchmark pipeline
# Requires: python3, jq

set -euo pipefail

BENCHMARK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="$BENCHMARK_DIR/tools"
SEEDS_DIR="$BENCHMARK_DIR/seeds"
PENDING_DIR="$BENCHMARK_DIR/generated/pending"
APPROVED_DIR="$BENCHMARK_DIR/generated/approved"
REJECTED_DIR="$BENCHMARK_DIR/generated/rejected"
RESULTS_DIR="$BENCHMARK_DIR/results"
CONFIG_FILE="$TOOLS_DIR/config.yaml"

# Parse a YAML file and extract a field using python3
# Usage: yaml_get <file> <dotted.key> [default]
yaml_get() {
    local file="$1"
    local key="$2"
    local default="${3:-}"
    python3 -c "
import yaml, sys
with open('$file') as f:
    d = yaml.safe_load(f)
keys = '$key'.split('.')
for k in keys:
    if isinstance(d, dict) and k in d:
        d = d[k]
    else:
        d = None
        break
if d is None:
    print('$default')
else:
    print(d)
" 2>/dev/null || echo "$default"
}

# Read full YAML file as JSON (for passing to prompts)
# Usage: yaml_to_json <file>
yaml_to_json() {
    local file="$1"
    python3 -c "
import yaml, json, sys
with open('$file') as f:
    d = yaml.safe_load(f)
print(json.dumps(d, ensure_ascii=False, indent=2))
"
}

# Read YAML file as raw text
# Usage: yaml_raw <file>
yaml_raw() {
    cat "$1"
}

# Get config value with fallback
# Usage: config_get <dotted.key> [default]
config_get() {
    yaml_get "$CONFIG_FILE" "$1" "${2:-}"
}

# Build tool execution command
# Usage: build_tool_cmd <tool> <prompt> [project_dir]
build_tool_cmd() {
    local tool="$1"
    local prompt="$2"
    local project_dir="${3:-.}"

    case "$tool" in
        claude)
            echo "claude -p $(printf '%q' "$prompt") --permission-mode bypassPermissions --output-format stream-json --add-dir $(printf '%q' "$project_dir") --cwd $(printf '%q' "$project_dir")"
            ;;
        codex)
            echo "codex exec $(printf '%q' "$prompt")"
            ;;
        opencode)
            echo "cd $(printf '%q' "$project_dir") && opencode run $(printf '%q' "$prompt")"
            ;;
        *)
            echo "ERROR: Unknown tool: $tool" >&2
            return 1
            ;;
    esac
}

# Print a formatted header
# Usage: print_header "Title"
print_header() {
    local title="$1"
    local width=50
    echo ""
    printf '=%.0s' $(seq 1 $width)
    echo ""
    echo " $title"
    printf '=%.0s' $(seq 1 $width)
    echo ""
}

# Print a separator line
# Usage: print_sep
print_sep() {
    printf -- '-%.0s' $(seq 1 50)
    echo ""
}

# Validate a seed YAML has required fields
# Usage: validate_seed <file>
validate_seed() {
    local file="$1"
    local errors=0

    for field in id category prompt scoring; do
        local val
        val=$(yaml_get "$file" "$field")
        if [ -z "$val" ]; then
            echo "ERROR: Missing required field '$field' in $file" >&2
            errors=$((errors + 1))
        fi
    done

    local scoring
    scoring=$(yaml_get "$file" "scoring")
    if [ "$scoring" = "rule" ]; then
        local rules
        rules=$(yaml_get "$file" "rules")
        if [ -z "$rules" ] || [ "$rules" = "None" ]; then
            echo "ERROR: scoring=rule but no rules defined in $file" >&2
            errors=$((errors + 1))
        fi
    elif [ "$scoring" = "ai-judge" ]; then
        local rubric
        rubric=$(yaml_get "$file" "rubric")
        if [ -z "$rubric" ] || [ "$rubric" = "None" ]; then
            echo "ERROR: scoring=ai-judge but no rubric defined in $file" >&2
            errors=$((errors + 1))
        fi
    fi

    return $errors
}

export -f yaml_get yaml_to_json yaml_raw config_get build_tool_cmd
export -f print_header print_sep validate_seed
export BENCHMARK_DIR TOOLS_DIR SEEDS_DIR PENDING_DIR APPROVED_DIR REJECTED_DIR RESULTS_DIR CONFIG_FILE
