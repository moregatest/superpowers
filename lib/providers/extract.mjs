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

  // Scan visible text (tags stripped) so script/attribute noise can't pose as data.
  const text = decode(stripTags(html));
  // Prefer an explicit currency (US$/USD/RMB…) over a bare symbol, so a stray
  // "$5" coupon can't win over the real "US$12.50".
  const priceM = text.match(/(?:US\$|USD|RMB|CNY|EUR|GBP|HKD)\s?\d[\d,]*(?:\.\d+)?/i)
              || text.match(/(?:\$|¥|€|£)\s?\d[\d,]*(?:\.\d+)?/);
  const priceHint = priceM ? priceM[0].trim() : null;

  // Require the quantity right after MOQ (only :, =, "is", "of" may intervene) —
  // a loose gap would grab an unrelated number (e.g. a voltage). null beats wrong.
  const moqM = text.match(/(?:MOQ|minimum\s+order(?:\s+quantity)?)\s*(?:is|of|[:=])?\s*(\d[\d,]*)\b/i);
  const moq = moqM ? Number(moqM[1].replace(/,/g, '')) : null;

  const specs = {};
  const tableM = html.match(/<table[\s\S]*?<\/table>/i);
  if (tableM) {
    // Best-effort: assumes 2-cell key/value rows; rows of other shapes are skipped.
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
