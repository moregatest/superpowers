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
