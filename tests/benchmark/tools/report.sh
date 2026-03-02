#!/usr/bin/env bash
# Human-friendly benchmark result reporter
#
# Usage: report.sh [--file results/2026-03-02-codex.json] [--format text|markdown]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

# Parse arguments
RESULT_FILE=""
FORMAT="text"

while [[ $# -gt 0 ]]; do
    case $1 in
        --file|-f)   RESULT_FILE="$2"; shift 2 ;;
        --format)    FORMAT="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [--file results/FILE.json] [--format text|markdown]"
            echo ""
            echo "Options:"
            echo "  --file, -f FILE      Result JSON file (default: latest in results/)"
            echo "  --format FORMAT      Output format: text|markdown (default: text)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Find latest result file if not specified
if [ -z "$RESULT_FILE" ]; then
    RESULT_FILE=$(find "$RESULTS_DIR" -name "*.json" -type f 2>/dev/null | sort -r | head -1)
    if [ -z "$RESULT_FILE" ]; then
        echo "沒有找到測試結果。請先執行 run.sh 或 benchmark.sh quickrun。"
        exit 1
    fi
fi

if [ ! -f "$RESULT_FILE" ]; then
    echo "ERROR: 檔案不存在: $RESULT_FILE" >&2
    exit 1
fi

FILENAME=$(basename "$RESULT_FILE")

# Extract metadata from results
TOOL=$(jq -r '.[0].tool // "unknown"' "$RESULT_FILE")
TIMESTAMP=$(jq -r '.[0].timestamp // "unknown"' "$RESULT_FILE" | cut -dT -f1)
TOTAL=$(jq 'length' "$RESULT_FILE")

if [ "$FORMAT" = "markdown" ]; then
    echo "# 測試報告：$FILENAME"
    echo ""
    echo "- **測試工具：** $TOOL"
    echo "- **測試時間：** $TIMESTAMP"
    echo "- **測試數量：** $TOTAL"
    echo ""
    echo "## 分類摘要"
    echo ""
    echo "| 類別 | 題數 | 得分 | 通過率 |"
    echo "|------|------|------|--------|"
    jq -r '
      group_by(.category) | sort_by(.[0].category) | .[] |
      (.[0].category) as $cat |
      (length) as $t |
      ([.[] | select(.score >= 0) | .score] | add // 0) as $s |
      ([.[] | .max_score] | add // 0) as $m |
      (if $m > 0 then (($s / $m * 100) | floor | tostring) + "%" else "N/A" end) as $rate |
      "| \($cat) | \($t) | \($s)/\($m) | \($rate) |"
    ' "$RESULT_FILE"
    echo ""
    echo "## 逐題結果"
    echo ""
    jq -r '
      .[] |
      "### [\(.score)/\(.max_score)] \(.id)\n" +
      "> \(.prompt | split("\n") | .[0][:70])\n\n" +
      "**評語：** \(.details.judge_reasoning // (.details | tostring) // "N/A")\n"
    ' "$RESULT_FILE"
else
    print_header "測試報告：$FILENAME"
    echo "  測試工具：$TOOL"
    echo "  測試時間：$TIMESTAMP"
    echo "  測試數量：$TOTAL"
    echo ""

    echo "分類摘要"
    print_sep
    printf "  %-20s %5s %10s %10s\n" "類別" "題數" "得分" "通過率"
    print_sep
    jq -r '
      group_by(.category) | sort_by(.[0].category) | .[] |
      (.[0].category) as $cat |
      (length) as $t |
      ([.[] | select(.score >= 0) | .score] | add // 0) as $s |
      ([.[] | .max_score] | add // 0) as $m |
      (if $m > 0 then (($s / $m * 100) | floor | tostring) + "%" else "N/A" end) as $rate |
      "  \($cat)|\($t)|\($s)/\($m)|\($rate)"
    ' "$RESULT_FILE" | while IFS='|' read -r cat t score rate; do
        printf "  %-20s %5s %10s %10s\n" "$cat" "$t" "$score" "$rate"
    done
    print_sep
    echo ""

    echo "逐題結果"
    print_sep
    jq -r '
      .[] |
      "  [\(.score)/\(.max_score)] \(.id)" +
      "\n        \(.prompt | split("\n") | .[0][:60])" +
      "\n        → \(.details.judge_reasoning // (.details | tostring) // "N/A" | split("\n") | .[0][:70])" +
      "\n"
    ' "$RESULT_FILE"
    print_sep

    # Overall summary
    TOTAL_SCORE=$(jq '[.[] | select(.score >= 0) | .score] | add // 0' "$RESULT_FILE")
    TOTAL_MAX=$(jq '[.[] | .max_score] | add // 0' "$RESULT_FILE")
    PASSED=$(jq '[.[] | select(.status == "passed")] | length' "$RESULT_FILE")
    ERRORS=$(jq '[.[] | select(.status == "error")] | length' "$RESULT_FILE")
    if [ "$TOTAL_MAX" -gt 0 ]; then
        RATE=$(python3 -c "print(f'{$TOTAL_SCORE/$TOTAL_MAX*100:.0f}%')")
    else
        RATE="N/A"
    fi
    echo ""
    echo "  總分：$TOTAL_SCORE/$TOTAL_MAX ($RATE)"
    echo "  通過：$PASSED  錯誤：$ERRORS"
    echo ""
fi
