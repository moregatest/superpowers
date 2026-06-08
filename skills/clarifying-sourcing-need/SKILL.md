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

`{ product, keywords[], destinationCountry, sourceCountries[], moq, certs[], targetPrice{min,max,currency}, leadTime }`

Stop asking once you have enough to search. Don't interrogate.
