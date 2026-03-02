# Benchmark Interactive CLI Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build an interactive CLI wrapper (`benchmark.sh`) and report generator (`report.sh`) that make the benchmark pipeline easy to use for newcomers and power users alike.

**Architecture:** A single entry point `benchmark.sh` routes to existing tools via subcommands or an interactive menu. A new `report.sh` reads JSON results and renders human-friendly summaries. No changes to existing scripts.

**Tech Stack:** Bash (3.2 compatible — no `mapfile`, no `declare -A`), `jq`, `python3`.

**Design doc:** `docs/plans/2026-03-02-benchmark-interactive-cli-design.md`

---

### Task 1: Create report.sh

**Files:**
- Create: `tests/benchmark/tools/report.sh`

**Step 1: Write report.sh**

Create `tests/benchmark/tools/report.sh`:

```bash
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
```

**Step 2: Make executable and test help**

Run: `chmod +x tests/benchmark/tools/report.sh && tests/benchmark/tools/report.sh --help`

Expected: Usage text printed, exit 0.

**Step 3: Test with existing result file**

Run: `cd tests/benchmark && ./tools/report.sh`

Expected: Human-friendly Chinese report printed from latest result.

**Step 4: Commit**

```bash
git add tests/benchmark/tools/report.sh
git commit -m "feat: add report.sh for human-friendly benchmark results"
```

---

### Task 2: Create benchmark.sh interactive menu helpers

**Files:**
- Create: `tests/benchmark/benchmark.sh`

**Step 1: Write benchmark.sh with menu and subcommand routing**

Create `tests/benchmark/benchmark.sh`:

