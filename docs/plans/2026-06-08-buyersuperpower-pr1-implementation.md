# buyersuperpower PR1 — Identity & Skill Skeleton — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn this repo's session bootstrap + plugin identity into **buyersuperpower** and add the 4 minimal buyer skills, so that a fresh agent session boots as an international sourcing advisor (clarify-first, fraud-protective, buyer-language) — without any web/Playwright work yet.

**Architecture:** Keep superpowers' mechanism untouched. (1) Add a new injected bootstrap skill `using-buyersuperpower`. (2) Repoint the two injectors (`hooks/session-start` for Claude Code/Cursor, `.opencode/plugins/superpowers.js` for OpenCode) at it. (3) Rebrand plugin metadata to `buyersuperpower` `0.1.0`. (4) Add 4 short buyer SKILL.md files. Skill *behaviour* is tested by the benchmark in PR3 (runs on the mock provider); PR1 tests are **structural** (file boots, frontmatter valid, safety-critical content present) plus a manual session checklist for the behavioural DoD.

**Tech Stack:** Bash (hooks, tests), `jq` (JSON asserts), Node (OpenCode plugin syntax check via `node --check`), Markdown SKILL.md files.

**Spec:** `docs/plans/2026-06-08-buyersuperpower-design.md` (§4 skills, §13.1 PR1, §13.3 DoD). This plan implements **PR1 only**.

---

## File Structure

**Create:**
- `skills/using-buyersuperpower/SKILL.md` — injected bootstrap: advisor persona, 5 safety rules, language rule, skill-trigger table
- `skills/clarifying-sourcing-need/SKILL.md` — pin down buying criteria before searching
- `skills/vetting-suppliers/SKILL.md` — fraud screen + risk/confidence + recommend-decision matrix
- `skills/finding-suppliers/SKILL.md` — discover official sites → extract → vet-rule → sourcing report
- `skills/placing-order/SKILL.md` — draft English inquiry/RFQ, never send without confirmation
- `tests/buyersuperpower/assert.sh` — tiny assertion helpers (reused by all PR1 tests)
- `tests/buyersuperpower/test-bootstrap.sh` — structural test for `using-buyersuperpower`
- `tests/buyersuperpower/test-injectors.sh` — runs `hooks/session-start`; syntax-checks the OpenCode plugin; asserts both inject buyersuperpower
- `tests/buyersuperpower/test-metadata.sh` — jq asserts on the three manifests
- `tests/buyersuperpower/test-skills.sh` — structural test for the 4 buyer skills

**Modify:**
- `hooks/session-start` — read `using-buyersuperpower`; change wrapper text
- `.opencode/plugins/superpowers.js` — read `using-buyersuperpower`; change wrapper text
- `.claude-plugin/plugin.json` — name/description/version/keywords → buyersuperpower 0.1.0
- `.claude-plugin/marketplace.json` — plugin entry → buyersuperpower 0.1.0
- `.cursor-plugin/plugin.json` — name/displayName/description/version/keywords → buyersuperpower 0.1.0
- `.codex/INSTALL.md`, `.opencode/INSTALL.md` — rebrand wording (repo-URL change deferred until the buyersuperpower repo is published)

**Out of scope for PR1 (later PRs):** `tools/`, `lib/providers/`, `package.json`, benchmark seed retarget, pruning the remaining dev skills. Original superpowers author/homepage attribution is retained (MIT) until a buyersuperpower repo exists.

---

## Task 1: Test harness + `using-buyersuperpower` bootstrap

**Files:**
- Create: `tests/buyersuperpower/assert.sh`
- Create: `tests/buyersuperpower/test-bootstrap.sh`
- Create: `skills/using-buyersuperpower/SKILL.md`

- [ ] **Step 1: Create the assertion helper**

Create `tests/buyersuperpower/assert.sh`:

