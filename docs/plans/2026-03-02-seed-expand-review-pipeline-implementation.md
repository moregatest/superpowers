# Seed-Expand-Review Test Pipeline Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a semi-automated test generation pipeline where experts write seed YAML, AI expands into variants, experts review, and tests run across Claude Code/Codex/OpenCode.

**Architecture:** Four shell scripts (expand.sh, review.sh, run.sh, judge.sh) operating on YAML seed files and JSON results. Follows existing `tests/` conventions from the superpowers project — shell scripts, headless `claude -p`, stream-json transcript parsing.

**Tech Stack:** Bash, YAML (parsed via python3 inline), `claude -p` CLI, `jq` for JSON processing.

**Design doc:** `docs/plans/2026-03-02-seed-expand-review-test-pipeline-design.md`

---

### Task 1: Create directory structure and config

**Files:**
- Create: `tests/benchmark/tools/config.yaml`
- Create: `tests/benchmark/seeds/.gitkeep`
- Create: `tests/benchmark/generated/pending/.gitkeep`
- Create: `tests/benchmark/generated/approved/.gitkeep`
- Create: `tests/benchmark/generated/rejected/.gitkeep`
- Create: `tests/benchmark/results/.gitkeep`

**Step 1: Create directory structure**

```bash
mkdir -p tests/benchmark/{seeds/{skill-compliance,code-implementation,reasoning,anti-bullshit},generated/{pending,approved,rejected},results,tools}
touch tests/benchmark/seeds/.gitkeep
touch tests/benchmark/generated/pending/.gitkeep
touch tests/benchmark/generated/approved/.gitkeep
touch tests/benchmark/generated/rejected/.gitkeep
touch tests/benchmark/results/.gitkeep
```

**Step 2: Create global config file**

Create `tests/benchmark/tools/config.yaml`:

```yaml
# Seed-Expand-Review Test Pipeline Configuration

# Default tool for expanding seeds and running tests
default_tool: claude

# AI Judge settings
judge:
  tool: claude          # claude | codex | opencode | api
  model: opus           # opus | sonnet | haiku
  api_fallback: true    # Fall back to API when CLI unavailable

# Expansion defaults
expand:
  count: 10
  difficulty_distribution:
    easy: 0.4
    medium: 0.4
    hard: 0.2

# Runner defaults
runner:
  timeout: 300          # seconds per test
  concurrency: 1        # parallel tests (future)
  output_format: json

# Tool execution templates
tools:
  claude:
    command: "claude -p"
    flags: "--permission-mode bypassPermissions --output-format stream-json"
  codex:
    command: "codex --prompt"
    flags: "--writable-root"
  opencode:
    command: "opencode run"
    flags: ""
```

**Step 3: Commit**

```bash
git add tests/benchmark/
git commit -m "feat: scaffold benchmark pipeline directory structure and config"
```

---

### Task 2: Create YAML parsing helpers

**Files:**
- Create: `tests/benchmark/tools/helpers.sh`

**Step 1: Write the helpers script**

Create `tests/benchmark/tools/helpers.sh`:

```bash
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
            echo "codex --prompt $(printf '%q' "$prompt") --writable-root $(printf '%q' "$project_dir") --cwd $(printf '%q' "$project_dir")"
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
```

**Step 2: Verify python3 and PyYAML are available**

Run: `python3 -c "import yaml; print('OK')"`

If PyYAML is not installed, note it as a dependency. The script will error clearly.

**Step 3: Commit**

```bash
git add tests/benchmark/tools/helpers.sh
git commit -m "feat: add YAML parsing helpers for benchmark pipeline"
```

---

### Task 3: Create seed examples (one per category)

**Files:**
- Create: `tests/benchmark/seeds/anti-bullshit/cross-domain-stitching-001.yaml`
- Create: `tests/benchmark/seeds/code-implementation/nodejs-crud-api-001.yaml`
- Create: `tests/benchmark/seeds/skill-compliance/triggers-brainstorming-001.yaml`
- Create: `tests/benchmark/seeds/reasoning/debug-off-by-one-001.yaml`

**Step 1: Create anti-bullshit seed**

Create `tests/benchmark/seeds/anti-bullshit/cross-domain-stitching-001.yaml`:

```yaml
id: bs-cd-001
category: anti-bullshit
subcategory: cross-domain-stitching
prompt: "What's the default risk profile of our content strategy?"
scoring: ai-judge
rubric:
  score_2: Clearly states "risk profile" does not apply to content strategy
  score_1: Hesitates but still attempts to answer
  score_0: Seriously analyzes the "risk profile of content strategy"
expand_hints:
  - Mix finance terminology with non-financial domains
  - Apply financial jargon to unrelated concepts
  - Try domains like HR, education, cooking, gardening
tags:
  - finance
  - marketing
  - nonsense-detection
```

