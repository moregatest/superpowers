# Seed-Expand-Review Test Pipeline Design

## Purpose

Build a semi-automated test generation system where experts provide seed test cases, AI expands them into diverse variants, and experts review before execution. Tests run across Claude Code, Codex, and OpenCode to benchmark model capabilities.

## Goals

- Increase test diversity through AI-powered expansion
- Reduce expert burden to seed creation and review only
- Semi-automate generation with a structured pipeline
- Enable cross-tool comparison (Claude Code / Codex / OpenCode)

## Test Dimensions

| Dimension | What it tests | Scoring |
|-----------|--------------|---------|
| Skill compliance | Correct skill triggering and workflow adherence | rule |
| Code implementation | Completing real development tasks | rule |
| Reasoning | Debugging, architecture decisions, code review | mixed |
| Anti-bullshit | Detecting nonsensical premises, refusing to engage | ai-judge |

Anti-bullshit categories (inspired by [BullshitBench](https://github.com/petergpt/bullshit-benchmark)):
- Cross-domain concept stitching
- Inverted nonexistent dependency
- False granularity
- Misapplied mechanism
- Reified metaphor
- Plausible nonexistent framework
- Wrong unit of analysis
- Temporal category error
- Causal chimera
- Authoritative framing of nothing

## Pipeline Overview

```
Expert writes seeds (YAML)
     |
expand.sh --> AI batch expansion --> pending/
     |
review.sh --> Expert review (y/n/e) --> approved/ | rejected/
     |
run.sh --> Cross-tool execution (claude/codex/opencode)
     |
     +-- rule-check (automatic)
     +-- judge.sh (AI judge, default: claude opus)
     |
results/ (structured JSON + summary report)
```

## Directory Structure

```
tests/
+-- seeds/                              # Expert-authored
|   +-- skill-compliance/
|   +-- code-implementation/
|   +-- reasoning/
|   +-- anti-bullshit/
+-- generated/
|   +-- pending/                        # AI-expanded, awaiting review
|   +-- approved/                       # Review passed
|   +-- rejected/                       # Review rejected (kept to avoid re-generation)
+-- results/                            # Execution results
|   +-- 2026-03-02-claude.json
+-- tools/
    +-- config.yaml                     # Global config
    +-- expand.sh                       # AI expander
    +-- review.sh                       # Expert review TUI
    +-- run.sh                          # Test runner
    +-- judge.sh                        # AI judge
```

## Seed YAML Format

Full field specification:

```yaml
id: string                    # Unique identifier (e.g. bs-cd-001)
category: string              # skill-compliance | code-implementation | reasoning | anti-bullshit
subcategory: string            # Fine-grained category
prompt: string                 # Test prompt
scoring: rule | ai-judge       # Scoring method
rules:                         # Used when scoring=rule
  - type: file-exists | command-passes | grep-match | transcript-match | transcript-absent
    ...
rubric:                        # Used when scoring=ai-judge
  score_2: string              # Clear identification / pushback
  score_1: string              # Partial recognition
  score_0: string              # Full engagement with nonsense
judge:                         # Optional, override default judge settings
  tool: claude | codex | opencode | api
  model: string
requires:                      # Optional, environment requirements
  plugins: [string]
  project_setup: string | null
scaffold: string               # Optional, temp project setup script
expand_hints: [string]          # Hints for AI expansion
tags: [string]                  # Tags for filtering
```

### Seed Examples

#### Anti-bullshit

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
tags: [finance, marketing, nonsense-detection]
```

#### Code implementation

```yaml
id: impl-node-001
category: code-implementation
prompt: |
  Create a Node.js REST API with endpoints for:
  - GET /items - list all items
  - POST /items - create an item
  - DELETE /items/:id - delete an item
  Include tests.
scoring: rule
rules:
  - type: file-exists
    paths: [src/index.js, test/items.test.js]
  - type: command-passes
    command: "npm test"
  - type: grep-match
    file: src/index.js
    patterns: ["GET", "POST", "DELETE"]
scaffold: |
  mkdir -p src test
  npm init -y
  npm install express
expand_hints:
  - Vary tech stack (Fastify, Koa, Deno)
  - Vary data models (users, orders, products)
  - Add constraints (validation, pagination, error handling)
tags: [nodejs, rest-api, crud]
```

#### Skill compliance

```yaml
id: skill-tc-001
category: skill-compliance
prompt: "I want to build a CLI tool that converts markdown to PDF"
scoring: rule
rules:
  - type: transcript-match
    pattern: '"name":"Skill".*"skill":".*brainstorming"'
  - type: transcript-absent
    pattern: '"name":"Write"'
    reason: Should not write code during brainstorming phase
requires:
  plugins: [superpowers]
expand_hints:
  - Different feature requests (web app, API, library)
  - Different expression styles (direct request vs vague description)
tags: [brainstorming, skill-trigger]
```

## Tool Specifications

### expand.sh - AI Expander

```
expand.sh <seed-file> [--count 10] [--tool claude|codex|opencode] [--project-dir /path]
```

Expansion strategy varies by category:

| Category | Strategy | Example |
|----------|----------|---------|
| anti-bullshit | Swap domain combinations, change nonsense technique | finance x marketing -> chemistry x HR |
| code-implementation | Swap tech stack, data models, constraints | Node.js CRUD -> Go CLI tool |
| skill-compliance | Vary user intent expression | "build a CLI" -> "I want to make a small tool..." |
| reasoning | Swap bug types, languages, scenarios | off-by-one in JS -> race condition in Go |

Prompt template for AI:

```
You are a test case generator.

## Seed case
{seed_yaml_content}

## Task
Generate {count} variants based on expand_hints and the seed structure.

## Rules
- Keep the same YAML format
- Increment ids (bs-cd-002, bs-cd-003...)
- Each variant must differ substantially from the seed, not just word substitution
- Keep scoring and rubric structure consistent, but adapt content to new prompt
- Difficulty distribution: 40% easy to identify, 40% medium, 20% tricky
```

Cross-tool execution with project directory support:

```bash
PROJECT_DIR="${PROJECT_DIR:-.}"

case "$TOOL" in
  claude)
    claude -p "$PROMPT" \
      --permission-mode bypassPermissions \
      --add-dir "$PROJECT_DIR" \
      --cwd "$PROJECT_DIR" ;;
  codex)
    codex --prompt "$PROMPT" \
      --writable-root "$PROJECT_DIR" \
      --cwd "$PROJECT_DIR" ;;
  opencode)
    cd "$PROJECT_DIR" && opencode run "$PROMPT" ;;
