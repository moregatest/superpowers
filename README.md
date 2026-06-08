# buyersuperpower

**buyersuperpower turns your AI agent into an international sourcing advisor for B2B buyers.**

Tell it what you want to source. It clarifies the need, finds real supplier *official sites*, screens them for fraud, hands you a sourcing report, and drafts your inquiry — in your language, and **without ever contacting a supplier or paying anyone without your say-so**.

It's built on [Superpowers](https://github.com/obra/superpowers) (MIT, by Jesse Vincent): the same auto-triggering "skills" mechanism, retargeted from software development to international procurement.

> **Status: early development.** The identity layer and the first four skills have shipped (PR1). Live supplier search (Playwright) and the evaluation benchmark land in later slices — see [Roadmap](#roadmap).

## How it works

The moment a session starts, a hook injects the `using-buyersuperpower` bootstrap, so your agent behaves as a sourcing advisor from the very first message. As you describe a buying need, it triggers the right skill automatically — you don't do anything special:

1. **clarifying-sourcing-need** — pins down product & specs, quantity (MOQ), destination country, required certifications (CE / FCC / NOM / UKCA…), target price, and lead time. One question at a time, *before* searching.
2. **finding-suppliers** — uses web search to find real manufacturer **official sites** (filtering out marketplaces and directories), extracts promising products, applies vetting, and produces a **sourcing report**.
3. **vetting-suppliers** — screens every supplier for fraud (no physical address, free-email-only contact, brand-new domain, too-good-to-be-true prices, payment to a *personal* account…) and assigns a `riskLevel` + a separate `confidence`. High- or unknown-risk suppliers **never** reach your recommended list.
4. **placing-order** — drafts an English inquiry / RFQ for the suppliers you choose. It **never** contacts anyone or pays anything without your explicit confirmation.

It detects the buyer's language and runs the whole conversation in it, shows key trade terms bilingually, and refuses to invent data a supplier's site doesn't actually state.

## Safety first (these buyers may be new to trade)

- **Clarify before acting** — no searching or recommending on a vague request.
- **Protect proactively** — actively screen for fraud and warn you.
- **Never invent** — "not stated on site", never a guessed MOQ or price.
- **Confirm before outreach** — never contacts a supplier, sends an inquiry, or places an order without your explicit OK.
- **Never auto-pays**, and never leaks your data.

## What's inside (PR1)

- **Bootstrap:** `skills/using-buyersuperpower/` — the advisor persona, the five safety rules, the language rule, and the skill-trigger table.
- **Skills:** `clarifying-sourcing-need`, `finding-suppliers`, `vetting-suppliers`, `placing-order`.
- **Identity:** both injectors retargeted (the Claude Code / Cursor `hooks/session-start` and the OpenCode plugin); plugin metadata is `buyersuperpower 0.1.0` across Claude Code, Cursor, Codex, and OpenCode.
- **Tests:** `tests/buyersuperpower/` — a structural suite that boots the hook, validates the manifests, and locks the safety-critical content of every skill.

Design and plan: [`docs/plans/2026-06-08-buyersuperpower-design.md`](docs/plans/2026-06-08-buyersuperpower-design.md) and [`docs/plans/2026-06-08-buyersuperpower-pr1-implementation.md`](docs/plans/2026-06-08-buyersuperpower-pr1-implementation.md).

## Roadmap

The supplier search is designed as a **pluggable provider** behind one JSON contract, so the agent's skills never change when the backend does:

- **PR2** — the provider contract + a `mock` provider (`tools/search-suppliers.sh`, `lib/providers/mock.mjs`) returning evidence-bearing supplier JSON, so skill behaviour can be tested without hitting the network.
- **PR3** — retarget the benchmark seeds (`sourcing-compliance`, `anti-fraud`, `anti-bullshit`, `sourcing-quality`, `reasoning`), run on the mock provider, to verify the safety behaviours automatically.
- **PR4** — the default **Playwright** provider: open official sites and extract products. A Ready Market supplier-data provider can later slot in behind the same contract.

## Installation

buyersuperpower is in active development and **not yet published as its own marketplace plugin**. For now, run it from this repository:

```bash
git clone https://github.com/moregatest/superpowers.git buyersuperpower
```

- **Codex / OpenCode:** follow [`.codex/INSTALL.md`](.codex/INSTALL.md) or [`.opencode/INSTALL.md`](.opencode/INSTALL.md), pointing the clone at your local checkout. (Those docs still reference the upstream repo path until buyersuperpower is published separately.)
- **Claude Code / Cursor:** load this directory as a local plugin. A public marketplace entry will come once the project graduates from early development.

Verify by starting a session and describing something to source (e.g. *"I want to import LED work lights to Mexico, ~500/month"*) — the agent should start asking clarifying questions rather than guessing.

## Credits

Built on **[Superpowers](https://github.com/obra/superpowers)** by Jesse Vincent — the auto-triggering skills architecture, the cross-platform packaging, and the benchmark pipeline all come from that project. If it's useful to you, consider [sponsoring his open-source work](https://github.com/sponsors/obra).

## License

MIT — see [LICENSE](LICENSE).
