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
