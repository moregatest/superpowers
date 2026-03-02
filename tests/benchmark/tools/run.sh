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