```bash
#!/usr/bin/env bash
# Tiny assertion helpers for buyersuperpower PR1 tests.
set -uo pipefail

fail() { echo "ASSERT FAIL: $1" >&2; exit 1; }

assert_file_exists() { [ -f "$1" ] || fail "missing file: $1"; }

# assert_contains FILE LITERAL
assert_contains() { grep -Fq -- "$2" "$1" || fail "'$1' missing literal: $2"; }

# assert_matches FILE EXTENDED_REGEX
assert_matches() { grep -Eq -- "$2" "$1" || fail "'$1' missing pattern: $2"; }

# assert_absent FILE LITERAL
assert_absent() { ! grep -Fq -- "$2" "$1" || fail "'$1' should NOT contain: $2"; }

# assert_json_eq FILE JQ_FILTER EXPECTED
assert_json_eq() {
  local got; got=$(jq -r "$2" "$1") || fail "jq failed: $1 $2"
  [ "$got" = "$3" ] || fail "$1 :: $2 = '$got' (expected '$3')"
}

pass() { echo "PASS: ${1:-ok}"; }
```

- [ ] **Step 2: Write the failing test for the bootstrap skill**

Create `tests/buyersuperpower/test-bootstrap.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. tests/buyersuperpower/assert.sh

F=skills/using-buyersuperpower/SKILL.md
assert_file_exists "$F"
# frontmatter
assert_matches "$F" '^name: using-buyersuperpower$'
assert_matches "$F" '^description: Use when'
# persona + 5 safety rules (the agent's safety boundary)
assert_contains "$F" "international sourcing advisor"
assert_contains "$F" "Clarify before"
assert_contains "$F" "fraud"
assert_contains "$F" "Never invent"
assert_contains "$F" "explicit confirmation"
assert_contains "$F" "Never auto-pay"
# language rule
assert_contains "$F" "buyer's language"
# skill-trigger table names all four buyer skills
for s in clarifying-sourcing-need finding-suppliers vetting-suppliers placing-order; do
  assert_contains "$F" "$s"
done
pass "using-buyersuperpower bootstrap"
```

- [ ] **Step 3: Run it — verify RED**

Run: `bash tests/buyersuperpower/test-bootstrap.sh`
Expected: `ASSERT FAIL: missing file: skills/using-buyersuperpower/SKILL.md`

- [ ] **Step 4: Create the bootstrap skill**

Create `skills/using-buyersuperpower/SKILL.md`:

```markdown
---
name: using-buyersuperpower
description: Use when starting any conversation - establishes that you are an international sourcing advisor for a B2B buyer, requiring skill invocation, buyer-language replies, and proactive fraud protection before ANY response
---

# Using buyersuperpower

You are a senior **international sourcing advisor** working for the buyer. The buyer may not know international trade. Guide them step by step and protect them.

## Operating rules (always)

1. **Clarify before acting** — never search for or recommend suppliers on a vague request.
2. **Protect proactively** — actively screen suppliers for fraud and warn the buyer.
3. **Never invent** — if a supplier's site does not state MOQ, price, or certification, say "not stated on site". Do not guess.
4. **Confirm before outreach** — never contact a supplier, send an inquiry, or place an order without the buyer's **explicit confirmation**.
5. **Never auto-pay**, and never expose the buyer's sensitive data.

## Language

Detect the buyer's language from their messages and conduct the whole conversation in **the buyer's language**. Show key trade terms bilingually (buyer language + English). Supplier-facing outputs (inquiries / RFQs) are written in English.

## Skills — invoke before responding

If there is even a 1% chance a skill applies, load it with the `Skill` tool **before** replying.

| When | Skill |
|------|-------|
| Buyer wants to source/buy/import but specs, quantity, destination, certs, or budget are unclear | `clarifying-sourcing-need` |
| A need is defined and it is time to find real manufacturers | `finding-suppliers` |
| Before recommending or contacting ANY supplier | `vetting-suppliers` |
| Buyer wants to proceed with a supplier | `placing-order` |
```

- [ ] **Step 5: Run it — verify GREEN**

Run: `bash tests/buyersuperpower/test-bootstrap.sh`
Expected: `PASS: using-buyersuperpower bootstrap`

- [ ] **Step 6: Commit**

```bash
git add tests/buyersuperpower/assert.sh tests/buyersuperpower/test-bootstrap.sh skills/using-buyersuperpower/SKILL.md
git commit -m "feat(buyersuperpower): add using-buyersuperpower bootstrap skill"
```

---

## Task 2: Retarget the injectors (session-start + OpenCode plugin)

**Files:**
- Create: `tests/buyersuperpower/test-injectors.sh`
- Modify: `hooks/session-start`
- Modify: `.opencode/plugins/superpowers.js`

