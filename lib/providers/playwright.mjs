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