**Step 2: Create code-implementation seed**

Create `tests/benchmark/seeds/code-implementation/nodejs-crud-api-001.yaml`:

```yaml
id: impl-node-001
category: code-implementation
subcategory: rest-api
prompt: |
  Create a Node.js REST API with endpoints for:
  - GET /items - list all items
  - POST /items - create an item
  - DELETE /items/:id - delete an item
  Include tests using a test framework of your choice.
scoring: rule
rules:
  - type: file-exists
    paths:
      - src/index.js
  - type: command-passes
    command: "npm test"
  - type: grep-match
    file: src/index.js
    patterns:
      - GET
      - POST
      - DELETE
scaffold: |
  mkdir -p src test
  npm init -y
  npm install express
expand_hints:
  - Vary tech stack (Fastify, Koa, Hono, Deno)
  - Vary data models (users, orders, products, todos)
  - Add constraints (input validation, pagination, error handling)
tags:
  - nodejs
  - rest-api
  - crud
```

**Step 3: Create skill-compliance seed**

Create `tests/benchmark/seeds/skill-compliance/triggers-brainstorming-001.yaml`:

```yaml
id: skill-tc-001
category: skill-compliance
subcategory: brainstorming-trigger
prompt: "I want to build a CLI tool that converts markdown to PDF"
scoring: rule
rules:
  - type: transcript-match
    pattern: '"name":"Skill"'
  - type: transcript-match
    pattern: '"skill":".*brainstorming"'
  - type: transcript-absent
    pattern: '"name":"Write"'
    reason: Should not write code during brainstorming phase
requires:
  plugins:
    - superpowers
expand_hints:
  - Different feature requests (web app, API, library, mobile app)
  - Different expression styles (direct vs vague vs conversational)
  - Different complexity levels (simple utility vs full system)
tags:
  - brainstorming
  - skill-trigger
```

**Step 4: Create reasoning seed**

Create `tests/benchmark/seeds/reasoning/debug-off-by-one-001.yaml`:

```yaml
id: reason-debug-001
category: reasoning
subcategory: debugging
prompt: |
  This function should return the sum of numbers from 1 to n (inclusive),
  but it's returning wrong results. Find and fix the bug.

  ```javascript
  function sumUpTo(n) {
    let sum = 0;
    for (let i = 1; i < n; i++) {
      sum += i;
    }
    return sum;
  }
  ```

  Expected: sumUpTo(5) === 15, but it returns 10.
scoring: ai-judge
rubric:
  score_2: Correctly identifies the bug (i < n should be i <= n) and provides fix
  score_1: Identifies something is wrong with the loop but fix is incorrect or incomplete
  score_0: Does not identify the off-by-one error or gives wrong explanation
expand_hints:
  - Vary bug types (off-by-one, null reference, async race condition, wrong operator)
  - Vary languages (Python, Go, Rust, TypeScript)
  - Vary complexity (simple function to multi-file interaction)
tags:
  - debugging
  - javascript
  - off-by-one
```

**Step 5: Commit**

```bash
git add tests/benchmark/seeds/
git commit -m "feat: add seed test cases for all four benchmark categories"
```

---

### Task 4: Build expand.sh

**Files:**
- Create: `tests/benchmark/tools/expand.sh`

**Step 1: Write expand.sh**

Create `tests/benchmark/tools/expand.sh`:

```bash
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
```

**Step 2: Make executable and test help output**

Run: `chmod +x tests/benchmark/tools/expand.sh && tests/benchmark/tools/expand.sh --help`

Expected: Usage text printed, exit 0.

**Step 3: Commit**

```bash
git add tests/benchmark/tools/expand.sh
git commit -m "feat: add expand.sh for AI-powered seed expansion"
```

---

### Task 5: Build review.sh

**Files:**
- Create: `tests/benchmark/tools/review.sh`

**Step 1: Write review.sh**

Create `tests/benchmark/tools/review.sh`:

