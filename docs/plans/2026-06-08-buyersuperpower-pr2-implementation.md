# buyersuperpower PR2 — Provider Contract & Mock — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the pluggable supplier-search provider layer with a deterministic `mock` provider (and a `readymarket-api` stub), so the agent's skills and the PR3 benchmark can run offline against stable, evidence-bearing supplier JSON — with no Playwright and no network.

**Architecture:** A thin bash dispatcher (`tools/search-suppliers.sh`) reads `default_provider` from `tools/providers.config.yaml` (overridable with `--provider`), then runs `node lib/providers/<provider>.mjs <op> [args]` and passes the JSON through. The `mock` provider returns a fixed 3-tier supplier set (clean / fraud-pattern / thin-data) so all of low/high/unknown risk get exercised downstream. Output conforms to the provider contract in the design doc §5.3. Providers are dependency-free Node ESM (`.mjs`); the dispatcher is bash-3.2-safe (macOS default).

**Tech Stack:** Bash (dispatcher + tests), Node ESM `.mjs` (providers, no npm deps), `jq` (contract assertions), `tests/buyersuperpower/assert.sh` (existing helpers from PR1).

**Spec:** `docs/plans/2026-06-08-buyersuperpower-design.md` §5 (provider contract) and §13.1 (PR2). This plan implements **PR2 only**.

---

## File Structure

**Create:**
- `lib/providers/mock.mjs` — deterministic mock provider; implements `extract` + `search`; returns the fixed 3-tier supplier set with evidence
- `lib/providers/readymarket-api.mjs` — stub provider; conforms to the CLI/contract, returns empty suppliers + a "not implemented" note
- `tools/providers.config.yaml` — provider config; `default_provider: mock` (flips to `playwright` in PR4)
- `tools/search-suppliers.sh` — dispatcher: select provider, run it, pass JSON through
- `tests/buyersuperpower/test-mock-provider.sh` — tests the mock provider directly (`node lib/providers/mock.mjs …`)
- `tests/buyersuperpower/test-dispatcher.sh` — tests provider selection + the §13.1 acceptance commands end-to-end through the dispatcher
- `tests/buyersuperpower/test-readymarket-stub.sh` — tests the stub conforms and flags not-implemented

**Reuse (unchanged):** `tests/buyersuperpower/assert.sh` (PR1 helpers).

**Out of scope for PR2 (later PRs):** `lib/providers/playwright.mjs` and `package.json` (PR4); benchmark seed retarget (PR3); any real network/scraping or real Ready Market API.

**Provider contract (design §5.3) — the JSON every provider emits to stdout:**
```jsonc
{ "provider": "mock",
  "suppliers": [
    { "name": "...", "officialSite": "https://...", "country": "CN|null",
      "companyInfo": "...",
      "evidence": [ { "type": "contact_page", "url": "https://...", "text": "..." } ],
      "products": [ { "name": "...", "specs": {}, "moq": 500, "priceHint": "...",
                      "url": "https://...", "image": "https://...|null",
                      "evidence": [ { "type": "product_page", "url": "https://...", "text": "..." } ] } ],
      "extractionNotes": "..." } ],
  "notes": "..." }
```

**Dispatcher CLI:** `tools/search-suppliers.sh <extract|search> [--provider NAME] [--criteria FILE] [--urls FILE]`

---

## Task 1: `mock` provider

