# Kestrel backend plan

**Date:** 2026-11-20. **Scope:** the web app first. The iPad/Mac app isn't distributed yet, so its client side
comes later and reuses the same server. **Budget:** $0 upfront. Everything below runs on free tiers; the only
money involved is the payment provider's cut of each sale, taken out of the sale itself.

## Why a backend at all

Today the web app has no server of its own. Accounts, encryption and the subscribe page all run in the browser,
and the relay only forwards public data. Four things can't work that way:

| Need | Why it needs a server |
|------|-----------------------|
| **1. Charging for the web** | A paywall that runs in the browser can be edited away (SECURITY.md, row 19). The server must know who paid and refuse Pro data to everyone else. |
| **2. Accounts that work on any browser** | Today an account exists in one browser profile only. Clearing site data deletes it, and a second computer can't sign in. |
| **3. Sync** | Watchlists, paper book, pages, alerts and LEARN badges follow you between computers (and later the iPad/Mac app). |
| **4. Alerts when the tab is closed** | Today alerts fire only while a Kestrel tab is open. Push needs a server watching prices. |

Account recovery comes with 2 (see decision B).

## Architecture (all on the Cloudflare free plan)

```
Browser ──► kestrel-web.pages.dev            (one origin: first-party cookies, no CORS)
              ├─ /            static app (Pages, unlimited static requests)
              ├─ /api/auth/*  accounts and sessions      ┐
              ├─ /api/vault   encrypted sync             │ Pages Functions (Workers runtime)
              ├─ /api/billing payment webhooks, status   │
              ├─ /api/push/*  push subscriptions, alerts │
              └─ /api/data/*  today's relay, moved here  ┘
                                │
                     D1 (SQLite): users · sessions · subscriptions · vaults · alerts · push · audit log
                     Durable Object: global rate limiter
                     Cron Trigger (every minute): alert checks · daily billing reconcile
```

**Why one origin:** `pages.dev` and `workers.dev` are separate sites to browsers (both are on the Public Suffix
List), so a session cookie set by a separate API Worker would be a blocked third-party cookie. Serving the API
from the site's own origin through Pages Functions makes it a first-party `HttpOnly; Secure; SameSite=Strict`
cookie. It also removes CORS entirely, and moving the relay under `/api/data` lets it check the subscription.

**Free-tier limits that matter** (Cloudflare docs, checked 2026-11-20):

| Resource | Free limit | Kestrel use |
|----------|-----------|-------------|
| Worker / Functions requests | 100,000 a day | The binding constraint (see "Capacity") |
| CPU time | 10 ms per request; waiting on fetch or the database doesn't count | Fine for everything below. **Argon2 must stay in the browser**: 10 ms is far too little to hash passwords on the server. |
| D1 database | 5 M rows read and 100k written a day; 5 GB total, 500 MB per database; 2 MB per row; 7 days of Time Travel (point-in-time restore) | Vault blobs are well under 2 MB. Daily writes are far below the cap. |
| Durable Objects | 100k requests a day, SQLite-backed only | Global rate limiter |
| Cron Triggers | 5 per account | 2 used (alerts every minute, daily billing reconcile) |
| Subrequests | 50 per invocation | The alert cron batches 20 symbols per Yahoo request, so up to 1,000 symbols a minute |

**Capacity (honest ceiling):** every quote refresh, chart and research call through the relay counts toward the
100,000 requests a day, as do API calls. Live crypto goes straight to Coinbase and doesn't count. A user with a
terminal open makes about 3 requests a minute (quotes every 20 s), or about 180 an hour. That gives
**roughly 500 user-hours of open terminal a day**: a few hundred active users with typical sessions. Past that,
requests fail with 429s until midnight UTC. The fix then is Workers Paid ($5 a month), which only makes sense
once there is revenue. The relay's caching already merges identical requests, and the plan below adds a 60 s
server-side quote cache.

## Decisions to make once (my recommendation first)