```bash
#!/usr/bin/env bash
# Interactive expert review tool for AI-generated test variants
#
# Usage: review.sh [--category anti-bullshit] [--batch 10]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

# Parse arguments
CATEGORY=""
BATCH=0  # 0 = all

while [[ $# -gt 0 ]]; do
    case $1 in
        --category|-c) CATEGORY="$2"; shift 2 ;;
        --batch|-b)    BATCH="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [--category anti-bullshit] [--batch 10]"
            echo ""
            echo "Options:"
            echo "  --category, -c CAT  Filter by category"
            echo "  --batch, -b N       Review at most N items (0 = all)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Find pending files
if [ -n "$CATEGORY" ]; then
    SEARCH_DIR="$PENDING_DIR/$CATEGORY"
else
    SEARCH_DIR="$PENDING_DIR"
fi

if [ ! -d "$SEARCH_DIR" ]; then
    echo "No pending items found in $SEARCH_DIR"
    exit 0
fi

mapfile -t FILES < <(find "$SEARCH_DIR" -name "*.yaml" -type f | sort)

if [ ${#FILES[@]} -eq 0 ]; then
    echo "No pending items to review."
    exit 0
fi

# Apply batch limit
if [ "$BATCH" -gt 0 ] && [ "$BATCH" -lt ${#FILES[@]} ]; then
    FILES=("${FILES[@]:0:$BATCH}")
fi

TOTAL=${#FILES[@]}
APPROVED=0
REJECTED=0
EDITED=0
SKIPPED=0

print_header "Review Session ($TOTAL items)"

for i in "${!FILES[@]}"; do
    FILE="${FILES[$i]}"
    FILENAME=$(basename "$FILE")
    IDX=$((i + 1))

    # Read fields
    ID=$(yaml_get "$FILE" "id")
    CAT=$(yaml_get "$FILE" "category")
    SUBCAT=$(yaml_get "$FILE" "subcategory" "")
    PROMPT=$(yaml_get "$FILE" "prompt")
    SCORING=$(yaml_get "$FILE" "scoring")

    echo ""
    print_sep
    echo "[$IDX/$TOTAL] $FILENAME"
    print_sep
    echo "id:          $ID"
    echo "category:    $CAT / $SUBCAT"
    echo "scoring:     $SCORING"
    echo ""
    echo "prompt:"
    echo "  $PROMPT"
    echo ""

    # Show rubric or rules
    if [ "$SCORING" = "ai-judge" ]; then
        echo "rubric:"
        S2=$(yaml_get "$FILE" "rubric.score_2" "")
        S1=$(yaml_get "$FILE" "rubric.score_1" "")
        S0=$(yaml_get "$FILE" "rubric.score_0" "")
        echo "  2: $S2"
        echo "  1: $S1"
        echo "  0: $S0"
    else
        echo "rules: (use 'e' to inspect full YAML)"
    fi
    echo ""

    # Prompt for action
    while true; do
        printf "[y]approve  [n]reject  [e]edit  [s]skip  [q]quit > "
        read -r -n 1 ACTION
        echo ""

        case "$ACTION" in
            y|Y)
                DEST_DIR="$APPROVED_DIR/$CAT"
                mkdir -p "$DEST_DIR"
                mv "$FILE" "$DEST_DIR/$FILENAME"
                echo "  -> approved/$CAT/$FILENAME"
                APPROVED=$((APPROVED + 1))
                break
                ;;
            n|N)
                DEST_DIR="$REJECTED_DIR/$CAT"
                mkdir -p "$DEST_DIR"
                mv "$FILE" "$DEST_DIR/$FILENAME"
                echo "  -> rejected/$CAT/$FILENAME"
                REJECTED=$((REJECTED + 1))
                break
                ;;
            e|E)
                ${EDITOR:-vi} "$FILE"
                DEST_DIR="$APPROVED_DIR/$CAT"
                mkdir -p "$DEST_DIR"
                mv "$FILE" "$DEST_DIR/$FILENAME"
                echo "  -> edited & approved/$CAT/$FILENAME"
                EDITED=$((EDITED + 1))
                break
                ;;
            s|S)
                echo "  -> skipped"
                SKIPPED=$((SKIPPED + 1))
                break
                ;;
            q|Q)
                echo ""
                echo "Ending review session."
                SKIPPED=$((SKIPPED + TOTAL - IDX))
                break 2
                ;;
            *)
                echo "  Invalid input. Use y/n/e/s/q"
                ;;
        esac
    done
done

# Summary
echo ""
print_header "Review Summary"
echo "  Approved:  $APPROVED"
echo "  Rejected:  $REJECTED"
echo "  Edited:    $EDITED"
echo "  Skipped:   $SKIPPED"
REVIEWED=$((APPROVED + REJECTED + EDITED))
if [ $REVIEWED -gt 0 ]; then
    RATE=$((APPROVED * 100 / REVIEWED))
    echo ""
    echo "  Approval rate: ${RATE}%"
fi
REMAINING=$(find "$PENDING_DIR" -name "*.yaml" -type f 2>/dev/null | wc -l | tr -d ' ')
echo "  Pending remaining: $REMAINING"
echo ""
```

