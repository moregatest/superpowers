# buyersuperpower PR4 — Playwright Extract Provider — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the real `playwright` supplier-search provider that, given official-site URLs, opens each site, finds up to 5 product pages, and extracts best-effort product data (title / specs / price-like / MOQ-like / image) into the §5.3 contract — split so the bug-prone HTML extraction is pure and fully tested offline, and Playwright is a thin browser-driver shell.

**Architecture:** Two modules. `lib/providers/extract.mjs` is **pure, dependency-free** HTML extraction (regex/string, "don't be clever") with a CLI for tests — it has NO Playwright import, so its fixture tests run with just `node`. `lib/providers/playwright.mjs` is the provider: it `import`s Playwright, drives the browser (per-site timeout + one retry + rate-limit, graceful per-site failure), and delegates all parsing to `extract.mjs`. It implements `extract` only (discovery is the agent's web search). `default_provider` stays `mock` (deterministic default); `playwright` is opt-in via `--provider playwright` or by editing the config. The browser path is verified live only where a browser is installable; the integration test SKIPs cleanly otherwise.

**Tech Stack:** Node ESM `.mjs`; the only npm dependency is `playwright` (declared in `package.json`, installed via `npm install && npx playwright install chromium`); bash + `jq` tests; the extractor tests need only `node` (no Playwright, no browser).

**Spec:** `docs/plans/2026-06-08-buyersuperpower-design.md` §5.3/§5.4, §7 (error handling), §13.1/§13.2 (PR4 scope). This plan implements **PR4 only**.

---

## File Structure

**Create:**
- `lib/providers/extract.mjs` — pure HTML extraction: `findProductLinks`, `extractProducts`, `extractCompanyInfo` + a test CLI. No deps.
- `lib/providers/playwright.mjs` — the provider: Playwright browser driver → delegates to `extract.mjs`; implements `extract`. Needs the `playwright` dep at runtime.
- `package.json` — declares the `playwright` dependency (no `"type"` field, so only `.mjs` is ESM; other `.js` untouched).
- `tests/buyersuperpower/fixtures/{home,products,thin}.html` — local HTML fixtures.
- `tests/buyersuperpower/test-extract.sh` — offline extractor tests (the core RED→GREEN; node + jq, no browser).
- `tests/buyersuperpower/test-playwright-provider.sh` — `node --check` both modules always; dispatcher routes `--provider playwright`; runs a real `file://` extract only if Playwright is installed, else SKIP.

**Modify:**
- `.gitignore` — add `node_modules/`.

**Reuse (unchanged):** `tools/search-suppliers.sh` already resolves `lib/providers/playwright.mjs` for `--provider playwright` (PR2 convention: provider value == filename stem). `tools/providers.config.yaml` keeps `default_provider: mock`.

**Out of scope for PR4:** `search`/`discover` in the Playwright provider (discovery is the agent's web search); the real Ready Market provider; anti-bot evasion; JS-heavy SPA rendering beyond `domcontentloaded`. Best-effort only: when a page lacks a spec/price/MOQ, emit `null` — never fabricate.

---

## Task 1: Pure HTML extractor (`extract.mjs`) + fixtures + offline tests

**Files:**
- Create: `lib/providers/extract.mjs`, `tests/buyersuperpower/fixtures/{home,products,thin}.html`, `tests/buyersuperpower/test-extract.sh`

- [ ] **Step 1: Create the three fixtures**

`tests/buyersuperpower/fixtures/home.html`:
```html
<!doctype html><html><head><title>Bright LED Manufacturing</title>
<meta name="description" content="LED work light manufacturer in Shenzhen since 2009."></head>
<body>
<nav>
  <a href="about.html">About Us</a>
  <a href="products.html">Our Products</a>
  <a href="https://twitter.com/x">Follow us</a>
</nav>
<h1>Bright LED Manufacturing Co., Ltd.</h1>
<p>Factory in Shenzhen since 2009.</p>
</body></html>
```

`tests/buyersuperpower/fixtures/products.html`:
```html
<!doctype html><html><head><title>LED Work Light 50W - Bright LED</title>
<meta name="description" content="50W IP65 LED work light, MOQ 500, CE certified."></head>
<body>
<h1>LED Work Light 50W (Model BL-50)</h1>
<img src="img/bl-50.jpg" alt="BL-50">
<p>Price: US$12.50 / unit (FOB Shenzhen)</p>
<p>MOQ: 500 pcs</p>
<table>
  <tr><th>Power</th><td>50W</td></tr>
  <tr><th>Voltage</th><td>110-240V</td></tr>
  <tr><th>IP Rating</th><td>IP65</td></tr>
</table>
</body></html>
```

`tests/buyersuperpower/fixtures/thin.html`:
```html
<!doctype html><html><head><title>Work Light</title></head><body>
<h1>Work Light</h1><p>Contact us for details.</p></body></html>
```

- [ ] **Step 2: Write the failing test**

Create `tests/buyersuperpower/test-extract.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. tests/buyersuperpower/assert.sh
F=tests/buyersuperpower/fixtures
X="node lib/providers/extract.mjs"

# links: product-ish links found, social/about excluded, returned absolute
L=$($X links "$F/home.html" "https://factory.example/") || fail "links run failed"
echo "$L" | jq -e 'type=="array" and length>=1' >/dev/null || fail "links: expected >=1"
echo "$L" | jq -e 'any(test("products\\.html$"))' >/dev/null || fail "links: products.html not found"
echo "$L" | jq -e 'all(startswith("https://factory.example/"))' >/dev/null || fail "links: not absolute"
echo "$L" | jq -e 'any(test("twitter|about"))|not' >/dev/null || fail "links: social/about leaked"

# products (rich page): name/price/moq/specs/image extracted
P=$($X products "$F/products.html" "https://factory.example/products.html") || fail "products run failed"
echo "$P" | jq -e '.[0].name|test("LED Work Light 50W")' >/dev/null || fail "product name"
echo "$P" | jq -e '.[0].priceHint|test("12\\.50")' >/dev/null || fail "price not extracted"
echo "$P" | jq -e '.[0].moq==500' >/dev/null || fail "moq != 500"
echo "$P" | jq -e '.[0].specs.Power=="50W"' >/dev/null || fail "specs.Power"
echo "$P" | jq -e '.[0].image=="https://factory.example/img/bl-50.jpg"' >/dev/null || fail "image not absolute"
echo "$P" | jq -e '.[0].evidence[0].type=="product_page"' >/dev/null || fail "evidence type"

# thin page: name present, price/moq null (NEVER fabricated)
T=$($X products "$F/thin.html" "https://factory.example/w") || fail "thin run failed"
echo "$T" | jq -e '.[0].priceHint==null and .[0].moq==null' >/dev/null || fail "thin: must be null, not fabricated"
pass "html extractor"
```

- [ ] **Step 3: Run it — verify RED**

Run: `bash tests/buyersuperpower/test-extract.sh`
Expected: `links run failed` (the module doesn't exist yet — `node` errors "Cannot find module .../extract.mjs").

- [ ] **Step 4: Create `lib/providers/extract.mjs`**

```javascript
#!/usr/bin/env node
// Dependency-free, best-effort HTML extraction for the playwright provider.
// First slice: find product-ish links and pull title / specs / price-like /
// MOQ-like / image from a page. "Don't be clever" — grab what's there, emit
// null when it isn't (never fabricate). Functions are imported by the provider;
// also runnable as a CLI for tests:
//   node extract.mjs links    <htmlfile> <baseUrl>
//   node extract.mjs products <htmlfile> <pageUrl>
//   node extract.mjs company  <htmlfile>
import fs from 'fs';
import { fileURLToPath } from 'url';

const PRODUCT_HINT = /(product|products|catalog|catalogue|solutions|goods|items)/i;

function absolute(href, base) { try { return new URL(href, base).href; } catch { return null; } }
function stripTags(s) { return s.replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ').trim(); }
function decode(s) {
  return s.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
          .replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&nbsp;/g, ' ');
}
function firstMatch(re, html) { const m = re.exec(html); return m ? decode(stripTags(m[1])) : null; }

export function findProductLinks(html, baseUrl, max = 5) {
  const out = [], seen = new Set();
  const re = /<a\b[^>]*\bhref\s*=\s*["']([^"']+)["'][^>]*>(.*?)<\/a>/gis;
  let m;
  while ((m = re.exec(html)) !== null) {
    const href = m[1], text = stripTags(m[2]);
    if (!PRODUCT_HINT.test(href) && !PRODUCT_HINT.test(text)) continue;
    const abs = absolute(decode(href), baseUrl);
    if (!abs || seen.has(abs)) continue;
    seen.add(abs); out.push(abs);
    if (out.length >= max) break;
  }
  return out;
}

export function extractProducts(html, pageUrl) {
  const title = firstMatch(/<title[^>]*>(.*?)<\/title>/is, html);
  const h1 = firstMatch(/<h1[^>]*>(.*?)<\/h1>/is, html);
  const name = h1 || title || null;
  if (!name) return [];

  const priceM = html.match(/(?:US\$|USD|RMB|CNY|EUR|\$|¥|€|£)\s?\d[\d,]*(?:\.\d+)?/i);
  const priceHint = priceM ? priceM[0].trim() : null;

  const moqM = html.match(/(?:MOQ|minimum\s+order(?:\s+quantity)?)\D{0,12}(\d[\d,]*)/i);
  const moq = moqM ? Number(moqM[1].replace(/,/g, '')) : null;

  const specs = {};
  const tableM = html.match(/<table[\s\S]*?<\/table>/i);
  if (tableM) {
    const rowRe = /<tr[^>]*>\s*<t[hd][^>]*>(.*?)<\/t[hd]>\s*<t[hd][^>]*>(.*?)<\/t[hd]>/gis;
    let r;
    while ((r = rowRe.exec(tableM[0])) !== null) {
      const k = decode(stripTags(r[1])), v = decode(stripTags(r[2]));
      if (k) specs[k] = v;
    }
  }

  const imgM = html.match(/<img\b[^>]*\bsrc\s*=\s*["']([^"']+)["']/i);
  const image = imgM ? absolute(decode(imgM[1]), pageUrl) : null;

  const evText = [name, priceHint, moqM ? moqM[0] : null].filter(Boolean).join(' | ').slice(0, 300);
  return [{
    name, specs, moq, priceHint, url: pageUrl, image,
    evidence: [{ type: 'product_page', url: pageUrl, text: evText || stripTags(html).slice(0, 200) }]
  }];
}

export function extractCompanyInfo(html) {
  const desc = firstMatch(/<meta[^>]*name=["']description["'][^>]*content=["']([^"']+)["']/i, html);
  return desc || firstMatch(/<title[^>]*>(.*?)<\/title>/is, html) || null;
}

const isMain = process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1];
if (isMain) {
  const [op, file, url] = process.argv.slice(2);
  const html = file ? fs.readFileSync(file, 'utf8') : '';
  let result;
  if (op === 'links') result = findProductLinks(html, url || 'http://example/');
  else if (op === 'products') result = extractProducts(html, url || 'http://example/p');
  else if (op === 'company') result = extractCompanyInfo(html);
  else { process.stderr.write("usage: extract.mjs <links|products|company> <htmlfile> [url]\n"); process.exit(2); }
  process.stdout.write(JSON.stringify(result, null, 2) + '\n');
}
```

- [ ] **Step 5: Run it — verify GREEN**

Run: `bash tests/buyersuperpower/test-extract.sh`
Expected: `PASS: html extractor`

- [ ] **Step 6: Commit**

```bash
git add lib/providers/extract.mjs tests/buyersuperpower/fixtures tests/buyersuperpower/test-extract.sh
git commit -m "feat(buyersuperpower): add dependency-free HTML product extractor + fixtures"
```

---

## Task 2: Playwright provider + package.json + integration test

**Files:**
- Create: `package.json`, `lib/providers/playwright.mjs`, `tests/buyersuperpower/test-playwright-provider.sh`
- Modify: `.gitignore`

- [ ] **Step 1: Write the failing test**

Create `tests/buyersuperpower/test-playwright-provider.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. tests/buyersuperpower/assert.sh

# always: both modules are valid JS
node --check lib/providers/extract.mjs   || fail "extract.mjs syntax error"
node --check lib/providers/playwright.mjs || fail "playwright.mjs syntax error"

# always: the PR2 dispatcher routes --provider playwright to this module
printf '%s' '["https://example.com"]' > /tmp/bsp-urls.json
if node -e "require.resolve('playwright')" 2>/dev/null; then
  : # installed — full path tested below
else
  # not installed: provider must fail cleanly (exit 3) with an actionable message,
  # which proves the dispatcher reached playwright.mjs
  err=$(tools/search-suppliers.sh extract --provider playwright --urls /tmp/bsp-urls.json 2>&1 >/dev/null; true)
  echo "$err" | grep -qi "playwright not installed" || fail "dispatcher did not route to playwright (got: $err)"
  echo "SKIP: playwright not installed — extractor is covered by test-extract.sh; run 'npm install && npx playwright install chromium' to exercise the browser path"
  pass "playwright provider (checks; integration skipped)"
  exit 0
fi

# installed: run a real extract over file:// fixtures and assert the §5.3 contract
F="$(pwd)/tests/buyersuperpower/fixtures"
printf '%s' "[\"file://$F/home.html\"]" > /tmp/bsp-urls.json
printf '%s' '{ "product":"LED work light" }' > /tmp/bsp-crit.json
OUT=$(BSP_RATE_MS=1 tools/search-suppliers.sh extract --provider playwright --urls /tmp/bsp-urls.json --criteria /tmp/bsp-crit.json) || fail "playwright extract failed"
echo "$OUT" | jq -e '.provider=="playwright"' >/dev/null || fail "provider field"
echo "$OUT" | jq -e '.suppliers|type=="array" and length==1' >/dev/null || fail "one supplier expected"
echo "$OUT" | jq -e '.suppliers[0].evidence|type=="array"' >/dev/null || fail "evidence array"
echo "$OUT" | jq -e '[.suppliers[0].products[].name]|any(test("LED Work Light 50W"))' >/dev/null || fail "did not extract the product via the browser"
pass "playwright provider (integration)"
```

- [ ] **Step 2: Run it — verify RED**

Run: `bash tests/buyersuperpower/test-playwright-provider.sh`
Expected: `playwright.mjs syntax error` (the module and `package.json` don't exist yet; `node --check` on a missing file errors).

- [ ] **Step 3: Create `package.json`**

```json
{
  "name": "buyersuperpower",
  "version": "0.1.0",
  "private": true,
  "description": "buyersuperpower supplier-search providers (Playwright extract)",
  "dependencies": {
    "playwright": "^1.48.0"
  }
}
```

- [ ] **Step 4: Add `node_modules/` to `.gitignore`**

Append `node_modules/` as a new line to `.gitignore`.

- [ ] **Step 5: Create `lib/providers/playwright.mjs`**

```javascript
#!/usr/bin/env node
// Playwright supplier-search provider (the default for live search; opt-in via
// --provider playwright until you flip default_provider). First slice: `extract`
// only — given official-site URLs, open each, find up to N product pages, and
// pull best-effort product data via ./extract.mjs. Output conforms to §5.3.
// Requires: npm install && npx playwright install chromium.
import fs from 'fs';
import { findProductLinks, extractProducts, extractCompanyInfo } from './extract.mjs';

function parseArgs(argv) {
  const a = { op: argv[2] || '', criteria: null, urls: null };
  for (let i = 3; i < argv.length; i++) {
    if (argv[i] === '--criteria') a.criteria = argv[++i];
    else if (argv[i] === '--urls') a.urls = argv[++i];
  }
  return a;
}
function readJson(p) { if (!p) return null; try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch { return null; } }
const num = (env, def) => { const v = Number(process.env[env]); return Number.isFinite(v) && v > 0 ? v : def; };
const TIMEOUT = num('BSP_TIMEOUT_MS', 20000);
const MAX_PAGES = num('BSP_MAX_PAGES', 5);
const RATE = num('BSP_RATE_MS', 1500);
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const emit = (o) => process.stdout.write(JSON.stringify(o, null, 2) + '\n');

async function loadHtml(page, url) {
  for (let attempt = 0; attempt < 2; attempt++) {
    try { await page.goto(url, { timeout: TIMEOUT, waitUntil: 'domcontentloaded' }); return await page.content(); }
    catch (e) { if (attempt === 1) throw e; await sleep(500); }
  }
}

async function main() {
  const args = parseArgs(process.argv);
  if (args.op !== 'extract') {
    emit({ provider: 'playwright', suppliers: [], notes: `playwright implements 'extract' only (got '${args.op}'); discovery is the agent's web search.` });
    return;
  }
  const urls = readJson(args.urls);
  if (!Array.isArray(urls) || urls.length === 0) {
    emit({ provider: 'playwright', suppliers: [], notes: 'extract requires --urls with a non-empty JSON array of official-site URLs.' });
    return;
  }
  let chromium;
  try { ({ chromium } = await import('playwright')); }
  catch { process.stderr.write('playwright not installed. Run: npm install && npx playwright install chromium\n'); process.exit(3); }

  const browser = await chromium.launch({ headless: true });
  const suppliers = [];
  try {
    const ctx = await browser.newContext({ userAgent: process.env.BSP_UA || 'Mozilla/5.0 (compatible; buyersuperpower/0.1)' });
    for (const site of urls) {
      const s = { name: null, officialSite: site, country: null, companyInfo: null, evidence: [], products: [], extractionNotes: '' };
      const page = await ctx.newPage();
      try {
        const home = await loadHtml(page, site);
        s.companyInfo = extractCompanyInfo(home);
        s.name = s.companyInfo;
        s.evidence.push({ type: 'home_page', url: site, text: (s.companyInfo || '').slice(0, 200) });
        const links = findProductLinks(home, site, MAX_PAGES);
        const pages = (links.length ? links : [site]).slice(0, MAX_PAGES);
        for (const pu of pages) {
          await sleep(RATE);
          try { s.products.push(...extractProducts(await loadHtml(page, pu), pu)); }
          catch (e) { s.extractionNotes += `could not load ${pu}: ${e.message}; `; }
        }
      } catch (e) {
        s.extractionNotes += `could not load site ${site}: ${e.message} (recorded for manual check); `;
      } finally {
        await page.close();
      }
      suppliers.push(s);
    }
  } finally {
    await browser.close();
  }
  emit({ provider: 'playwright', suppliers, notes: `playwright extract over ${urls.length} site(s)` });
}
main().catch(e => { process.stderr.write(String((e && e.stack) || e) + '\n'); process.exit(1); });
```

- [ ] **Step 6: Run it — verify GREEN (SKIP path here, since Playwright isn't installed)**

Run: `bash tests/buyersuperpower/test-playwright-provider.sh`
Expected (no Playwright installed): prints the `SKIP: playwright not installed …` line then `PASS: playwright provider (checks; integration skipped)`. (Where Playwright IS installed, it instead prints `PASS: playwright provider (integration)`.)

- [ ] **Step 7: Commit**

```bash
git add package.json .gitignore lib/providers/playwright.mjs tests/buyersuperpower/test-playwright-provider.sh
git commit -m "feat(buyersuperpower): add Playwright extract provider (opt-in, browser-driver shell)"
```

---

## Task 3: PR4 verification

**Files:** none (verification only)

- [ ] **Step 1: Full buyersuperpower suite (now 10)**

Run:
```bash
for t in bootstrap injectors metadata skills mock-provider dispatcher readymarket-stub benchmark-seeds extract playwright-provider; do
  echo "== $t =="; bash tests/buyersuperpower/test-$t.sh || exit 1
done
```
Expected: ten test groups, each ending `PASS:` (test-playwright-provider may print a `SKIP:` line before its PASS); exit 0.

- [ ] **Step 2: Confirm the dispatcher routes to the real provider, and default stays mock**

Run:
```bash
grep -E '^default_provider:' tools/providers.config.yaml   # expect: default_provider: mock
ls lib/providers/                                          # expect: extract.mjs mock.mjs playwright.mjs readymarket-api.mjs
node --check lib/providers/playwright.mjs && echo "playwright.mjs OK"
```
Expected: default is `mock`; all four providers present; `playwright.mjs OK`.

- [ ] **Step 3: Confirm node_modules is ignored (so a future `npm install` won't pollute git)**

Run: `git check-ignore node_modules || echo "NOT IGNORED"`
Expected: prints `node_modules` (it is ignored).

---

## Self-Review

**Spec coverage (design §5.3/§5.4, §7, §13.1/§13.2):**
- `lib/providers/playwright.mjs`, `package.json`, fixture tests, timeout/retry/rate-limit → Tasks 1–2 ✅
- §13.2 scope: open site → find `product/products/catalog/solutions` links → ≤5 pages → extract title/h1/table/price-like/MOQ-like/image → §5.3 JSON; missing → `null` (thin-fixture test) ✅
- §7 error handling: per-site timeout + one retry + rate-limit; a failed page/site is recorded in `extractionNotes` and does NOT abort the batch ✅
- "extract only; discovery is the agent's" → non-`extract` ops return an explanatory empty result ✅
- Testability: the bug-prone extraction is pure + fully covered offline; the browser path is a thin shell, integration-tested where a browser exists and SKIP-guarded otherwise ✅

**Placeholder scan:** No TBD/TODO; every module, fixture, and test is complete; exact expected outputs given. ✅

**Consistency:** Provider value `playwright` resolves to `playwright.mjs` (PR2 dispatcher convention); output shape (`provider`/`suppliers[]` with `name`/`officialSite`/`evidence[]`/`products[]` each with `evidence[]`/`notes`) matches §5.3, mock, and the stub. `extract.mjs` CLI ops (`links`/`products`/`company`) match what `test-extract.sh` invokes and what `playwright.mjs` imports. ✅

**Scope:** Only `extract` implemented; `default_provider` unchanged (`mock`); one new dependency (`playwright`, gitignored `node_modules/`); no anti-bot/SPA work. ✅
