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
