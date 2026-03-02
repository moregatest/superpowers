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
        codex exec "$JUDGE_PROMPT" \
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
