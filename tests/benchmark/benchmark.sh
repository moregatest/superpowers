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