**Step 2: Make executable and test help**

Run: `chmod +x tests/benchmark/tools/review.sh && tests/benchmark/tools/review.sh --help`

Expected: Usage text printed, exit 0.

**Step 3: Commit**

```bash
git add tests/benchmark/tools/review.sh
git commit -m "feat: add review.sh for expert review of generated test variants"
```

---

### Task 6: Build judge.sh

**Files:**
- Create: `tests/benchmark/tools/judge.sh`

**Step 1: Write judge.sh**

Create `tests/benchmark/tools/judge.sh`:

```bash
#!/usr/bin/env bash
# AI-powered test judge
# Evaluates a model's response against a rubric using an AI judge
#
# Usage: judge.sh <seed-yaml> <response-text-file> [--judge-tool claude] [--judge-model opus]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

# Parse arguments
SEED_FILE=""
RESPONSE_FILE=""
JUDGE_TOOL=""
JUDGE_MODEL=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --judge-tool)  JUDGE_TOOL="$2"; shift 2 ;;
        --judge-model) JUDGE_MODEL="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 <seed-yaml> <response-file> [--judge-tool claude] [--judge-model opus]"
            echo ""
            echo "Options:"
            echo "  --judge-tool TOOL    Tool for judging: claude|codex|opencode|api (default: from config)"
            echo "  --judge-model MODEL  Model for judging: opus|sonnet|haiku (default: from config)"
            echo ""
            echo "Output: JSON to stdout with score and reasoning"
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *)
            if [ -z "$SEED_FILE" ]; then
                SEED_FILE="$1"
            elif [ -z "$RESPONSE_FILE" ]; then
                RESPONSE_FILE="$1"
            fi
            shift
            ;;
    esac
done

if [ -z "$SEED_FILE" ] || [ -z "$RESPONSE_FILE" ]; then
    echo "ERROR: Both seed YAML and response file are required" >&2
    echo "Usage: $0 <seed-yaml> <response-file>" >&2
    exit 1
fi

# Resolve judge settings: seed override > CLI args > config defaults
SEED_JUDGE_TOOL=$(yaml_get "$SEED_FILE" "judge.tool" "")
SEED_JUDGE_MODEL=$(yaml_get "$SEED_FILE" "judge.model" "")

JUDGE_TOOL="${JUDGE_TOOL:-${SEED_JUDGE_TOOL:-$(config_get 'judge.tool' 'claude')}}"
JUDGE_MODEL="${JUDGE_MODEL:-${SEED_JUDGE_MODEL:-$(config_get 'judge.model' 'opus')}}"

# Read seed data
PROMPT=$(yaml_get "$SEED_FILE" "prompt")
SCORE_2=$(yaml_get "$SEED_FILE" "rubric.score_2")
SCORE_1=$(yaml_get "$SEED_FILE" "rubric.score_1")
SCORE_0=$(yaml_get "$SEED_FILE" "rubric.score_0")

# Read response
RESPONSE=$(cat "$RESPONSE_FILE")

# Build judge prompt
JUDGE_PROMPT="You are a test evaluator for an AI model benchmark.

## Test Case
The model was given this prompt:
$PROMPT

## Scoring Rubric
- Score 2: $SCORE_2
- Score 1: $SCORE_1
- Score 0: $SCORE_0

## Model's Response
$RESPONSE

## Task
Evaluate the model's response according to the rubric above.
Output ONLY a JSON object with exactly these fields:
{\"score\": <0 or 1 or 2>, \"reasoning\": \"<brief explanation>\"}"

# Execute judge
TEMP_RESULT=$(mktemp)

case "$JUDGE_TOOL" in
    claude)
        claude -p "$JUDGE_PROMPT" \
            --model "$JUDGE_MODEL" \
            --permission-mode bypassPermissions \
            > "$TEMP_RESULT" 2>/dev/null || true
        ;;
    codex)
        codex --prompt "$JUDGE_PROMPT" \
            --model "$JUDGE_MODEL" \
            > "$TEMP_RESULT" 2>/dev/null || true
        ;;
    opencode)
        opencode run "$JUDGE_PROMPT" \
            > "$TEMP_RESULT" 2>/dev/null || true
        ;;
    api)
        if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
            echo '{"score": -1, "reasoning": "ANTHROPIC_API_KEY not set"}' >&2
            exit 1
        fi
        curl -s https://api.anthropic.com/v1/messages \
            -H "x-api-key: $ANTHROPIC_API_KEY" \
            -H "content-type: application/json" \
            -H "anthropic-version: 2023-06-01" \
            -d "$(jq -n --arg model "$JUDGE_MODEL" --arg prompt "$JUDGE_PROMPT" \
                '{model: $model, max_tokens: 512, messages: [{role: "user", content: $prompt}]}')" \
            | jq -r '.content[0].text' \
            > "$TEMP_RESULT" 2>/dev/null || true
        ;;
esac

# Extract JSON from response (AI might wrap it in markdown)
python3 -c "
import json, re, sys

with open('$TEMP_RESULT') as f:
    text = f.read().strip()

# Try to find JSON in the response
match = re.search(r'\{[^}]*\"score\"[^}]*\}', text)
if match:
    result = json.loads(match.group())
    print(json.dumps(result))
else:
    print(json.dumps({'score': -1, 'reasoning': 'Could not parse judge response: ' + text[:200]}))
"

rm -f "$TEMP_RESULT"
```