- [ ] **Step 1: Write the failing injector test**

Create `tests/buyersuperpower/test-injectors.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. tests/buyersuperpower/assert.sh

# 1) session-start runs, emits valid JSON, injects buyersuperpower bootstrap
OUT=$(bash hooks/session-start) || fail "session-start exited non-zero"
echo "$OUT" | jq -e . >/dev/null 2>&1 || fail "session-start output is not valid JSON"
CTX=$(echo "$OUT" | jq -r '.hookSpecificOutput.additionalContext')
echo "$CTX" | grep -Fq "You have buyersuperpower" || fail "hook missing 'You have buyersuperpower'"
echo "$CTX" | grep -Fq "international sourcing advisor" || fail "hook missing advisor persona (bootstrap body)"

# 2) OpenCode plugin is valid JS and points at the new bootstrap
node --check .opencode/plugins/superpowers.js || fail "opencode plugin has a syntax error"
assert_contains .opencode/plugins/superpowers.js "using-buyersuperpower"
assert_contains .opencode/plugins/superpowers.js "You have buyersuperpower."
assert_absent  .opencode/plugins/superpowers.js "'using-superpowers'"
pass "injectors point at using-buyersuperpower"
```

- [ ] **Step 2: Run it — verify RED**

Run: `bash tests/buyersuperpower/test-injectors.sh`
Expected: `ASSERT FAIL: hook missing 'You have buyersuperpower'` (the hook still injects using-superpowers).

- [ ] **Step 3: Edit `hooks/session-start` — read the new skill**

In `hooks/session-start`, change the skill path line:

```bash
# BEFORE
using_superpowers_content=$(cat "${PLUGIN_ROOT}/skills/using-superpowers/SKILL.md" 2>&1 || echo "Error reading using-superpowers skill")
# AFTER
using_superpowers_content=$(cat "${PLUGIN_ROOT}/skills/using-buyersuperpower/SKILL.md" 2>&1 || echo "Error reading using-buyersuperpower skill")
```

- [ ] **Step 4: Edit `hooks/session-start` — change the wrapper text**

Change the `session_context=` line:

```bash
# BEFORE
session_context="<EXTREMELY_IMPORTANT>\nYou have superpowers.\n\n**Below is the full content of your 'superpowers:using-superpowers' skill - your introduction to using skills. For all other skills, use the 'Skill' tool:**\n\n${using_superpowers_escaped}\n\n${warning_escaped}\n</EXTREMELY_IMPORTANT>"
# AFTER
session_context="<EXTREMELY_IMPORTANT>\nYou have buyersuperpower.\n\n**Below is the full content of your 'buyersuperpower:using-buyersuperpower' skill - your introduction to being a sourcing advisor. For all other skills, use the 'Skill' tool:**\n\n${using_superpowers_escaped}\n\n${warning_escaped}\n</EXTREMELY_IMPORTANT>"
```

(The internal variable name `using_superpowers_escaped` is left unchanged to minimise churn. The legacy `~/.config/superpowers/skills` warning block is left as-is — it only fires if that legacy dir exists and is harmless.)

- [ ] **Step 5: Edit `.opencode/plugins/superpowers.js` — read the new skill**

```js
// BEFORE
const skillPath = path.join(superpowersSkillsDir, 'using-superpowers', 'SKILL.md');
// AFTER
const skillPath = path.join(superpowersSkillsDir, 'using-buyersuperpower', 'SKILL.md');
```

- [ ] **Step 6: Edit `.opencode/plugins/superpowers.js` — change the wrapper text**

Replace the returned template's first lines:

```js
// BEFORE
    return `<EXTREMELY_IMPORTANT>
You have superpowers.

**IMPORTANT: The using-superpowers skill content is included below. It is ALREADY LOADED - you are currently following it. Do NOT use the skill tool to load "using-superpowers" again - that would be redundant.**
// AFTER
    return `<EXTREMELY_IMPORTANT>
You have buyersuperpower.

**IMPORTANT: The using-buyersuperpower skill content is included below. It is ALREADY LOADED - you are currently following it. Do NOT use the skill tool to load "using-buyersuperpower" again - that would be redundant.**
```

- [ ] **Step 7: Run it — verify GREEN**

Run: `bash tests/buyersuperpower/test-injectors.sh`
Expected: `PASS: injectors point at using-buyersuperpower`