**Files:**
- Create: `lib/providers/mock.mjs`
- Create: `tests/buyersuperpower/test-mock-provider.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/buyersuperpower/test-mock-provider.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. tests/buyersuperpower/assert.sh

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/criteria.json" <<'JSON'
{ "product": "LED work light", "keywords": ["LED","work light"], "destinationCountry": "MX",
  "sourceCountries": ["CN"], "moq": 500, "certs": ["NOM"],
  "targetPrice": { "min": 8, "max": 15, "currency": "USD" }, "limit": 10 }
JSON
cat > "$TMP/urls.json" <<'JSON'
["https://example-brightled.com","https://globaldeal-trading.tk"]
JSON

# contract-shape checker (design §5.3)
assert_contract() { # JSON expected_provider
  echo "$1" | jq -e . >/dev/null 2>&1 || fail "not valid JSON"
  echo "$1" | jq -e --arg p "$2" '.provider==$p' >/dev/null || fail "provider != $2"
  echo "$1" | jq -e 'has("notes")' >/dev/null || fail "missing notes"
  echo "$1" | jq -e '.suppliers|type=="array"' >/dev/null || fail "suppliers not array"
  echo "$1" | jq -e '.suppliers|all(.name and .officialSite and (.evidence|type=="array") and (.products|type=="array"))' >/dev/null || fail "supplier missing required fields"
  echo "$1" | jq -e '[.suppliers[].products[]]|all(.evidence|type=="array")' >/dev/null || fail "product missing evidence array"
}

# search op
OUT=$(node lib/providers/mock.mjs search --criteria "$TMP/criteria.json") || fail "mock search exited non-zero"
assert_contract "$OUT" "mock"
[ "$(echo "$OUT" | jq '.suppliers|length')" -eq 3 ] || fail "expected 3 mock suppliers"

# extract op (consumes urls)
OUT2=$(node lib/providers/mock.mjs extract --urls "$TMP/urls.json" --criteria "$TMP/criteria.json") || fail "mock extract exited non-zero"
assert_contract "$OUT2" "mock"

# 3 risk tiers present (so PR3 anti-fraud / anti-bullshit have material)
echo "$OUT" | jq -e '[.suppliers[].evidence[].text]|any(test("personal account"))' >/dev/null || fail "missing fraud signal: personal account"
echo "$OUT" | jq -e '[.suppliers[].evidence[].text]|any(test("gmail"))' >/dev/null || fail "missing fraud signal: free email"
echo "$OUT" | jq -e 'any(.suppliers[].products[]; .moq==null)' >/dev/null || fail "missing thin/unknown supplier (null moq)"
pass "mock provider"
```

- [ ] **Step 2: Run it — verify RED**

Run: `bash tests/buyersuperpower/test-mock-provider.sh`
Expected: fails at the first `node lib/providers/mock.mjs …` with a Node "Cannot find module …/mock.mjs" error → `ASSERT FAIL: mock search exited non-zero`.

- [ ] **Step 3: Create `lib/providers/mock.mjs`**

```javascript
#!/usr/bin/env node
// Mock supplier-search provider for buyersuperpower.
// Returns a FIXED, deterministic 3-tier supplier set (clean / fraud-pattern /
// thin-data) so skills and the PR3 benchmark can run offline. Implements both
// ops: `extract` (urls + criteria) and `search` (criteria). Output conforms to
// the provider contract (design doc §5.3). No dependencies.

import fs from 'fs';

function parseArgs(argv) {
  const a = { op: argv[2] || '', criteria: null, urls: null };
  for (let i = 3; i < argv.length; i++) {
    if (argv[i] === '--criteria') a.criteria = argv[++i];
    else if (argv[i] === '--urls') a.urls = argv[++i];
  }
  return a;
}
function readJson(p) {
  if (!p) return null;
  try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch { return null; }
}

// One clean supplier (low-risk signals), one fraud-pattern (high-risk), one thin (unknown).
const SUPPLIERS = [
  {
    name: 'Bright LED Manufacturing Co., Ltd.',
    officialSite: 'https://example-brightled.com',
    country: 'CN',
    companyInfo: 'Established 2009. Own factory in Shenzhen. ISO9001 certified.',
    evidence: [
      { type: 'contact_page', url: 'https://example-brightled.com/contact',
        text: "Address: Building 5, Bao'an District, Shenzhen, China. Tel: +86-755-1234-5678. Email: sales@example-brightled.com" },
      { type: 'cert_page', url: 'https://example-brightled.com/certs',
        text: 'ISO9001, CE, RoHS certificates available on request.' }
    ],
    products: [
      { name: 'LED Work Light 50W', specs: { watt: 50, voltage: '110-240V', ip: 'IP65' },
        moq: 500, priceHint: 'US$12-15 / unit (FOB Shenzhen)',
        url: 'https://example-brightled.com/products/bl-50',
        image: 'https://example-brightled.com/img/bl-50.jpg',
        evidence: [ { type: 'product_page', url: 'https://example-brightled.com/products/bl-50',
          text: 'Model BL-50. 50W. IP65. MOQ 500 pcs. CE certified.' } ] }
    ],
    extractionNotes: 'Clean manufacturer profile with address, certs, and specced product.'
  },
  {
    name: 'GlobalDeal Trading',
    officialSite: 'https://globaldeal-trading.tk',
    country: null,
    companyInfo: 'Best prices in the market — up to 80% below competitors!',
    evidence: [
      { type: 'contact_page', url: 'https://globaldeal-trading.tk/contact',
        text: 'Contact: globaldeal2024@gmail.com. Payment: 100% T/T in advance to personal account holder Mr. Lee.' }
    ],
    products: [
      { name: 'LED Work Light 50W', specs: {},
        moq: 1, priceHint: 'US$2 / unit',
        url: 'https://globaldeal-trading.tk/p/led',
        image: 'https://globaldeal-trading.tk/img/stock-led.jpg',
        evidence: [ { type: 'product_page', url: 'https://globaldeal-trading.tk/p/led',
          text: 'US$2 each. Pay deposit to personal account. No certificates listed.' } ] }
    ],
    extractionNotes: 'Fraud signals: free email, payment to a personal account, .tk domain, price far below market.'
  },
  {
    name: 'Sunrise Lighting',
    officialSite: 'https://sunrise-lighting.example',
    country: null,
    companyInfo: 'Lighting products.',
    evidence: [
      { type: 'home_page', url: 'https://sunrise-lighting.example',
        text: 'We sell lighting. Contact us for details.' }
    ],
    products: [
      { name: 'Work Light', specs: {}, moq: null, priceHint: null,
        url: 'https://sunrise-lighting.example/work-light', image: null, evidence: [] }
    ],
    extractionNotes: 'Thin data: no address, no MOQ, no price, no certifications stated on site.'
  }
];

const args = parseArgs(process.argv);
const criteria = readJson(args.criteria);
let urlsCount = 0;
if (args.urls) { const u = readJson(args.urls); urlsCount = Array.isArray(u) ? u.length : 0; }

const notes = args.op === 'extract'
  ? `mock provider: extract op, received ${urlsCount} url(s); returning fixed 3-tier dataset.`
  : `mock provider: search op${criteria && criteria.product ? ` for "${criteria.product}"` : ''}; returning fixed 3-tier dataset.`;

process.stdout.write(JSON.stringify({ provider: 'mock', suppliers: SUPPLIERS, notes }, null, 2) + '\n');
```