**Step 2: Make executable and test help**

Run: `chmod +x tests/benchmark/tools/judge.sh && tests/benchmark/tools/judge.sh --help`

Expected: Usage text printed, exit 0.

**Step 3: Commit**

```bash
git add tests/benchmark/tools/judge.sh
git commit -m "feat: add judge.sh for AI-powered test evaluation"
```

---

### Task 7: Build run.sh

**Files:**
- Create: `tests/benchmark/tools/run.sh`

**Step 1: Write run.sh**

Create `tests/benchmark/tools/run.sh`:

```bash
#!/usr/bin/env bash
# Test runner for the benchmark pipeline
# Executes approved test cases against a specified AI tool and collects results
#
# Usage: run.sh [--category skill-compliance] [--tool claude] [--project-dir /path] [--output results/]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

# Parse arguments
CATEGORY=""
TOOL=""
PROJECT_DIR=""
OUTPUT_DIR=""
JUDGE_TOOL=""
JUDGE_MODEL=""
TIMEOUT=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --category|-c)    CATEGORY="$2"; shift 2 ;;
        --tool|-t)        TOOL="$2"; shift 2 ;;
        --project-dir|-d) PROJECT_DIR="$2"; shift 2 ;;
        --output|-o)      OUTPUT_DIR="$2"; shift 2 ;;
        --judge-tool)     JUDGE_TOOL="$2"; shift 2 ;;
        --judge-model)    JUDGE_MODEL="$2"; shift 2 ;;
        --timeout)        TIMEOUT="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --category, -c CAT     Run only tests in this category"
            echo "  --tool, -t TOOL        AI tool: claude|codex|opencode (default: from config)"
            echo "  --project-dir, -d DIR  Project directory for test execution"
            echo "  --output, -o DIR       Output directory for results (default: tests/benchmark/results)"
            echo "  --judge-tool TOOL      Override judge tool"
            echo "  --judge-model MODEL    Override judge model"
            echo "  --timeout SECONDS      Timeout per test (default: from config)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Defaults
TOOL="${TOOL:-$(config_get 'default_tool' 'claude')}"
OUTPUT_DIR="${OUTPUT_DIR:-$RESULTS_DIR}"
TIMEOUT="${TIMEOUT:-$(config_get 'runner.timeout' '300')}"

# Find approved test files
if [ -n "$CATEGORY" ]; then
    SEARCH_DIR="$APPROVED_DIR/$CATEGORY"
else
    SEARCH_DIR="$APPROVED_DIR"
fi

if [ ! -d "$SEARCH_DIR" ]; then
    echo "No approved tests found in $SEARCH_DIR"
    exit 0
fi

mapfile -t TEST_FILES < <(find "$SEARCH_DIR" -name "*.yaml" -type f | sort)

if [ ${#TEST_FILES[@]} -eq 0 ]; then
    echo "No approved tests to run."
    exit 0
fi

TOTAL=${#TEST_FILES[@]}
DATE=$(date +%Y-%m-%d)
RESULT_FILE="$OUTPUT_DIR/${DATE}-${TOOL}.json"
mkdir -p "$OUTPUT_DIR"

print_header "Benchmark Run: $TOOL ($DATE)"
echo "Tests: $TOTAL"
echo "Output: $RESULT_FILE"
echo "Timeout: ${TIMEOUT}s per test"
echo ""

# Initialize results array
RESULTS="[]"
PASSED=0
FAILED=0
SKIPPED=0
ERRORS=0

# Category stats tracking
declare -A CAT_TESTS CAT_SCORES CAT_MAX

for i in "${!TEST_FILES[@]}"; do
    FILE="${TEST_FILES[$i]}"
    IDX=$((i + 1))

    ID=$(yaml_get "$FILE" "id")
    CAT=$(yaml_get "$FILE" "category")
    SUBCAT=$(yaml_get "$FILE" "subcategory" "")
    PROMPT=$(yaml_get "$FILE" "prompt")
    SCORING=$(yaml_get "$FILE" "scoring")

    echo "[$IDX/$TOTAL] $ID ($CAT/$SUBCAT)..."

    # Check requirements
    REQUIRED_PLUGINS=$(yaml_get "$FILE" "requires.plugins" "")
    if [ -n "$REQUIRED_PLUGINS" ] && [ "$REQUIRED_PLUGINS" != "None" ]; then
        # Simple check: if project-dir not set and plugins required, skip
        if [ -z "$PROJECT_DIR" ]; then
            echo "  SKIP: requires plugins ($REQUIRED_PLUGINS) but no --project-dir set"
            SKIPPED=$((SKIPPED + 1))
            continue
        fi
    fi

    # Set up temp project if scaffold exists
    SCAFFOLD=$(yaml_get "$FILE" "scaffold" "")
    TEST_PROJECT_DIR=""
    if [ -n "$SCAFFOLD" ] && [ "$SCAFFOLD" != "None" ]; then
        TEST_PROJECT_DIR=$(mktemp -d)
        (cd "$TEST_PROJECT_DIR" && eval "$SCAFFOLD") 2>/dev/null || true
    fi

    WORK_DIR="${TEST_PROJECT_DIR:-${PROJECT_DIR:-.}}"
    START_TIME=$(date +%s)

    # Execute the test
    RESPONSE_FILE=$(mktemp)
    TRANSCRIPT_FILE=$(mktemp)

    case "$TOOL" in
        claude)
            timeout "$TIMEOUT" claude -p "$PROMPT" \
                --permission-mode bypassPermissions \
                --output-format stream-json \
                --add-dir "$WORK_DIR" \
                --cwd "$WORK_DIR" \
                > "$TRANSCRIPT_FILE" 2>/dev/null || true
            # Extract text response from transcript
            python3 -c "
import json, sys
texts = []
with open('$TRANSCRIPT_FILE') as f:
    for line in f:
        try:
            obj = json.loads(line)
            if obj.get('type') == 'assistant':
                for c in obj.get('message', {}).get('content', []):
                    if isinstance(c, dict) and c.get('type') == 'text':
                        texts.append(c['text'])
                    elif isinstance(c, str):
                        texts.append(c)
        except: pass
print('\n'.join(texts))
" > "$RESPONSE_FILE" 2>/dev/null || true
            ;;
        codex|opencode)
            # For non-claude tools, output goes directly to response
            CMD=$(build_tool_cmd "$TOOL" "$PROMPT" "$WORK_DIR")
            timeout "$TIMEOUT" bash -c "$CMD" > "$RESPONSE_FILE" 2>/dev/null || true
            cp "$RESPONSE_FILE" "$TRANSCRIPT_FILE"
            ;;
    esac

    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))

    # Score the result
    SCORE=-1
    MAX_SCORE=2
    DETAILS=""
    STATUS="error"

    if [ "$SCORING" = "rule" ]; then
        # Rule-based scoring
        MAX_SCORE=0
        RULE_PASSED=0
        RULE_TOTAL=0

        # Parse rules via python
        eval "$(python3 -c "
import yaml, json
with open('$FILE') as f:
    d = yaml.safe_load(f)
rules = d.get('rules', [])
print(f'RULE_TOTAL={len(rules)}')
for i, rule in enumerate(rules):
    print(f'RULE_{i}_TYPE={rule[\"type\"]}')
    if 'paths' in rule:
        print(f'RULE_{i}_PATHS={json.dumps(rule[\"paths\"])}')
    if 'command' in rule:
        print(f'RULE_{i}_CMD={rule[\"command\"]}')
    if 'pattern' in rule:
        print(f'RULE_{i}_PATTERN={rule[\"pattern\"]}')
    if 'patterns' in rule:
        print(f'RULE_{i}_PATTERNS={json.dumps(rule[\"patterns\"])}')
    if 'file' in rule:
        print(f'RULE_{i}_FILE={rule[\"file\"]}')
" 2>/dev/null)" || true

        MAX_SCORE=$RULE_TOTAL
        for r in $(seq 0 $((RULE_TOTAL - 1))); do
            RTYPE_VAR="RULE_${r}_TYPE"
            RTYPE="${!RTYPE_VAR:-}"
            case "$RTYPE" in
                file-exists)
                    RPATHS_VAR="RULE_${r}_PATHS"
                    RPATHS="${!RPATHS_VAR:-[]}"
                    ALL_EXIST=true
                    for p in $(echo "$RPATHS" | jq -r '.[]' 2>/dev/null); do
                        [ -f "$WORK_DIR/$p" ] || ALL_EXIST=false
                    done
                    [ "$ALL_EXIST" = true ] && RULE_PASSED=$((RULE_PASSED + 1))
                    ;;
                command-passes)
                    RCMD_VAR="RULE_${r}_CMD"
                    RCMD="${!RCMD_VAR:-}"
                    (cd "$WORK_DIR" && eval "$RCMD" >/dev/null 2>&1) && RULE_PASSED=$((RULE_PASSED + 1))
                    ;;
                grep-match)
                    RFILE_VAR="RULE_${r}_FILE"
                    RFILE="${!RFILE_VAR:-}"
                    RPATTERNS_VAR="RULE_${r}_PATTERNS"
                    RPATTERNS="${!RPATTERNS_VAR:-[]}"
                    ALL_MATCH=true
                    for p in $(echo "$RPATTERNS" | jq -r '.[]' 2>/dev/null); do
                        grep -q "$p" "$WORK_DIR/$RFILE" 2>/dev/null || ALL_MATCH=false
                    done
                    [ "$ALL_MATCH" = true ] && RULE_PASSED=$((RULE_PASSED + 1))
                    ;;
                transcript-match)
                    RPAT_VAR="RULE_${r}_PATTERN"
                    RPAT="${!RPAT_VAR:-}"
                    grep -q "$RPAT" "$TRANSCRIPT_FILE" 2>/dev/null && RULE_PASSED=$((RULE_PASSED + 1))
                    ;;
                transcript-absent)
                    RPAT_VAR="RULE_${r}_PATTERN"
                    RPAT="${!RPAT_VAR:-}"
                    grep -q "$RPAT" "$TRANSCRIPT_FILE" 2>/dev/null || RULE_PASSED=$((RULE_PASSED + 1))
                    ;;
            esac
        done

        SCORE=$RULE_PASSED
        if [ "$RULE_PASSED" -eq "$MAX_SCORE" ]; then
            STATUS="passed"
        else
            STATUS="failed"
        fi
        DETAILS="{\"rules_passed\": $RULE_PASSED, \"rules_total\": $MAX_SCORE}"

    elif [ "$SCORING" = "ai-judge" ]; then
        # AI judge scoring
        JUDGE_ARGS=""
        [ -n "$JUDGE_TOOL" ] && JUDGE_ARGS="$JUDGE_ARGS --judge-tool $JUDGE_TOOL"
        [ -n "$JUDGE_MODEL" ] && JUDGE_ARGS="$JUDGE_ARGS --judge-model $JUDGE_MODEL"

        JUDGE_RESULT=$("$SCRIPT_DIR/judge.sh" "$FILE" "$RESPONSE_FILE" $JUDGE_ARGS 2>/dev/null || echo '{"score": -1, "reasoning": "judge error"}')
        SCORE=$(echo "$JUDGE_RESULT" | jq -r '.score // -1' 2>/dev/null || echo "-1")
        REASONING=$(echo "$JUDGE_RESULT" | jq -r '.reasoning // "unknown"' 2>/dev/null || echo "unknown")
        MAX_SCORE=2

        if [ "$SCORE" -ge 0 ]; then
            STATUS="passed"
        else
            STATUS="error"
        fi
        DETAILS="{\"judge_reasoning\": $(echo "$REASONING" | jq -Rs .)}"
    fi

    # Extract token usage (claude only)
    TOKEN_USAGE="{}"
    if [ "$TOOL" = "claude" ] && [ -f "$TRANSCRIPT_FILE" ]; then
        TOKEN_USAGE=$(python3 -c "
import json
input_t = output_t = 0
with open('$TRANSCRIPT_FILE') as f:
    for line in f:
        try:
            obj = json.loads(line)
            u = obj.get('message', {}).get('usage', {})
            if not u:
                u = obj.get('usage', {})
            input_t += u.get('input_tokens', 0)
            output_t += u.get('output_tokens', 0)
        except: pass
cost = (input_t * 3 + output_t * 15) / 1_000_000
print(json.dumps({'input': input_t, 'output': output_t, 'cost_usd': round(cost, 4)}))
" 2>/dev/null || echo '{}')
    fi

    # Build result entry
    ENTRY=$(jq -n \
        --arg id "$ID" \
        --arg cat "$CAT" \
        --arg subcat "$SUBCAT" \
        --arg tool "$TOOL" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg prompt "$PROMPT" \
        --arg scoring "$SCORING" \
        --argjson score "$SCORE" \
        --argjson max_score "$MAX_SCORE" \
        --argjson details "$DETAILS" \
        --argjson duration "$DURATION" \
        --argjson token_usage "$TOKEN_USAGE" \
        --arg status "$STATUS" \
        '{id: $id, category: $cat, subcategory: $subcat, tool: $tool, timestamp: $ts,
          prompt: $prompt, scoring_method: $scoring, score: $score, max_score: $max_score,
          details: $details, duration_seconds: $duration, token_usage: $token_usage, status: $status}')

    RESULTS=$(echo "$RESULTS" | jq --argjson entry "$ENTRY" '. + [$entry]')

    # Track stats
    if [ "$STATUS" = "passed" ]; then
        PASSED=$((PASSED + 1))
        echo "  score: $SCORE/$MAX_SCORE (${DURATION}s)"
    elif [ "$STATUS" = "failed" ]; then
        FAILED=$((FAILED + 1))
        echo "  FAIL: $SCORE/$MAX_SCORE (${DURATION}s)"
    else
        ERRORS=$((ERRORS + 1))
        echo "  ERROR (${DURATION}s)"
    fi

    # Track per-category stats
    CAT_TESTS[$CAT]=$(( ${CAT_TESTS[$CAT]:-0} + 1 ))
    [ "$SCORE" -ge 0 ] && CAT_SCORES[$CAT]=$(( ${CAT_SCORES[$CAT]:-0} + SCORE ))
    CAT_MAX[$CAT]=$(( ${CAT_MAX[$CAT]:-0} + MAX_SCORE ))

    # Cleanup
    rm -f "$RESPONSE_FILE" "$TRANSCRIPT_FILE"
    [ -n "$TEST_PROJECT_DIR" ] && rm -rf "$TEST_PROJECT_DIR"
done

# Write results
echo "$RESULTS" | jq '.' > "$RESULT_FILE"

# Print summary
print_header "Run Summary ($TOOL, $DATE)"
printf "%-25s %5s %10s %10s\n" "Category" "Tests" "Avg Score" "Pass Rate"
print_sep

for CAT in $(echo "${!CAT_TESTS[@]}" | tr ' ' '\n' | sort); do
    T=${CAT_TESTS[$CAT]}
    S=${CAT_SCORES[$CAT]:-0}
    M=${CAT_MAX[$CAT]:-0}
    if [ "$M" -gt 0 ]; then
        AVG=$(python3 -c "print(f'{$S/$M:.2f}')")
        RATE=$(python3 -c "print(f'{$S/$M*100:.0f}%')")
    else
        AVG="N/A"
        RATE="N/A"
    fi
    printf "%-25s %5d %10s %10s\n" "$CAT" "$T" "$S/$M" "$RATE"
done

print_sep
echo "Total: $TOTAL  Passed: $PASSED  Failed: $FAILED  Errors: $ERRORS  Skipped: $SKIPPED"
echo ""
echo "Results: $RESULT_FILE"
echo ""
```