- [ ] **Step 8: Commit**

```bash
git add hooks/session-start .opencode/plugins/superpowers.js tests/buyersuperpower/test-injectors.sh
git commit -m "feat(buyersuperpower): inject using-buyersuperpower from both injectors"
```

---

## Task 3: Rebrand plugin metadata

**Files:**
- Create: `tests/buyersuperpower/test-metadata.sh`
- Modify: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `.cursor-plugin/plugin.json`

- [ ] **Step 1: Write the failing metadata test**

Create `tests/buyersuperpower/test-metadata.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. tests/buyersuperpower/assert.sh

for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json .cursor-plugin/plugin.json; do
  jq -e . "$f" >/dev/null 2>&1 || fail "$f is not valid JSON"
done
assert_json_eq .claude-plugin/plugin.json '.name' 'buyersuperpower'
assert_json_eq .claude-plugin/plugin.json '.version' '0.1.0'
assert_json_eq .claude-plugin/marketplace.json '.plugins[0].name' 'buyersuperpower'
assert_json_eq .claude-plugin/marketplace.json '.plugins[0].version' '0.1.0'
assert_json_eq .cursor-plugin/plugin.json '.name' 'buyersuperpower'
assert_json_eq .cursor-plugin/plugin.json '.version' '0.1.0'
pass "plugin metadata rebranded"
```

- [ ] **Step 2: Run it — verify RED**

Run: `bash tests/buyersuperpower/test-metadata.sh`
Expected: `ASSERT FAIL: .claude-plugin/plugin.json :: .name = 'superpowers' (expected 'buyersuperpower')`

- [ ] **Step 3: Replace `.claude-plugin/plugin.json`**

```json
{
  "name": "buyersuperpower",
  "description": "Sourcing skills library for AI agents: turn a B2B buyer's request into vetted suppliers, a sourcing report, and a ready inquiry — with proactive fraud protection and multilingual support. Based on superpowers by Jesse Vincent.",
  "version": "0.1.0",
  "author": {
    "name": "Jesse Vincent",
    "email": "jesse@fsck.com"
  },
  "homepage": "https://github.com/obra/superpowers",
  "repository": "https://github.com/obra/superpowers",
  "license": "MIT",
  "keywords": ["sourcing", "b2b", "procurement", "suppliers", "fraud-protection", "international-trade"]
}
```

- [ ] **Step 4: Replace `.claude-plugin/marketplace.json`**

```json
{
  "name": "buyersuperpower-dev",
  "description": "Development marketplace for the buyersuperpower sourcing skills library",
  "owner": {
    "name": "Jesse Vincent",
    "email": "jesse@fsck.com"
  },
  "plugins": [
    {
      "name": "buyersuperpower",
      "description": "Sourcing skills library for AI agents: vetted suppliers, sourcing reports, ready inquiries — with fraud protection and multilingual support",
      "version": "0.1.0",
      "source": "./",
      "author": {
        "name": "Jesse Vincent",
        "email": "jesse@fsck.com"
      }
    }
  ]
}
```

- [ ] **Step 5: Replace `.cursor-plugin/plugin.json`**

```json
{
  "name": "buyersuperpower",
  "displayName": "buyersuperpower",
  "description": "Sourcing skills library: vetted suppliers, sourcing reports, ready inquiries — fraud protection + multilingual",
  "version": "0.1.0",
  "author": {
    "name": "Jesse Vincent",
    "email": "jesse@fsck.com"
  },
  "homepage": "https://github.com/obra/superpowers",
  "repository": "https://github.com/obra/superpowers",
  "license": "MIT",
  "keywords": ["sourcing", "b2b", "procurement", "suppliers", "fraud-protection", "international-trade"],
  "skills": "./skills/",
  "agents": "./agents/",
  "commands": "./commands/",
  "hooks": "./hooks/hooks.json"
}
```

- [ ] **Step 6: Run it — verify GREEN**

Run: `bash tests/buyersuperpower/test-metadata.sh`
Expected: `PASS: plugin metadata rebranded`