**A. Payment provider.** A *merchant of record* (MoR) is the legal seller. It collects and pays sales tax and VAT
in every country, handles card disputes and sends receipts. Without one, you are personally responsible for sales
tax across US states and abroad. None of these charge a monthly fee; each takes a cut of every sale.

| Provider | Cut (Nov 2026) | Notes |
|----------|----------------|-------|
| **Polar** (recommended) | 5% + 50¢ on the free Starter plan; +1.5% on non-US cards | Developer-first API and webhooks, open source, 195+ seller countries. Raised rates in May 2026. |
| Lemon Squeezy | 5% + 50¢ plus surcharges | Owned by Stripe since 2024. Its team is now building Stripe Managed Payments, so its future is uncertain, and sellers report slower support. |
| Stripe Managed Payments | 3.5% on top of Stripe's 2.9% + 30¢ and Billing's subscription fee (about 7% all-in) | Public preview since Feb 2026. The most expensive here. |
| Paddle | 5% + 50¢ | Strict approval; expects an established website. |

On your prices with Polar: monthly $9.99 keeps about **$8.99**, 6 months $49.99 keeps about **$46.99**, and yearly
$99.99 keeps about **$94.49**. The fixed 50¢ hurts the monthly plan most, which is another reason to lead with yearly.
**What you'd do:** create the Polar account yourself (ID check, bank account for payouts). I can't create accounts
or enter identity or bank details. Polar also needs Terms, Privacy and Refund pages on the site; I'll draft them.

**B. Account recovery.** Sending email needs a domain you own (Resend's free tier is 100 a day, but only from a
verified domain), and domains cost money. Separately, your data is end-to-end encrypted, so a server-side reset
could never recover it anyway.
- **Recommended: a recovery key.** At sign-up the app shows a 24-character key once ("print or save this"). It can
  reset the password and still opens your data. This is how Bitwarden and 1Password work. No email is needed.
- Alternative: "forgot password" deletes the data and lets the person start over. That is simpler but harsh.

**C. Alerts when the tab is closed (web push).**
- **Recommended: yes.** The server then stores each alert's symbol and price level in plain form so it can check
  them; portfolios, watchlists and everything else stay encrypted. Push is free (VAPID keys, no third-party
  service). On iPhone and iPad, web push works only after "Add to Home Screen" (iOS 16.4+).
- Alternative: no. Alerts stay end-to-end private but fire only while a tab is open.

**D. Existing browser accounts.** **Recommended:** at their next sign-in, a local account is created on the
server automatically and its encrypted data uploaded, with no extra step. (Alternative: start fresh.)

## Design (what gets built)

**Accounts (zero-knowledge).**
1. The browser runs Argon2id(password, per-account salt), as today, and splits the result with HKDF into an
   **auth key** and a **wrap key**.
2. The server stores only SHA-256 of the auth key. That is safe because the auth key is a 256-bit derived value,
   not the password.
3. The wrap key never leaves the browser. It unwraps the data key, so the server can't read anyone's data even if
   the database leaks.
4. For an unknown email, the salt lookup returns a fake salt derived from a server secret, so emails can't be
   enumerated.

**Sessions, CSRF and abuse.**
- **Session:** a 256-bit token in an `HttpOnly; Secure; SameSite=Strict` cookie, stored hashed in D1. It slides for
  30 days and is revocable ("sign out everywhere").
- **CSRF:** every state-changing request needs `SameSite=Strict`, a matching `Origin` and a custom `X-Kestrel`
  header.
- **Rate limits:** per IP and per account through the Durable Object. Sign-in keeps the 5-failure lockout, now on
  the server where it can't be reset from the browser.
- **Sign-up:** protected by Cloudflare Turnstile (free).
- **Audit log:** sign-ins, failures, lockouts and billing events go to a D1 table, with IPs hashed.

**Subscriptions.**
1. Checkout is Polar's hosted page, tagged with the Kestrel account ID.
2. Polar's signed webhook (signature verified, replay-protected by event ID) records the status and the period end
   in D1. A daily cron reconciles against Polar's API in case a webhook was missed.
