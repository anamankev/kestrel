# Kestrel security review

**Date:** 2026-11-17. **Scope:** the iPad and Mac app, the KestrelCore package, the repository and its full git
history, and the GitHub account settings reachable from this repo.

**Architecture, because it decides what applies:** Kestrel is a native client with **no backend, no database
server, no API keys and no web views**. It reads public market data over HTTPS/WSS and keeps everything else on
the device: accounts, paper portfolios, watchlists and alerts. Server-only controls (CORS, cookies, CSRF,
security headers, admin routes, SQL, uploads, reset emails) have nothing to attach to today. They are listed as
N/A with the design they must follow once the planned backend exists (see the end of this report).

## Results

Every ✅ row is backed by a test or a command whose output is quoted. Test counts at the time of review:
**109 core tests** (`cd KestrelCore && swift test`) and **16 app tests** on macOS and **19** on the iPad simulator
(`xcodebuild test -scheme Kestrel`). All pass.

| # | Item | Status | What was done and how it was verified |
|---|------|--------|---------------------------------------|
| 1 | Authentication | ✅ fixed | Before: the signed-in account was a bare UUID in UserDefaults, so editing one settings value switched accounts without a password. Now: sign-in issues a 256-bit random session token stored only in the **Keychain** (`AfterFirstUnlockThisDeviceOnly`, never synced). The account file keeps only its SHA-256, compared in constant time, with a 30-day sliding expiry. Sign-out and deletion revoke it, so a copied token stops working. Tests: `SessionTests` (forged, expired, other-account and revoked tokens rejected; token never stored in plaintext), `SessionHardeningTests` (replay after sign-out fails, another account's ID with my token fails, Keychain round trip asserted on iPad and Mac). |
| 2 | API keys hidden | ✅ | There are none: every data source is public. `gitleaks detect --log-opts=--all`: "22 commits scanned … no leaks found". |
| 3 | Database locked down | ✅ encrypted | There is no server database. Each account's files (paper book, equity curve, watchlists and alerts) are **sealed with AES-256-GCM** under a random per-account data key. That key is stored only wrapped by a key derived from the password (PBKDF2, 600k rounds, its own salt). Between launches the data key sits beside the session token in the Keychain, and sign-out wipes both, so a copy of the files is unreadable without the password. Tampering is detected. Files from before encryption are sealed at the owner's next sign-in, and a file that won't open is never overwritten. Tests: `VaultTests`, `EncryptionAtRestTests` (no plaintext on disk, reopen after relaunch, legacy migration, wrong key never clobbers data). |
| 4 | HTTPS enforced | ✅ | Every endpoint is `https://` or `wss://`. The release build's Info.plist has no App Transport Security exceptions (checked with `plutil`). RSS links are restricted to https with a host (`rss()` test). |
| 5 | Passwords hashed | ✅ **upgraded 2026-11-18** | **Argon2id** (memory-hard; RFC 9106: 64 MiB, 3 passes, 1 lane), 16-byte random salt per account, derived off the main thread. It uses the PHC reference implementation, vendored unmodified (`KestrelCore/Sources/CArgon2`, CC0/Apache-2.0, tag 20190702) and checked against its six Argon2id test vectors (`Argon2Tests`). PBKDF2 accounts (600k rounds, RFC 7914 vector still tested) are re-keyed at their next sign-in, with new salts and the same data key, so files still open (`upgradesLegacyAccountsAtSignIn`). Rules follow NIST 800-63B: at least 10 characters, a blocklist, and the email can't be part of the password. Tests: `AccountTests`, `Argon2Tests`. |
| 6 | Input validated | ✅ hardened | This app's "server" is its own core: validation lives in KestrelCore, not the UI. The command line is capped at 64 characters, news queries at 120, emails at 254, names at 60 and passwords at 128. New: orders are capped at 1e9 units and prices at 1e12. A fuzz test feeds 10,000-character strings, NUL and bidi controls, SQL, `<script>` and path traversal through the command parser, news search and email validator (`InputBoundsTests`). |
| 7 | XSS / injection | ✅ | No web views or HTML rendering. Headlines are plain `AttributedString`s, never Markdown. Links open only if they are https. XML external entities are disabled in the RSS parser. |
| 8 | Suspicious activity logged | ✅ new | `os.Logger` (subsystem `dev.kestrel.terminal`, category `security`) records failed sign-ins, lockouts, rejected or tampered sessions, sign-outs, deletions and Keychain failures. Emails are logged as a private hash and never in clear. |
| 9 | Admin routes | N/A | No admin surface exists. |
| 10 | Parameterized queries | N/A | No SQL. Outbound URLs are built with `URLComponents`, never string concatenation. |
| 11 | Environment variables | ✅ | The app reads none, and there are no `.env` files in the tree or in history. CI uses no secrets. |
| 12 | Rate limiting | ✅ | Sign-in: 5 failures lock the account for 30 s, doubling to 1 h. Unknown emails cost the same work as real ones, so they can't be enumerated by timing. Outbound: at most 6 concurrent Yahoo requests on a 45 s cycle, WebSocket reconnect backoff from 0.5 s to 30 s, and a 15 s stale-feed watchdog. |
| 13 | CORS | N/A | No server. |
| 14 | Security headers | N/A | No server. |
| 15 | Session cookies | ✅ equivalent | No cookies. The session is the Keychain token from row 1 (hashed at rest, expiring, revocable). |
| 16 | CSRF | N/A | No server and no web forms. |
| 17 | Password-reset expiry | N/A | There is no email server, so no reset links exist. The sign-in screen says accounts can't be recovered yet. |
| 18 | Upload restrictions | N/A | The app accepts no uploads. |
| 19 | Prices verified | ✅ | Paper fills are priced by the engine from the live touch, never from the UI. Cash and margin are re-checked at fill time. Stops trigger on the last trade. **Subscriptions:** prices come from the App Store (`Product.displayPrice`), never hard-coded in the UI. Pro is granted only from StoreKit 2 transactions that verify (App Store JWS, checked on device); unverified, revoked (refunded) or expired transactions grant nothing. Purchases carry the Kestrel account ID as `appAccountToken`. Tests: `SubscriptionTests` (entitlement rules) and `SubscriptionStoreTests` (real StoreKitTest purchases of each plan, renewal, refund, restore). Residual: with no server, a jailbroken device could patch the app to skip the check, which App Store Server API validation would close once the backend exists. |
| 20 | Debug off in production | ✅ fixed | The snapshot and demo tours are now compiled only into DEBUG builds. In the release binary, `strings` finds no `-snapshot`, `-demo`, tour paths or test passwords. |
| 21 | Vulnerable dependencies | ✅ | No package-manager dependencies. One vendored C library, the Argon2 reference implementation (PHC, tag 20190702, CC0/Apache-2.0), was reviewed before vendoring: it does no file, network or environment access, and no threads are compiled in. Dependabot alerts and security updates are enabled. |
| 22 | Unused packages | ✅ | None to remove. |
| 23 | Exposed files | ✅ | No `.DS_Store`, `xcuserdata`, keys, certificates, provisioning profiles or `.env` files have ever been committed (checked against every path in history). `.gitignore` covers build output. |
| 24 | Secrets in git history | ✅ | `gitleaks` over all 22 commits found no leaks. A pattern scan found only test-fixture passwords in test files. |
| 25 | Revoke leaked keys | ✅ | Nothing leaked, so nothing to revoke. GitHub secret scanning and push protection are now **on** for all six public repos, so a future key is blocked at push time. |
| 26 | GitHub account | ⚠ partly yours | Done: topics on `kestrel`; secret scanning, push protection and Dependabot enabled on every public repo, with 0 alerts. Needs you: 2FA with a passkey or security key, reviewing OAuth apps and tokens, and the commit email (see "Owner decisions"). A drafted Kestrel section for your profile README is waiting for your approval. |
| 27 | Full review, tested | ✅ | This document. Every fix above has a test, a command or a capture behind it. |

### Also done (item 28)

- **App-switcher privacy (iPad):** a cover hides balances and positions whenever the app isn't active.
- **Apple privacy manifest:** `PrivacyInfo.xcprivacy` declares no tracking and no collected data, plus the required-reason APIs (UserDefaults, elapsed time). It is bundled in the release build.
- **Sandbox:** the macOS App Sandbox allows outgoing network connections only, under the Hardened Runtime (confirmed with `codesign -d --entitlements`).
- **Encrypted iPad ↔ Mac transfer:** the transfer file is sealed with AES-256-GCM under an Argon2id key from a passphrase (format KXF2; older PBKDF2 KXF1 files still open) (10+ characters, random salt), and is treated as untrusted on import. The size is capped at 8 MB, the iteration count is bounded so a crafted file can't stall the device, tampering is detected, and the contents are re-validated against the same limits as typed input before anything is replaced, behind a confirm step (`TransferTests`).
- **Background alerts** use only the public price endpoints already allowed; nothing new leaves the device.
- **Old session key removed:** the UserDefaults value from earlier builds is deleted on launch, so it can't be used as a backdoor.

### Owner decisions (I did not do these without you)

1. **Commit email:** every commit carries `kanaman@brandeis.edu` as its author, and that is public on a public repo. Options: use GitHub's `noreply` address for future commits (no history change), or also rewrite history (destructive force-push). I recommend the first.
2. **Two-factor authentication on GitHub:** use a passkey or hardware key. This is in your account settings; my token can't see or change it.

### Residual risk

- Files are encrypted, but while you are signed in the data key is in the Keychain. Someone using your
  unlocked, signed-in device can see your paper book, just as they could see the screen. Signing out locks it.
- Market data comes from free, unauthenticated sources. It can be delayed or change format, so quotes are never
  executable prices.
- **Web build tools (`web/`):** `npm audit` reports `picomatch` (GHSA-fc5q-39xc-vjpf, ReDoS, now rated high) through Vite and Vitest. No patched release exists (rechecked 2026-11-18) (every version up to 4.0.7 is affected). It only runs inside the development and build tools, on the project's own glob patterns; it is not shipped to browsers or the relay, so it isn't reachable by users. Re-check when picomatch publishes a fix. All other web dependency findings were fixed by upgrading Vite (8.3.5), Vitest (5.1.0), the React plugin (6.2.1) and TypeScript (5.9.3), each at least two weeks old. `npm audit --omit=dev`: 0 vulnerabilities.

## Web app and relay (2026-11-18)

**Scope:** `web/` (React app served as static files from Cloudflare Pages) and `web/worker/` (the Cloudflare
Worker relay). The web app has accounts in the browser and no Kestrel server. The relay is the only server
code. It forwards an allowlisted set of read-only public-data requests. Tests: **73 web tests**
(`cd web && npm test`) and **6 KestrelCore transfer tests**, all passing, plus the live probes quoted below,
run against the relay (`npm run relay`) and the production bundle.

| # | Item | Status | What was done and how it was verified |
|---|------|--------|---------------------------------------|
| 1 | Authentication | ✅ | Mirrors the app: Argon2id (row 5), NIST 800-63B password rules, 5 failures lock the account with doubling back-off, and unknown emails cost the same work. The session key is a **non-extractable** WebCrypto AES key in IndexedDB with a 30-day sliding expiry; sign-out deletes it. Tests: `auth.test.ts` (policy, wrong password, lockout, wrapped data key, vault tampering). Residual: anyone with access to the browser profile can reset the lockout counter in local storage, so offline guessing is limited only by the KDF (see row 5). |
| 2 | API keys hidden | ✅ | No keys exist. The only secret is the SEC contact email: a Cloudflare secret in production and `worker/.dev.vars` locally (gitignored, mode 600, never committed). It is sent only to sec.gov. `gitleaks detect --log-opts=--all`: "51 commits scanned … no leaks found". |
| 3 | Database locked down | ✅ | No server database. Each account's data (watchlists, workspace and pages, paper book, alerts) is sealed with AES-256-GCM under a random data key wrapped by a password-derived key. Test: the vault holds ciphertext only (checked in the browser earlier, and by `auth.test.ts`). |
| 4 | HTTPS enforced | ✅ | Pages serves only HTTPS, `_headers` adds HSTS, and the CSP adds `upgrade-insecure-requests` for https relays. **New:** `npm run build` stops if `VITE_RELAY_URL` is missing or not https (`scripts/check-env.mjs`; verified: "VITE_RELAY_URL is not set"), so a production bundle can't fall back to `http://localhost`. The relay answers with HSTS. |
| 5 | Passwords hashed | ✅ **upgraded** | **Argon2id**, 64 MiB, 3 passes, 1 lane: the same as the app, via `hash-wasm` 4.12.0 (MIT, no dependencies or install scripts). It gives the **same outputs as the app** on the reference vectors (`auth.test.ts`). PBKDF2 accounts are re-keyed at their next sign-in, keeping their data key (test: "upgrades a PBKDF2 account at sign-in"). CSP gains only `'wasm-unsafe-eval'`, which allows WebAssembly but not `eval`. Live on the production build: a new account was created with Argon2id under the strict CSP with no console errors, a wrong password was refused and the right one signed in. One hash takes about 130 ms in the browser (PBKDF2 at 600k took 44 ms). |
| 6 | Input validated | ✅ | The relay validates every path segment and query value against allowlists before any upstream call. The app validates imports like typed input. Live probes, each answered **404**: `/yahoo/chart/..%2F..%2Fetc%2Fpasswd`, `/sec/facts/..%2F..%2Fsubmissions`, `/french/..%2F..%2Fsecret.zip`, `/wb/bulk/%2e%2e`, `/proxy?url=http://169.254.169.254/`, a 65-character search, and `events=evil`. Encoded `&`/`=` in a symbol is re-encoded upstream, so no parameter injection. |
| 7 | XSS blocked | ✅ | React escapes all text; there is no `dangerouslySetInnerHTML`, `innerHTML`, `eval` or `new Function` in `src/` or the relay. CSP: `script-src 'self'`, `object-src 'none'`, `base-uri 'none'`, `frame-ancestors 'none'`. Live: a hostile RSS feed in the browser dropped the `javascript:`, `data:` and `http:` links, kept an `<img onerror>` headline as plain text, and didn't expand an external entity. External links use `rel="noopener noreferrer"`. **New:** relay responses carry `Content-Security-Policy: default-src 'none'; frame-ancestors 'none'; sandbox` and `X-Frame-Options: DENY`, so an HTML upstream response can't run (test: "responses can't run or be framed"). Residual: `style-src 'unsafe-inline'` is needed for React style attributes; it allows CSS, not script. |
| 8 | Suspicious activity logged | ✅ **new** | The relay logs rejected origins, rejected methods, invalid routes, rate limiting, upstream failures and misconfiguration as JSON lines (`wrangler tail`). Visitor IPs appear only as a truncated SHA-256 tag. Test: "logs suspicious requests with a hashed IP, never the address". Live: `{"event":"rate_limited","ip":"0133cae03a78","path":"/yahoo/search"}`. |
| 9 | Admin routes | N/A | None exist. |
| 10 | Parameterized queries | N/A | No SQL. Upstream URLs are built with `URL`/`searchParams`, never concatenated input. |
| 11 | Environment checked at startup | ✅ **new** | Workers have no startup hook, so the relay checks its configuration on every request (`configProblem`). It refuses (500, no CORS) an empty or wildcard `ALLOWED_ORIGINS`, non-https or non-bare origins, and a malformed `SEC_CONTACT`. The build checks `VITE_RELAY_URL` (row 4). Tests: "refuses unsafe configuration". |
| 12 | Rate limiting | ✅ | 120 requests a minute per IP per relay instance, sign-in lockout, and long cache lifetimes (BLS 12 h, SEC filings 1 to 24 h). Live: 130 requests from one IP gave **120 × 200, 10 × 429**, while another IP was still served. Residual: the limit is per Worker instance. A Cloudflare rate-limiting rule (one is free) would make it global. |
| 13 | CORS restricted | ✅ **fixed** | Allow-list only, no `*`. Live: no Origin, `https://evil.example`, `null` and the lookalike `http://localhost:5173.evil.example` each got **403**. **New:** local origins are now only in the dev config, and production uses `[env.production]` with the site's origin alone. `deploy:relay` deploys `--env production`. Note: Origin is a browser control, so scripts can forge it; it is not authentication. The allowlist, validation and rate limit are what bound misuse. |
| 14 | Security headers | ✅ | Site (`dist/_headers`): CSP, HSTS, `nosniff`, `Referrer-Policy: no-referrer`, `X-Frame-Options: DENY`, COOP and a restrictive `Permissions-Policy`. Live on the production bundle: allowed APIs returned 200, and `https://example.com` was **blocked** by CSP. Relay: the same plus the sandbox CSP above (live headers confirmed with `curl -D -`). |
| 15 | Session cookies | ✅ equivalent | No cookies. The session is a non-extractable key in IndexedDB (row 1), which page scripts can use but never read. |
| 16 | CSRF | ✅ N/A by design | The relay is GET-only and stateless (POST/PUT answer 405, verified live). The app has no server session to forge requests against. |
| 17 | Password reset | N/A | No email server or reset links. The sign-in page says accounts can't be recovered. |
| 18 | Uploads restricted | ✅ **fixed** | The only upload is the `.kestrel` transfer file. **New:** the size is checked *before* the file is read (24 B to 8 MB). Then come the magic bytes, a bounded iteration count, authenticated decryption and field-by-field validation, and a confirm step before anything is replaced. Live: a 9 MB file, a 10-byte file and an HTML file were each refused in 8 ms total. Tests: `transfer.test.ts` (wrong passphrase, tampering, hostile iteration count, validation). |
| 19 | Prices verified on the server | ⚠ open until payments | Paper fills are priced by the engine from live quotes, never from the UI. **Subscription:** any gate in a static site runs in the visitor's browser and can be bypassed. **New:** production builds no longer contain the "web preview" bypass (verified: 0 matches in the bundle), and the app ignores a forged preview flag. Real enforcement must come with payments: the relay should require a signed entitlement token on Pro data routes, issued only after server-verified payment. |
| 20 | Debug off in production | ✅ | The `window.__kestrel` hook is dev-only and absent from the production bundle (grep: 0 matches). There are no source maps (`sourcemap: false`; `dist/` has no `.map`). |
| 21 | Vulnerable dependencies | ⚠ dev-only residual | `npm audit --omit=dev`: **0 vulnerabilities** in what ships. Dev tools: `picomatch` ≤ 4.0.7 (GHSA-fc5q-39xc-vjpf, ReDoS, now rated high) through Vite and Vitest. **There is still no patched release** (latest is 4.0.7); `npm audit fix --force` would only downgrade the tools. It runs only on the project's own build globs, never in browsers or the relay. |
| 22 | Unused packages | ✅ | Runtime dependencies: `react`, `react-dom`. Dev: Vite, Vitest, the React plugin, TypeScript, React types and Workers types, all used. |
| 23 | No exposed files | ✅ | `dist/` holds only `index.html`, `favicon.svg`, hashed JS and CSS, and `_headers`: no `.env`, `.git`, maps or backups. `.env.production` holds only the public relay URL. |
| 24 | Git history scanned | ✅ | gitleaks: 51 commits, no leaks (above). |
| 25 | Leaked keys revoked | ✅ | Nothing leaked. GitHub secret scanning and push protection stay on. |
| 26 | GitHub account | ⚠ yours | Unchanged from 2026-11-17: 2FA with a passkey and the commit email are your decisions. Every commit, including today's, still carries `kanaman@brandeis.edu`. |
| 27 | Full review, tested | ✅ | This section. |

### Owner decisions (web)

1. ~~Memory-hard password hashing~~: **done 2026-11-18** (row 5). Transfer files are now written as **KXF2** (Argon2id
   settings in the header, bounded on import: at most 256 MiB, 10 passes and 4 lanes). Both apps still open
   **KXF1**. Files are tested in both directions between web and app for both formats.
2. **Before charging on the web (row 19):** build the server-side entitlement check with payments.
3. **Before deploying:** add one free Cloudflare rate-limiting rule on the relay (row 12).

## Re-review (2026-11-19): whole app, web app and relay

**Scope:** everything, read again as an attacker would, with extra depth on code added since 2026-11-18: the
relay's SEC industry, share-count and Treasury routes; RV, SEAS, GC, YAS, LEARN, COPY and PNG on every platform;
and the Mac keychain change. **Tests after the fixes:** 157 KestrelCore, 22 app tests on macOS, 23 on the iPad
simulator, 98 web and relay tests. All pass.

### Found and fixed

| # | Where | Flaw | Fix and proof |
|---|-------|------|---------------|
| 1 | Relay | Upstream redirects were followed blindly, so a redirect from an upstream could make the relay fetch another host for a visitor. | A response whose final URL is on a different host from the one requested is refused (502) and logged as `upstream_redirect_rejected`. The only upstream that redirects (CoinDesk, to its own host) now uses its final URL. Test: "never follows a redirect off the upstream host". |
| 2 | Relay | The 25 MB cap was checked after reading the whole body into memory. | A larger `Content-Length` is refused before the body is read. Test: same, which asserts the stream is never pulled. |
| 3 | Relay | Once 10,000 IPs were tracked, the rate-limit table was wiped, so a flood of new IPs reset every visitor's count, including a blocked one's. | Expired windows are dropped first, then only the oldest entry. Test: "a flood of new IPs doesn't reset a limited IP". |
| 4 | App | Futures (`…=F`) and index (`^…`) symbols accepted any characters, including `/`, `?`, `#`, `..` and non-ASCII letters, and went straight into Yahoo request paths. The web was already protected by the relay's symbol pattern. | Both are ASCII-only (`[A-Z0-9.-]{1,8}=F`, `^[A-Z0-9.]{1,11}`). Test: `SymbolPathTests` (hostile symbols rejected; every resolved symbol stays on Yahoo's chart path). |
| 5 | App and web | The SEC industry code from a company's filing went into a request URL unchecked. In Swift, `\d` also matches full-width digits such as `３５７１`; the new test caught this. | Only 4 ASCII digits are accepted (`[0-9]{4}`); anything else shows "no data". Tests: `IndustryCodeTests`; the relay also refuses `/sec/sic/3571%26x` (404, live). |
| 6 | App and web | Chart trendlines and bond-calculator inputs sit in plain device storage outside the encrypted vault, so on a shared iPad, Mac or library computer the next person to sign in saw them. | Cleared at sign-out and account deletion; display preferences (ranges, studies) are kept. Tests: `PersonalUITests` (app), `personal.test.ts` (web). |
| 7 | Web | Saved bond inputs were read from storage without checking their shape. | Checked before use: short strings, a date-shaped maturity and a known mode, otherwise the defaults. Test: "rejects tampered bond inputs". |
| 8 | Mac (fixed earlier today) | The saved session was read from the login keychain on the main thread. Each rebuilt app asked for the keychain password and froze until answered. | Sessions use the data-protection keychain, which is tied to the app and never prompts. Unsigned dev builds, which can't use it, keep the session in memory only. Commit "Mac: sessions in the data-protection keychain, so launches never prompt or freeze". |