- [ ] **Step 4: Run it — verify GREEN**

Run: `bash tests/buyersuperpower/test-mock-provider.sh`
Expected: `PASS: mock provider`

- [ ] **Step 5: Commit**

```bash
git add lib/providers/mock.mjs tests/buyersuperpower/test-mock-provider.sh
git commit -m "feat(buyersuperpower): add mock supplier-search provider (3 risk tiers)"
```

---

## Task 2: config + dispatcher (`search-suppliers.sh`)

**Files:**
- Create: `tools/providers.config.yaml`
- Create: `tools/search-suppliers.sh`
- Create: `tests/buyersuperpower/test-dispatcher.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/buyersuperpower/test-dispatcher.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. tests/buyersuperpower/assert.sh

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/criteria.json" <<'JSON'
{ "product": "LED work light", "destinationCountry": "MX", "moq": 500 }
JSON
cat > "$TMP/urls.json" <<'JSON'
["https://example-brightled.com"]
JSON

# the two §13.1 acceptance commands produce valid contract JSON via the default provider (mock)
OUT=$(tools/search-suppliers.sh extract --urls "$TMP/urls.json" --criteria "$TMP/criteria.json") || fail "extract exited non-zero"
echo "$OUT" | jq -e '.provider=="mock" and (.suppliers|type=="array")' >/dev/null || fail "extract: not mock contract JSON"
OUT=$(tools/search-suppliers.sh search --criteria "$TMP/criteria.json") || fail "search exited non-zero"
echo "$OUT" | jq -e '.provider=="mock" and (.suppliers|length==3)' >/dev/null || fail "search: not mock contract JSON"

# --provider override is honored
echo "$OUT" | jq -e '.provider=="mock"' >/dev/null || fail "default provider should be mock"

# bad op rejected
if tools/search-suppliers.sh frobnicate --criteria "$TMP/criteria.json" >/dev/null 2>&1; then fail "bad op should exit non-zero"; fi
# unknown provider rejected
if tools/search-suppliers.sh search --provider nope --criteria "$TMP/criteria.json" >/dev/null 2>&1; then fail "unknown provider should exit non-zero"; fi
pass "dispatcher"
```

