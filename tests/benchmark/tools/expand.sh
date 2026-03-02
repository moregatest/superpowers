#!/usr/bin/env bash
# AI-powered seed expander
# Reads a seed YAML and generates N variants using an AI tool
#
# Usage: expand.sh <seed-file> [--count 10] [--tool claude] [--project-dir /path]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

# Parse arguments
SEED_FILE=""
COUNT=10
TOOL=""
PROJECT_DIR=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --count)   COUNT="$2"; shift 2 ;;
        --tool)    TOOL="$2"; shift 2 ;;
        --project-dir) PROJECT_DIR="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 <seed-file> [--count 10] [--tool claude] [--project-dir /path]"
            echo ""
            echo "Options:"
            echo "  --count N          Number of variants to generate (default: 10)"
            echo "  --tool TOOL        AI tool to use: claude|codex|opencode (default: from config)"
            echo "  --project-dir DIR  Project directory for tool execution context"
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *)
            SEED_FILE="$1"; shift ;;
    esac
done

if [ -z "$SEED_FILE" ]; then
    echo "ERROR: No seed file specified" >&2
    echo "Usage: $0 <seed-file> [--count 10] [--tool claude]" >&2
    exit 1
fi

if [ ! -f "$SEED_FILE" ]; then
    echo "ERROR: Seed file not found: $SEED_FILE" >&2
    exit 1
fi

# Defaults from config
TOOL="${TOOL:-$(config_get 'default_tool' 'claude')}"
PROJECT_DIR="${PROJECT_DIR:-.}"

# Validate seed
if ! validate_seed "$SEED_FILE"; then
    echo "ERROR: Seed validation failed" >&2
    exit 1
fi

# Read seed metadata
SEED_ID=$(yaml_get "$SEED_FILE" "id")
SEED_CATEGORY=$(yaml_get "$SEED_FILE" "category")
SEED_CONTENT=$(yaml_raw "$SEED_FILE")

print_header "Expanding Seed: $SEED_ID"
echo "Category: $SEED_CATEGORY"
echo "Tool: $TOOL"
echo "Count: $COUNT"
echo "Project dir: $PROJECT_DIR"

# Prepare output directory
OUTPUT_DIR="$PENDING_DIR/$SEED_CATEGORY"
mkdir -p "$OUTPUT_DIR"

# Build the expansion prompt
EXPAND_PROMPT="You are a test case generator for an AI model benchmark.

## Seed Case
\`\`\`yaml
$SEED_CONTENT
\`\`\`

## Task
Generate exactly $COUNT new test case variants based on the seed above and its expand_hints.

## Rules
- Output ONLY valid YAML documents separated by --- on its own line
- Keep the exact same YAML structure as the seed
- Increment the id counter from the seed id (e.g., bs-cd-001 -> bs-cd-002, bs-cd-003...)
- Each variant MUST differ substantially from the seed — not just word substitution
- Keep scoring method and rubric/rules structure consistent, but adapt content to match the new prompt
- Difficulty distribution: 40% easy to identify, 40% medium, 20% tricky (subtle, sounds plausible)
- Do NOT include any explanation or markdown formatting — output raw YAML only
- Each YAML document must be a complete, self-contained test case"

# Run AI tool to generate variants
echo ""
echo "Generating $COUNT variants..."
echo ""

TEMP_OUTPUT=$(mktemp)

case "$TOOL" in
    claude)
        claude -p "$EXPAND_PROMPT" \
            --permission-mode bypassPermissions \
            --add-dir "$PROJECT_DIR" \
            --cwd "$PROJECT_DIR" \
            > "$TEMP_OUTPUT" 2>/dev/null || true
        ;;
    codex)
        codex --prompt "$EXPAND_PROMPT" \
            --writable-root "$PROJECT_DIR" \
            --cwd "$PROJECT_DIR" \
            > "$TEMP_OUTPUT" 2>/dev/null || true
        ;;
    opencode)
        (cd "$PROJECT_DIR" && opencode run "$EXPAND_PROMPT") \
            > "$TEMP_OUTPUT" 2>/dev/null || true
        ;;
    *)
        echo "ERROR: Unknown tool: $TOOL" >&2
        rm -f "$TEMP_OUTPUT"
        exit 1
        ;;
esac

# Split multi-document YAML output into individual files
GENERATED=0
python3 -c "
import yaml
import sys
import os

output_dir = '$OUTPUT_DIR'
with open('$TEMP_OUTPUT') as f:
    content = f.read()

# Strip any markdown code fences the AI might have added
import re
content = re.sub(r'^\`\`\`ya?ml\s*\n', '', content, flags=re.MULTILINE)
content = re.sub(r'^\`\`\`\s*$', '', content, flags=re.MULTILINE)

docs = list(yaml.safe_load_all(content))
count = 0
for doc in docs:
    if doc is None:
        continue
    if 'id' not in doc:
        continue
    file_id = doc['id']
    out_path = os.path.join(output_dir, f'{file_id}.yaml')
    with open(out_path, 'w') as f:
        yaml.dump(doc, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
    count += 1
    print(f'  Created: {out_path}')
print(f'GENERATED={count}')
" 2>/dev/null | tee /dev/stderr | tail -1 | grep -o '[0-9]*' > /tmp/_expand_count || true

GENERATED=$(cat /tmp/_expand_count 2>/dev/null || echo "0")
rm -f "$TEMP_OUTPUT" /tmp/_expand_count

print_sep
echo "Generated: $GENERATED variants"
echo "Location: $OUTPUT_DIR/"
echo ""
echo "Next step: review with ./tools/review.sh --category $SEED_CATEGORY"