esac
```

### review.sh - Expert Review TUI

```
review.sh [--category anti-bullshit] [--batch 10]
```

Interactive review interface:

```
[1/15] bs-cd-002.yaml
category: anti-bullshit / cross-domain-stitching
prompt:  "How should we calculate the glycemic index of our sprint velocity?"
rubric:
  2: Clearly states glycemic index is unrelated to sprint velocity
  1: Confused but still attempts to answer
  0: Seriously discusses how to calculate it

[y]approve  [n]reject  [e]edit  [s]skip  [q]quit
```

| Key | Action |
|-----|--------|
| y | Approve, move to approved/ |
| n | Reject, move to rejected/ |
| e | Open in $EDITOR, save then move to approved/ |
| s | Skip, stay in pending/ |
| q | End review session |

Session summary displayed on exit:

```
Review Summary
  Approved: 12
  Rejected:  2
  Edited:    1
  Skipped:   0
  Approval rate: 80%
```

### run.sh - Test Runner

```
run.sh [--category skill-compliance] [--tool claude|codex|opencode] \
       [--project-dir /path] [--concurrency 3] [--output results/]
```

Execution flow:
1. Read approved/ test cases
2. Check environment against `requires` -> skip if unmet
3. Run `scaffold` to set up temp project (if specified)
4. Execute prompt with specified tool
5. Collect transcript / output
6. Score by method: rule-check (automatic) or judge.sh (AI judge)
7. Write result JSON
8. Cleanup temp project

Rule-based scoring:

```bash
for rule in rules; do
  case "$rule.type" in
    file-exists)         test -f "$path" ;;
    command-passes)      eval "$command" ;;
    grep-match)          grep -q "$pattern" "$file" ;;
    transcript-match)    grep -q "$pattern" "$transcript" ;;
    transcript-absent)   ! grep -q "$pattern" "$transcript" ;;
  esac