```bash
#!/usr/bin/env bash
# Benchmark Pipeline — 互動式入口
#
# Usage:
#   ./benchmark.sh                        # 互動模式
#   ./benchmark.sh expand [options]       # 擴展種子
#   ./benchmark.sh review [options]       # 審核變體
#   ./benchmark.sh run [options]          # 執行測試
#   ./benchmark.sh report [options]       # 查看報告
#   ./benchmark.sh quickrun [options]     # 一鍵測試

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="$SCRIPT_DIR/tools"
source "$TOOLS_DIR/helpers.sh"

# ─── Interactive helpers ────────────────────────

# Pick from a numbered list
# Usage: pick_one "prompt" item1 item2 ...
# Returns: chosen item via stdout
pick_one() {
    local prompt="$1"; shift
    local items=("$@")

    echo "" >&2
    for i in "${!items[@]}"; do
        echo "  $((i + 1))) ${items[$i]}" >&2
    done
    echo "" >&2

    while true; do
        printf "$prompt " >&2
        read -r choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#items[@]} ]; then
            echo "${items[$((choice - 1))]}"
            return
        fi
        echo "  請輸入 1-${#items[@]}" >&2
    done
}

# Ask yes/no with default
# Usage: ask_yn "prompt" [y|n]
ask_yn() {
    local prompt="$1"
    local default="${2:-y}"
    local hint="Y/n"
    [ "$default" = "n" ] && hint="y/N"

    printf "$prompt [$hint] " >&2
    read -r answer
    answer="${answer:-$default}"
    [[ "$answer" =~ ^[Yy] ]]
}

# Ask for a value with default
# Usage: ask_value "prompt" "default"
ask_value() {
    local prompt="$1"
    local default="$2"
    printf "$prompt [預設 $default]: " >&2
    read -r value
    echo "${value:-$default}"
}

# List available categories from seeds directory
list_categories() {
    find "$SEEDS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | while read -r d; do
        basename "$d"
    done | sort
}

# List seed files in a category
list_seeds() {
    local cat="$1"
    find "$SEEDS_DIR/$cat" -name "*.yaml" -type f 2>/dev/null | while read -r f; do
        basename "$f" .yaml
    done | sort
}

# List available tools
list_tools() {
    echo "codex"
    echo "claude"
    echo "opencode"
}

# ─── Subcommands ────────────────────────────────

do_expand_interactive() {
    echo ""
    echo "擴展種子"
    print_sep

    local cats
    cats=($(list_categories))
    local cat
    cat=$(pick_one "選擇類別 >" "${cats[@]}")

    local seeds
    seeds=($(list_seeds "$cat"))
    local seed
    seed=$(pick_one "選擇 seed >" "${seeds[@]}")

    local count
    count=$(ask_value "生成數量" "5")

    local tools
    tools=($(list_tools))
    local tool
    tool=$(pick_one "選擇工具 >" "${tools[@]}")

    echo ""
    "$TOOLS_DIR/expand.sh" "$SEEDS_DIR/$cat/${seed}.yaml" --count "$count" --tool "$tool"

    echo ""
    if ask_yn "要審核生成的變體嗎？"; then
        do_review_interactive "$cat"
    fi
}

do_review_interactive() {
    local cat="${1:-}"
    if [ -z "$cat" ]; then
        echo ""
        echo "審核變體"
        print_sep

        local pending_cats
        pending_cats=($(find "$PENDING_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | while read -r d; do basename "$d"; done | sort))

        if [ ${#pending_cats[@]} -eq 0 ]; then
            echo "沒有待審核的變體。"
            return
        fi

        cat=$(pick_one "選擇類別 >" "${pending_cats[@]}")
    fi

    "$TOOLS_DIR/review.sh" --category "$cat"

    echo ""
    if ask_yn "要執行測試嗎？"; then
        do_run_interactive
    fi
}

do_run_interactive() {
    echo ""
    echo "執行測試"
    print_sep

    local approved_cats
    approved_cats=($(find "$APPROVED_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | while read -r d; do basename "$d"; done | sort))

    if [ ${#approved_cats[@]} -eq 0 ]; then
        echo "沒有已核准的測試案例。"
        return
    fi

    # Add "all" option
    local choices=("全部" "${approved_cats[@]}")
    local cat
    cat=$(pick_one "選擇類別 >" "${choices[@]}")

    local cat_flag=""
    [ "$cat" != "全部" ] && cat_flag="--category $cat"

    local tools
    tools=($(list_tools))
    local tool
    tool=$(pick_one "選擇工具 >" "${tools[@]}")

    local timeout
    timeout=$(ask_value "Timeout (秒)" "120")

    echo ""
    "$TOOLS_DIR/run.sh" $cat_flag --tool "$tool" --judge-tool "$tool" --timeout "$timeout"

    echo ""
    if ask_yn "要查看報告嗎？"; then
        "$TOOLS_DIR/report.sh"
    fi
}

do_report() {
    "$TOOLS_DIR/report.sh" "$@"
}

do_quickrun_interactive() {
    echo ""
    echo "快速測試"
    print_sep

    local cats
    cats=($(list_categories))
    local cat
    cat=$(pick_one "選擇類別 >" "${cats[@]}")

    local seeds
    seeds=($(list_seeds "$cat"))
    local seed
    seed=$(pick_one "選擇 seed >" "${seeds[@]}")

    local tools
    tools=($(list_tools))
    local tool
    tool=$(pick_one "選擇工具 >" "${tools[@]}")

    do_quickrun_exec "$SEEDS_DIR/$cat/${seed}.yaml" "$tool"
}

do_quickrun_exec() {
    local seed_file="$1"
    local tool="${2:-codex}"
    local timeout="${3:-120}"
    local judge_tool="${4:-$tool}"

    local id cat
    id=$(yaml_get "$seed_file" "id")
    cat=$(yaml_get "$seed_file" "category")

    echo ""
    echo "快速測試：$id ($cat)"
    print_sep

    # Copy seed to approved
    local dest_dir="$APPROVED_DIR/$cat"
    local filename
    filename=$(basename "$seed_file")
    mkdir -p "$dest_dir"
    cp "$seed_file" "$dest_dir/$filename"

    # Run
    "$TOOLS_DIR/run.sh" --category "$cat" --tool "$tool" --judge-tool "$judge_tool" --timeout "$timeout"

    # Show report
    echo ""
    "$TOOLS_DIR/report.sh"

    # Cleanup
    rm -f "$dest_dir/$filename"
    # Only remove dir if empty
    rmdir "$dest_dir" 2>/dev/null || true
}

# ─── Main ───────────────────────────────────────

show_menu() {
    echo ""
    echo "Benchmark Pipeline"
    printf '=%.0s' $(seq 1 40)
    echo ""
    echo "  1) 擴展種子 (expand)"
    echo "  2) 審核變體 (review)"
    echo "  3) 執行測試 (run)"
    echo "  4) 查看報告 (report)"
    echo "  5) 快速測試 (quickrun)"
    echo "  q) 離開"
    echo ""
}

main_interactive() {
    while true; do
        show_menu
        printf "選擇 > "
        read -r -n 1 choice
        echo ""

        case "$choice" in
            1) do_expand_interactive ;;
            2) do_review_interactive ;;
            3) do_run_interactive ;;
            4) do_report ;;
            5) do_quickrun_interactive ;;
            q|Q) echo "再見！"; exit 0 ;;
            *) echo "請輸入 1-5 或 q" ;;
        esac
    done
}

# Route: subcommand or interactive
if [ $# -eq 0 ]; then
    main_interactive
else
    CMD="$1"; shift
    case "$CMD" in
        expand)
            "$TOOLS_DIR/expand.sh" "$@"
            ;;
        review)
            "$TOOLS_DIR/review.sh" "$@"
            ;;
        run)
            "$TOOLS_DIR/run.sh" "$@"
            ;;
        report)
            do_report "$@"
            ;;
        quickrun)
            # Parse quickrun args
            QR_SEED=""
            QR_TOOL="codex"
            QR_TIMEOUT="120"
            QR_JUDGE=""
            while [[ $# -gt 0 ]]; do
                case $1 in
                    --seed|-s)       QR_SEED="$2"; shift 2 ;;
                    --tool|-t)       QR_TOOL="$2"; shift 2 ;;
                    --timeout)       QR_TIMEOUT="$2"; shift 2 ;;
                    --judge-tool)    QR_JUDGE="$2"; shift 2 ;;
                    --help|-h)
                        echo "Usage: $0 quickrun --seed <seed-file> [--tool codex] [--timeout 120] [--judge-tool codex]"
                        exit 0
                        ;;
                    *) echo "Unknown option: $1" >&2; exit 1 ;;
                esac
            done
            if [ -z "$QR_SEED" ]; then
                do_quickrun_interactive
            else
                do_quickrun_exec "$QR_SEED" "$QR_TOOL" "$QR_TIMEOUT" "${QR_JUDGE:-$QR_TOOL}"
            fi
            ;;
        --help|-h)
            echo "Usage: $0 [command] [options]"
            echo ""
            echo "Commands:"
            echo "  expand     擴展種子為測試變體"
            echo "  review     審核生成的變體"
            echo "  run        執行已核准的測試"
            echo "  report     查看測試報告"
            echo "  quickrun   一鍵測試（seed → run → report）"
            echo ""
            echo "無參數執行則進入互動模式。"
            exit 0
            ;;
        *)
            echo "未知指令：$CMD" >&2
            echo "執行 $0 --help 查看可用指令。" >&2
            exit 1
            ;;
    esac
fi
```