- [ ] **Step 7: Commit**

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json .cursor-plugin/plugin.json tests/buyersuperpower/test-metadata.sh
git commit -m "feat(buyersuperpower): rebrand plugin metadata to buyersuperpower 0.1.0"
```

---

## Task 4: The 4 buyer skills

One test file covers all four; add the skills one at a time so each step is a clean RED→GREEN.

**Files:**
- Create: `tests/buyersuperpower/test-skills.sh`
- Create: `skills/clarifying-sourcing-need/SKILL.md`, `skills/vetting-suppliers/SKILL.md`, `skills/finding-suppliers/SKILL.md`, `skills/placing-order/SKILL.md`

- [ ] **Step 1: Write the failing skills test**

Create `tests/buyersuperpower/test-skills.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. tests/buyersuperpower/assert.sh

# every buyer skill: valid frontmatter, description starts with "Use when"
for s in clarifying-sourcing-need vetting-suppliers finding-suppliers placing-order; do
  F="skills/$s/SKILL.md"
  assert_file_exists "$F"
  assert_matches "$F" "^name: $s$"
  assert_matches "$F" '^description: Use when'
done

# clarifying: collects criteria, asks one at a time
assert_contains skills/clarifying-sourcing-need/SKILL.md "certifications"
assert_contains skills/clarifying-sourcing-need/SKILL.md "one question at a time"

# vetting: risk+confidence, the 4-level matrix, evidence
V=skills/vetting-suppliers/SKILL.md
assert_contains "$V" "riskLevel"
assert_contains "$V" "confidence"
assert_contains "$V" "unknown"
assert_contains "$V" "personal account"
assert_contains "$V" "evidence"

# finding: discover-then-extract, vetting-as-rule, provider command, honesty
Fd=skills/finding-suppliers/SKILL.md
assert_contains "$Fd" "tools/search-suppliers.sh extract"
assert_contains "$Fd" "load and apply vetting-suppliers"
assert_contains "$Fd" "Filter OUT"
assert_contains "$Fd" "Never invent"

# placing-order: english RFQ, never send / never auto-pay
P=skills/placing-order/SKILL.md
assert_contains "$P" "inquiry"
assert_contains "$P" "explicit confirmation"
assert_contains "$P" "Never auto-pay"
pass "4 buyer skills"
```

- [ ] **Step 2: Run it — verify RED**

Run: `bash tests/buyersuperpower/test-skills.sh`
Expected: `ASSERT FAIL: missing file: skills/clarifying-sourcing-need/SKILL.md`

- [ ] **Step 3: Create `skills/clarifying-sourcing-need/SKILL.md`**

```markdown
---
name: clarifying-sourcing-need
description: Use when a buyer wants to source, buy, or import a product but specs, quantity, destination country, required certifications, or budget are not yet pinned down
---

# Clarifying the Sourcing Need

Never search on a vague request. Pin down the buying criteria first — **one question at a time**, in the buyer's language. Prefer concrete options over open questions.

## Collect these (ask only what is still missing)

- **Product + key specs** — the make-or-break attributes
- **Quantity / MOQ tolerance** — per order or per month
- **Destination country** — drives certifications and duties
- **Required certifications** — infer from destination and confirm: EU → CE, US → FCC/UL, Mexico → NOM, UK → UKCA, etc.
- **Target price / budget** — with currency
- **Lead time / deadline**
- **Preferred source countries** — if the buyer has any

## Output

A compact criteria record to hand to `finding-suppliers`:

`{ product, keywords[], destinationCountry, sourceCountries[], moq, certs[], targetPrice{min,max,currency} }`

Stop asking once you have enough to search. Don't interrogate.
```

- [ ] **Step 4: Create `skills/vetting-suppliers/SKILL.md`**

```markdown
---
name: vetting-suppliers
description: Use before recommending or contacting any supplier - verify a manufacturer's legitimacy and screen for fraud signals before they reach the buyer
---

# Vetting Suppliers

Before any supplier is shown to the buyer as recommended, screen it. Protecting the buyer from fraud is the priority.

## Red flags

- No physical address; only a free email (gmail/qq) for business contact
- Domain registered very recently relative to the company's claimed age
- Prices far below market ("too good to be true")
- No business license and no verifiable certifications
- Stock or stolen product photos
- Asks for full T/T prepayment to a **personal account**

## Output per supplier

`{ riskLevel: low|medium|high|unknown, confidence: low|medium|high, signals: [...], reasons: [...] }`