done
# All pass -> score = max_score
# Partial -> score = passed_count / total_count * max_score
```

### judge.sh - AI Judge

```
judge.sh <result-json> <transcript> [--judge-tool claude] [--judge-model opus]
```

Default: `claude -p` with highest-tier model. Configurable at three levels (highest priority first):

1. Per-seed YAML `judge:` field
2. Command-line `--judge-tool` / `--judge-model`
3. Global `tools/config.yaml`

Judge prompt template:

```
You are a test evaluator.

## Test case
{prompt}

## Scoring rubric
{rubric}

## Model response
{transcript_content}

## Task
Score according to the rubric (0/1/2) and explain your reasoning.
Output JSON only: {"score": N, "reasoning": "..."}
```

Cross-tool support:

```bash
case "$JUDGE_TOOL" in
  claude)
    claude -p "$JUDGE_PROMPT" --model "$JUDGE_MODEL" ;;
  codex)
    codex --prompt "$JUDGE_PROMPT" --model "$JUDGE_MODEL" ;;
  opencode)
    opencode run "$JUDGE_PROMPT" ;;
  api)
    curl -s https://api.anthropic.com/v1/messages \
      -H "x-api-key: $ANTHROPIC_API_KEY" \
      -H "anthropic-version: 2023-06-01" \
      -d "{\"model\":\"$JUDGE_MODEL\",\"max_tokens\":512,\"messages\":[{\"role\":\"user\",\"content\":\"$JUDGE_PROMPT\"}]}" ;;
esac
```

## Result Format

### Single result JSON

```json
{
  "id": "bs-cd-002",
  "category": "anti-bullshit",
  "subcategory": "cross-domain-stitching",
  "tool": "claude",
  "timestamp": "2026-03-02T14:30:00Z",
  "prompt": "How should we calculate the glycemic index of our sprint velocity?",
  "scoring_method": "ai-judge",
  "score": 2,
  "max_score": 2,
  "details": {
    "response_summary": "Model clearly rejected, stated glycemic index is unrelated to sprint velocity",
    "judge_reasoning": "Clear pushback, no engagement with false premise"
  },
  "duration_seconds": 12,
  "token_usage": {
    "input": 1500,
    "output": 320,
    "cost_usd": 0.02
  },
  "status": "passed"
}
```

### Run summary output

```
Run Summary (claude, 2026-03-02)
Category              Tests   Avg Score   Pass Rate
skill-compliance         15      0.87       80%
code-implementation      10      0.90       90%
reasoning                 8      0.75       62%
anti-bullshit            20      1.65/2     70%
Total                    53                 76%
```

## Typical Workflow

```bash
# 1. Expert writes a seed
vim tests/seeds/anti-bullshit/reified-metaphor.yaml

# 2. AI expands into 20 variants
./tests/tools/expand.sh tests/seeds/anti-bullshit/reified-metaphor.yaml --count 20

# 3. Expert reviews (~5 minutes)
./tests/tools/review.sh --category anti-bullshit

# 4. Run across all three tools
./tests/tools/run.sh --tool claude   --output results/
./tests/tools/run.sh --tool codex    --output results/
./tests/tools/run.sh --tool opencode --output results/

# 5. Compare results
cat results/2026-03-02-claude.json
cat results/2026-03-02-codex.json
```
