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