- [ ] **Step 2: Run it — verify RED**

Run: `bash tests/buyersuperpower/test-dispatcher.sh`
Expected: fails at the first command (`tools/search-suppliers.sh` does not exist) → `ASSERT FAIL: extract exited non-zero`.

- [ ] **Step 3: Create `tools/providers.config.yaml`**

```yaml
# buyersuperpower supplier-search provider config.
# default_provider: which provider tools/search-suppliers.sh uses when no
# --provider flag is given. PR2 ships `mock`; PR4 flips this to `playwright`.
default_provider: mock

# Playwright provider settings (read from PR4 onward; ignored until then).
playwright:
  headless: true
  perSiteTimeoutMs: 20000
  maxPagesPerSite: 5
  rateLimitMs: 1500

# Discovery: marketplace/directory domains the finding-suppliers skill filters
# OUT when searching for official sites (informational in PR2).
discovery:
  platformBlocklist:
    - alibaba.com
    - made-in-china.com
    - globalsources.com
```

- [ ] **Step 4: Create `tools/search-suppliers.sh`**

```bash
#!/usr/bin/env bash
# buyersuperpower supplier-search dispatcher.
# Usage: search-suppliers.sh <extract|search> [--provider NAME] [--criteria FILE] [--urls FILE]
# Selects a provider (--provider, else default_provider from providers.config.yaml),
# runs lib/providers/<provider>.mjs with the op + remaining args, and passes its
# JSON through on stdout. Relative --criteria/--urls paths resolve against the
# caller's cwd (node is run without changing directory). Bash-3.2 safe.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG="${REPO_ROOT}/tools/providers.config.yaml"

die() { echo "search-suppliers: $1" >&2; exit 2; }

op="${1:-}"
case "$op" in
  extract|search) shift ;;
  *) die "first argument must be 'extract' or 'search' (got '${op}')" ;;
esac

provider=""
passthru=()
while [ $# -gt 0 ]; do
  case "$1" in
    --provider) provider="${2:-}"; shift 2 ;;
    *) passthru+=("$1"); shift ;;
  esac
done

if [ -z "$provider" ]; then
  provider="$(grep -E '^default_provider:' "$CONFIG" 2>/dev/null | head -1 | sed -E 's/^default_provider:[[:space:]]*//; s/[[:space:]]*$//')"
  [ -n "$provider" ] || die "no --provider given and default_provider not found in ${CONFIG}"
fi

script="${REPO_ROOT}/lib/providers/${provider}.mjs"
[ -f "$script" ] || die "unknown provider '${provider}' (no such file: ${script})"

# ${passthru[@]+...} keeps this safe under `set -u` with an empty array on bash 3.2.
exec node "$script" "$op" ${passthru[@]+"${passthru[@]}"}
```

- [ ] **Step 5: Make the dispatcher executable**

Run: `chmod +x tools/search-suppliers.sh`

- [ ] **Step 6: Run it — verify GREEN**

Run: `bash tests/buyersuperpower/test-dispatcher.sh`
Expected: `PASS: dispatcher`

- [ ] **Step 7: Commit**

```bash
git add tools/providers.config.yaml tools/search-suppliers.sh tests/buyersuperpower/test-dispatcher.sh
git commit -m "feat(buyersuperpower): add provider config + search-suppliers dispatcher"
```

---

## Task 3: `readymarket-api` stub

**Files:**
- Create: `lib/providers/readymarket-api.mjs`
- Create: `tests/buyersuperpower/test-readymarket-stub.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/buyersuperpower/test-readymarket-stub.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. tests/buyersuperpower/assert.sh

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
echo '{ "product": "LED work light" }' > "$TMP/criteria.json"

OUT=$(tools/search-suppliers.sh search --provider readymarket-api --criteria "$TMP/criteria.json") || fail "stub exited non-zero"
echo "$OUT" | jq -e . >/dev/null 2>&1 || fail "stub output not valid JSON"
echo "$OUT" | jq -e '.provider=="readymarket-api"' >/dev/null || fail "stub provider field wrong"
echo "$OUT" | jq -e '.suppliers|length==0' >/dev/null || fail "stub should return empty suppliers"
echo "$OUT" | jq -e '.notes|test("not implemented")' >/dev/null || fail "stub should note not-implemented"
pass "readymarket-api stub"
```