**Step 2: Make executable and test help**

Run: `chmod +x tests/benchmark/benchmark.sh && tests/benchmark/benchmark.sh --help`

Expected: Usage text with subcommands printed, exit 0.

**Step 3: Test quickrun help**

Run: `tests/benchmark/benchmark.sh quickrun --help`

Expected: Quickrun usage text, exit 0.

**Step 4: Commit**

```bash
git add tests/benchmark/benchmark.sh
git commit -m "feat: add benchmark.sh interactive CLI with menu and subcommands"
```

---

### Task 3: End-to-end quickrun test

**Step 1: Run quickrun with codex on the reasoning seed**

```bash
cd tests/benchmark
./benchmark.sh quickrun --seed seeds/reasoning/debug-off-by-one-001.yaml --tool codex
```

Expected: Test runs, report prints human-friendly Chinese output, cleanup happens.

**Step 2: Run quickrun with codex on the anti-bullshit seed**

```bash
./benchmark.sh quickrun --seed seeds/anti-bullshit/cross-domain-stitching-001.yaml --tool codex
```

Expected: Test runs, report shows score and judge reasoning in Chinese.

**Step 3: Verify cleanup (no leftover approved files)**

```bash
find tests/benchmark/generated/approved -name "*.yaml" -type f
```

Expected: No output (quickrun cleaned up after itself).

**Step 4: Commit**

```bash
git add tests/benchmark/
git commit -m "feat: verified interactive CLI with end-to-end quickrun tests"
```

---

Plan complete and saved to `docs/plans/2026-03-02-benchmark-interactive-cli-implementation.md`. Two execution options:

**1. Subagent-Driven (this session)** — I dispatch fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** — Open new session with executing-plans, batch execution with checkpoints

Which approach?