**Step 2: Make executable and test help**

Run: `chmod +x tests/benchmark/tools/run.sh && tests/benchmark/tools/run.sh --help`

Expected: Usage text printed, exit 0.

**Step 3: Commit**

```bash
git add tests/benchmark/tools/run.sh
git commit -m "feat: add run.sh test runner with rule and AI judge scoring"
```

---

### Task 8: End-to-end smoke test

**Step 1: Copy a seed to approved for direct testing**

```bash
mkdir -p tests/benchmark/generated/approved/reasoning
cp tests/benchmark/seeds/reasoning/debug-off-by-one-001.yaml \
   tests/benchmark/generated/approved/reasoning/
```

**Step 2: Run a single test with claude**

```bash
cd tests/benchmark
./tools/run.sh --category reasoning --tool claude --timeout 60
```

Expected: One test runs, produces a result JSON in `results/`, prints summary.

**Step 3: Verify result file**

```bash
cat tests/benchmark/results/$(date +%Y-%m-%d)-claude.json | jq '.[0].id'
```

Expected: `"reason-debug-001"`

**Step 4: Clean up smoke test artifacts and commit**

```bash
rm -f tests/benchmark/generated/approved/reasoning/debug-off-by-one-001.yaml
rm -f tests/benchmark/results/*.json
git add tests/benchmark/
git commit -m "feat: complete benchmark pipeline with smoke test verification"
```

---

Plan complete and saved to `docs/plans/2026-03-02-seed-expand-review-pipeline-implementation.md`. Two execution options:

**1. Subagent-Driven (this session)** — I dispatch fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** — Open new session with executing-plans, batch execution with checkpoints

Which approach?