3. `/api/data/*` serves Pro data only to a session whose subscription is active. The sign-in screen's live ticker
   stays public. "Manage subscription" opens Polar's customer portal for cancel, card and invoices.
4. The client never decides who is Pro.

**Encrypted sync.** The vault the browser already seals (AES-256-GCM) is uploaded with `PUT /api/vault` and a
version number. A stale version gets 409, and the browser merges and retries. The limit is 1 MB per account.

**Push alerts.**
1. A service worker (CSP gets `worker-src 'self'`) and a web manifest are added. Push subscriptions are stored per
   device.
2. The cron fetches distinct alert symbols in batches of 20, compares them to thresholds and sends Web Push
   (RFC 8291 encryption with WebCrypto).
3. Each alert fires once, then becomes history, matching the app's rules.

**Validation.** Every endpoint uses a schema check with size caps that mirror KestrelCore. D1 queries are
prepared statements with bound parameters only. Bodies are capped at 1 MB.

**Secrets.** The VAPID private key, Polar webhook secret, session pepper, fake-salt secret and SEC contact are
stored as `wrangler secret`, never in git.

**Backups.** D1 Time Travel gives point-in-time restore for the last 7 days. A weekly cron export is optional
later.

## Build order

| # | Piece | Depends on | Done when |
|---|-------|-----------|-----------|
| 1 | Pages Functions skeleton, D1 schema and migrations, relay moved to `/api/data`, Durable Object rate limiter | — | Today's app works unchanged from the new origin; relay tests pass there |
| 2 | Server accounts and sessions, migration of browser accounts, recovery key | 1 | Sign up on one browser, sign in on another; the lockout survives clearing site data |
| 3 | Encrypted sync | 2 | A watchlist added on one browser appears on the other; the server holds ciphertext only |
| 4 | Polar checkout, webhook, entitlement gate on `/api/data`, Terms/Privacy/Refund pages | 2, your Polar account | A test-mode purchase unlocks Pro; a canceled or refunded one locks it; the paywall can't be bypassed from the browser |
| 5 | Web push alerts | 2 | An alert fires to a closed tab and to a home-screen iPhone |
| 6 | Security review against the 27-item checklist, each fix tested, SECURITY.md updated | all | Report delivered |
| later | iPad/Mac app: same accounts, sync and entitlement | 2–4, a distribution decision | — |

Everything runs locally first (`wrangler pages dev` with a local D1), so nothing is deployed until you say the
product is done.

## What I need from you

1. Answers to decisions **A–D** above.
2. When step 4 starts: a **Polar account** in test mode (sign-up, then identity and bank details: yours to enter).
3. When you choose to deploy, not before: a **Cloudflare account** (free) logged in with `wrangler login`.

## Known risk (not a backend task)

Most quotes come from Yahoo Finance's free endpoints, whose terms don't allow commercial redistribution. A
payment provider reviewing a paid market-data product may ask where the data comes from. You chose to set data
licensing aside for now; it becomes relevant at step 4.

## Sources

- Cloudflare: [Workers pricing and free limits](https://developers.cloudflare.com/workers/platform/pricing/), [Workers limits](https://developers.cloudflare.com/workers/platform/limits/), [D1 limits](https://developers.cloudflare.com/d1/platform/limits/), [Rate Limiting binding](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/)
- Payments: [Polar fees](https://polar.sh/docs/fees), [Polar plans](https://polar.sh/blog/introducing-polar-plans), [Lemon Squeezy 2026 update](https://www.lemonsqueezy.com/blog/2026-update), [Stripe Managed Payments pricing](https://support.stripe.com/questions/managed-payments-pricing)
- Email: [Resend sending limits](https://resend.com/docs/knowledge-base/resend-sending-limits)
- Cookies: [same-site vs same-origin](https://web.dev/articles/same-site-same-origin), [Heroku on the Public Suffix List](https://devcenter.heroku.com/articles/cookies-and-herokuapp-com)
