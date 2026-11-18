# Kestrel for the web

The same terminal in the browser: React + TypeScript + Vite, with the iPad/Mac app's core logic ported
(command parser, decoders, indicators, quant and research models, the paper-trading engine, alerts, Black-76 options
and the guide) and its tests ported alongside. All 38 functions work on the web.

```
npm install
npm run relay   # Cloudflare Worker relay on :8787 (needs worker/.dev.vars with SEC_CONTACT=you@example.com)
npm run dev     # app on :5173
npm test        # core, guide, paper engine, options and relay tests
npm run build       # production: needs an https VITE_RELAY_URL; type-checks, bundles, writes dist/_headers
npm run build:local # the same bundle against the local relay, for checking on this machine
npm run preview     # serve dist on :4173 with those headers
npm run guide   # regenerate the guide's knowledge from KestrelCore/Guide.swift
```

**Accounts and data.** Accounts live in the browser: passwords are hashed with Argon2id (64 MiB, 3 passes; older PBKDF2 accounts upgrade at sign-in), and each
account's watchlists, workspace, paper book and alerts are sealed with AES-256-GCM under a key the password unlocks.
The session key is a non-extractable WebCrypto key in IndexedDB. There is no Kestrel server or account database.

**Relay (`worker/`).** Browsers can't call Yahoo, the SEC, BLS's POST API, the French Data Library or the World Bank's
bulk files directly (no CORS; the SEC also requires a contact User-Agent). The relay forwards only an allowlisted set of
read-only routes, validates every path and query value, answers only Kestrel's own origins, rate-limits per visitor and
caches responses. It is not an open proxy. The SEC contact is a Cloudflare secret, never committed. Coinbase, Deribit,
the New York Fed and the World Bank's country list are called directly from the browser.

## Deploy (Cloudflare free tier)

1. Sign in once: `npx wrangler login`.
2. Store the SEC contact as a secret: `npx wrangler secret put SEC_CONTACT --config worker/wrangler.toml --env production`.
3. In `worker/wrangler.toml`, set `[env.production.vars] ALLOWED_ORIGINS` to the site's exact origin
   (e.g. `https://kestrel-web.pages.dev`), then `npm run deploy:relay`. The relay refuses to serve with a wildcard,
   non-https or malformed origin. Note the relay URL it prints (`https://kestrel-relay.<account>.workers.dev`).
4. Write `.env.production` with `VITE_RELAY_URL=<that URL>`, then `npm run build`. The build stops if the relay URL is
   missing or not https.
5. Publish: `npx wrangler pages deploy dist --project-name kestrel-web`.

6. Watch the relay's security log with `npx wrangler tail --config worker/wrangler.toml --env production`
   (rejected origins, invalid routes, rate limiting, upstream failures; visitor IPs appear only as hashes).

Payments: the subscribe page shows the plans; web checkout isn't wired yet. Development builds show a
"Continue to the web preview" link; production builds don't, unless built with `VITE_WEB_PREVIEW=1` on purpose.