### Checked and clean

- **Web sinks:** no `innerHTML`, `dangerouslySetInnerHTML`, `eval`, `new Function`, `postMessage` or `window.open`. Both data-driven links are https-only and `noopener noreferrer`.
- **New features:** COPY writes text only; PNG draws only the app's own canvas and frees its blob URL. LEARN progress lives in the encrypted vault, and stored IDs are filtered to known drills.
- **Relay, live:** `/tsy/1900`, `/tsy/2025x`, `/sec/shares/CY2026Q9I` and a traversal attempt each returned **404**, and a foreign origin got **403**.
- **Release app (Mac):** no ATS exceptions. No debug flags or tour strings in the binary (`-snapshot`, `-uitest`, `-capture`, `-keychainProbe`: 0 matches). Sandbox with outgoing network only.
- **Dependencies:** `npm audit` reports **0 vulnerabilities**, including dev tools: the picomatch advisory listed above is resolved.
- **Secrets:** gitleaks over all 66 commits found no leaks.

### Before release (needs signing)

- A locally signed Release build carries `get-task-allow`, which lets a debugger attach. Xcode adds it because
  there is no signing team; App Store distribution signing removes it. Turning off entitlement injection
  instead strips the sandbox too, so I left the setting alone. **Check:** after the first App Store archive,
  `codesign -d --entitlements -` on the exported app must not list `get-task-allow`.
- Mac builds from before 2026-11-19 left the old session item `dev.kestrel.terminal.session` in your **login**
  keychain. The new app never reads it, and the token inside stops working at your next sign-in. To remove it,
  delete it in Keychain Access.

## When the backend exists

The backend planned for push alerts and sync must ship with: TLS only; HSTS, CSP, `X-Content-Type-Options`,
`Referrer-Policy` and `frame-ancestors 'none'`; a CORS allow-list with no `*`; session cookies (if web) that
are `Secure`, `HttpOnly` and `SameSite=Strict`, with CSRF tokens; parameterized SQL only; server-side
validation that mirrors KestrelCore; per-IP and per-account rate limits; single-use reset tokens that expire
in 15 minutes and are stored hashed; secrets in a secret manager, never in env files committed to git; and
uploads (if any) restricted by type sniffing and size. These rows move from N/A to tested at that point.