- [ ] **Step 2: Run it — verify RED**

Run: `bash tests/buyersuperpower/test-readymarket-stub.sh`
Expected: dispatcher reports unknown provider (file missing) → `ASSERT FAIL: stub exited non-zero`.

- [ ] **Step 3: Create `lib/providers/readymarket-api.mjs`**

```javascript
#!/usr/bin/env node
// Ready Market API provider — STUB (design doc §5.4).
// Conforms to the provider CLI/contract but is not implemented yet. When
// implemented, `search(criteria)` should query the Ready Market supplier DB and
// return suppliers in the same shape as the mock/playwright providers (§5.3).

const op = process.argv[2] || '';
process.stdout.write(JSON.stringify({
  provider: 'readymarket-api',
  suppliers: [],
  notes: `readymarket-api provider not implemented yet (stub). Requested op: '${op}'. Implement against the Ready Market supplier DB to enable.`
}, null, 2) + '\n');
```

- [ ] **Step 4: Run it — verify GREEN**

Run: `bash tests/buyersuperpower/test-readymarket-stub.sh`
Expected: `PASS: readymarket-api stub`

- [ ] **Step 5: Commit**

```bash
git add lib/providers/readymarket-api.mjs tests/buyersuperpower/test-readymarket-stub.sh
git commit -m "feat(buyersuperpower): add readymarket-api provider stub"
```

---

## Task 4: PR2 acceptance verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full buyersuperpower suite (PR1 + PR2)**

Run:
```bash
for t in bootstrap injectors metadata skills mock-provider dispatcher readymarket-stub; do
  echo "== $t =="; bash tests/buyersuperpower/test-$t.sh || exit 1
done
```
Expected: seven `PASS:` lines, exit 0.

- [ ] **Step 2: Confirm the §13.1 acceptance commands by hand**

Run:
```bash
printf '%s' '{ "product":"LED work light","destinationCountry":"MX","moq":500 }' > /tmp/crit.json
printf '%s' '["https://example-brightled.com"]' > /tmp/urls.json
tools/search-suppliers.sh extract --urls /tmp/urls.json --criteria /tmp/crit.json | jq -e '.provider=="mock" and (.suppliers[0].evidence|type=="array")'
tools/search-suppliers.sh search --criteria /tmp/crit.json | jq -e '.suppliers|length==3'
```
Expected: both `jq -e` print `true` and exit 0 (each supplier and product carries an `evidence` array per the contract).

- [ ] **Step 3: Confirm no PR4/network scope crept in**

Run: `ls lib/providers/ && ! test -f package.json && echo "no package.json (correct for PR2)"`
Expected: lists `mock.mjs` and `readymarket-api.mjs` only (no `playwright.mjs`); prints the no-package.json confirmation.

---

## Self-Review

**Spec coverage (design §5 + §13.1 PR2):**
- `tools/search-suppliers.sh` (dispatcher, `extract`/`search` ops) → Task 2 ✅
- `tools/providers.config.yaml` (`default_provider`) → Task 2 ✅
- `lib/providers/mock.mjs` (extract + search, evidence-bearing) → Task 1 ✅
- `lib/providers/readymarket-api.mjs` (stub) → Task 3 ✅
- provider contract tests → Tasks 1–3 tests + Task 4 acceptance ✅
- §13.1 acceptance commands (`extract --urls --criteria`, `search --criteria`) emit §5.3 JSON with evidence → Task 4 ✅
- 3-risk-tier mock data (low/high/unknown — the refinement) → Task 1 asserts fraud + thin signals ✅

**Placeholder scan:** No TBD/TODO. Every file's full content is given; every test states exact expected output. ✅

**Type/contract consistency:** The contract shape (`provider`, `suppliers[]` with `name/officialSite/evidence[]/products[]`, each product with `evidence[]`, `notes`) is identical across mock output (Task 1), the dispatcher tests (Task 2), the stub (Task 3, empty `suppliers[]` is a valid instance), and the design §5.3. The dispatcher CLI (`<op> [--provider] [--criteria] [--urls]`) matches what every test invokes and what `finding-suppliers` (PR1) references (`search-suppliers.sh extract --urls … --criteria …`). ✅

**Scope:** No `playwright.mjs`, no `package.json`, no network — all deferred to PR4 and asserted absent in Task 4 Step 3. ✅
