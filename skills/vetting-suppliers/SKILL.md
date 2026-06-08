---
name: vetting-suppliers
description: Use when recommending or contacting any supplier - verify a manufacturer's legitimacy and screen for fraud signals before they reach the buyer
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
| high | No — only in the "⚠️ Caution / excluded" section, with reasons |
| unknown | No — excluded unless the buyer explicitly asks for manual follow-up |

Always attach **evidence** (source page URL + snippet) for every signal you cite.