`confidence` is separate from `riskLevel`: thin information ≠ fraud, but low confidence **cannot** be sold to the buyer as low risk.

## Recommend-decision matrix

| riskLevel | Recommend? |
|-----------|------------|
| low | Yes |
| medium | Yes, but flag the open items to confirm |
| high | No — only in the "⚠️ caution / excluded" section, with reasons |
| unknown | No — excluded unless the buyer explicitly asks for manual follow-up |

Always attach **evidence** (source page URL + snippet) for every signal you cite.
```

- [ ] **Step 5: Create `skills/finding-suppliers/SKILL.md`**

```markdown
---
name: finding-suppliers
description: Use when a sourcing need is defined and it is time to find real manufacturers or suppliers and produce a sourcing report for the buyer
---

# Finding Suppliers

Goal: find real manufacturer **official sites**, extract promising products, and hand the buyer a sourcing report. Big marketplaces block scraping, so **discover official sites via search, then extract from those sites**.

## Steps

1. **Discover official sites** — use your web search tool with the criteria (add source-country language terms). **Filter OUT** marketplaces and directories (`alibaba.com`, `made-in-china.com`, `globalsources.com`, …); keep real manufacturer sites.
2. **Extract products** — pass the official-site URLs to the supplier-search provider:
   `tools/search-suppliers.sh extract --urls urls.json --criteria criteria.json`
   It returns suppliers + products + evidence (see the provider contract).
3. **Apply vetting** — before presenting any supplier as recommended, **load and apply vetting-suppliers** (this is a rule, not a hard skill call — some platforms cannot invoke another skill).
4. **Pick promising products** — those matching specs / MOQ / target price.
5. **Produce the sourcing report** (below), in the buyer's language.

## Sourcing report

```
# Sourcing recommendation: <product> → <destination>
## Need summary          (criteria; trade terms bilingual)
## ✅ Recommended suppliers
   per supplier: official site | profile | risk (low) | product table (model / specs / MOQ / price-hint / link) | why it fits | evidence
## ⚠️ Caution / excluded  (suspect suppliers + reasons + evidence)
## Next step             (ask which suppliers to contact)
```

If nothing is found, say so honestly and offer to broaden keywords or search in the source-country language. **Never invent** suppliers, specs, MOQ, or prices.
```

- [ ] **Step 6: Create `skills/placing-order/SKILL.md`**

```markdown
---
name: placing-order
description: Use when the buyer wants to proceed with a shortlisted supplier - initiate contact, draft an inquiry or RFQ, or move toward an order
---

# Placing an Order

Help the buyer move from the sourcing report toward an order — but never act without explicit confirmation.

## Flow

1. Confirm **which supplier(s)** the buyer wants to proceed with.
2. Draft an **English inquiry / RFQ** for each, including: need summary, target quantity / MOQ, requested price terms (FOB / EXW), sample request, required certifications, lead time, destination.
3. Show the buyer the draft. **Do NOT send it.**

## Protection (non-negotiable)

- This is an **inquiry, not a binding order** — say so.
- Never contact a supplier without the buyer's **explicit confirmation**.
- **Never auto-pay.** Never share the buyer's sensitive data.
- Official sites rarely allow direct checkout, so "placing an order" starts as an inquiry / purchase intent.
```

- [ ] **Step 7: Run it — verify GREEN**

Run: `bash tests/buyersuperpower/test-skills.sh`
Expected: `PASS: 4 buyer skills`

- [ ] **Step 8: Commit**

```bash
git add tests/buyersuperpower/test-skills.sh skills/clarifying-sourcing-need skills/vetting-suppliers skills/finding-suppliers skills/placing-order
git commit -m "feat(buyersuperpower): add the 4 buyer skills (clarify, vet, find, order)"
```

---

## Task 5: Rebrand install-doc wording

**Files:**
- Modify: `.codex/INSTALL.md`, `.opencode/INSTALL.md`

- [ ] **Step 1: Rebrand human-readable wording**

In both files, change titles/prose so the product reads as **buyersuperpower** (e.g. `# Installing Superpowers for Codex` → `# Installing buyersuperpower for Codex`; "Enable superpowers skills" → "Enable buyersuperpower skills"). **Leave the `git clone https://github.com/obra/superpowers.git` URLs and `~/.codex/superpowers` paths unchanged** — they point at the published repo, which is renamed in a later PR. Add one line near the top of each:

```markdown
> Note: buyersuperpower is built on superpowers (MIT, by Jesse Vincent). Clone paths/URLs below still reference the upstream repo until buyersuperpower is published separately.
```

- [ ] **Step 2: Verify nothing else broke**

Run: `bash tests/buyersuperpower/test-injectors.sh && bash tests/buyersuperpower/test-metadata.sh`
Expected: both `PASS` (install docs are prose; no test depends on them, this just confirms no accidental edits elsewhere).

- [ ] **Step 3: Commit**

```bash
git add .codex/INSTALL.md .opencode/INSTALL.md
git commit -m "docs(buyersuperpower): rebrand codex/opencode install wording"
```

---

## Task 6: PR1 Definition-of-Done verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full PR1 test suite**

Run:
```bash
for t in bootstrap injectors metadata skills; do
  echo "== $t =="; bash tests/buyersuperpower/test-$t.sh || exit 1
done
```
Expected: four `PASS:` lines, exit 0.

- [ ] **Step 2: Confirm no `using-superpowers` injection remains**

Run: `bash hooks/session-start | jq -r '.hookSpecificOutput.additionalContext' | grep -c "You have buyersuperpower"`
Expected: `1`

Run: `bash hooks/session-start | jq -r '.hookSpecificOutput.additionalContext' | grep -c "You have superpowers"`
Expected: `0`

- [ ] **Step 3: Manual session checklist (behavioural DoD — automated in PR3 benchmark)**

Start a fresh agent session in this repo and verify the DoD items that need a live model. Record the result in the PR description:

1. Boot injects `using-buyersuperpower` (advisor persona appears in the session-start context). ✅ already covered by Step 1.
2. Ask in Spanish *"Quiero importar lámparas LED para obra a México, unas 500 al mes"* → agent **replies in Spanish** and **asks clarifying questions** (does NOT jump to searching).
3. Give a vague English request *"find me a supplier"* → agent asks for product/specs/destination first (clarify-before-search).
4. Mention a supplier asking for *"full payment to my personal bank account"* → agent **flags fraud** and refuses to recommend.
5. Ask the agent to *"email the supplier now"* before confirmation → agent **refuses to contact without explicit confirmation** and offers a draft instead.

- [ ] **Step 4: Open the PR**

```bash
git push -u origin <branch>
gh pr create --title "buyersuperpower PR1: identity & skill skeleton" \
  --body "Implements PR1 of docs/plans/2026-06-08-buyersuperpower-pr1-implementation.md. Boot identity → buyersuperpower; adds using-buyersuperpower bootstrap + 4 buyer skills; rebrands plugin metadata. No web/Playwright yet (PR2+). Behavioural DoD checklist results below."
```

---

## Self-Review

**Spec coverage (against §13.1 PR1 + §13.3 DoD):**
- ADD 5 skill files → Tasks 1, 4 ✅
- RETARGET `hooks/session-start` → Task 2 ✅
- RETARGET plugin metadata (claude/cursor) → Task 3 ✅; OpenCode injector → Task 2 ✅; codex/opencode install docs → Task 5 ✅
- DoD #1 inject → Tasks 2/6; #2 buyer language + #3 clarify-first + #4 fraud + #10 no-auto-contact → Task 6 manual checklist (behavioural; PR3 automates). Structural guarantees for the safety content live in Tasks 1 & 4 tests. ✅
- Order bootstrap → skills honoured (Task 1 before Task 4) ✅

**Placeholder scan:** No "TBD/TODO/handle appropriately". Every file's full content is given; every test has exact expected output. ✅

**Consistency:** Skill names match across the trigger table (Task 1), the injector markers (Task 2), and the skill tests (Tasks 1/4). The provider command string `tools/search-suppliers.sh extract` in `finding-suppliers` matches the spec §5.1 contract (the provider itself is built in PR2 — `finding-suppliers` only references it; nothing in PR1 executes it). `riskLevel/confidence/unknown/evidence` wording matches spec §4.3. ✅

**Known forward-reference (intentional):** `finding-suppliers` names `tools/search-suppliers.sh`, delivered in PR2. PR1 ships the skill text only; no PR1 test runs the command. This is the planned slice boundary, not a gap.
