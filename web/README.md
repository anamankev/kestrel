# Kestrel for the web

The same terminal in the browser: React + TypeScript + Vite, with the iPad/Mac app's core logic ported
(symbol resolution, command parser, decoders, indicators) and its tests ported alongside.

```
npm install
npm run relay   # Cloudflare Worker relay on :8787 (needs worker/.dev.vars with SEC_CONTACT=you@example.com)
npm run dev     # app on :5173
npm test        # core + relay tests
```

**Relay (`worker/`).** Browsers can't call Yahoo, SEC's ticker list or the French Data Library directly (no CORS;
the SEC also requires a contact User-Agent). The relay forwards only an allowlisted set of read-only routes, validates
every path and query value, answers only Kestrel's own origins, rate-limits per visitor and caches responses. It is not
an open proxy. The SEC contact is a Cloudflare secret (`wrangler secret put SEC_CONTACT`), never committed.

**Phases.** 1: terminal, panels, quotes, charts, watchlists, news, security search, live crypto depth and tape (done).
2: sign-in and subscribe page, then research tools (FA, EVTS, HP, BT, BETA, FACT, EVST, DVD, EQS, COMP, MVO, CORR, ECO, ECST).
3: paper trading, alerts, the guide. Payments are decided later.
