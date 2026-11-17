# Kestrel security review (2026-11-16)

Kestrel is a native client with **no backend and no API keys**. It reads public market data and keeps
on-device accounts, each with its own simulated (paper) book, watchlists and alerts (updated 2026-11-17). The checklist below is the project-wide bar. Items
that only apply to servers (cookies, CSRF, CORS, admin routes, databases, password reset) are marked N/A.

| # | Item | Status | Evidence |
|---|------|--------|----------|
| 1 | Authentication | ✅ | On-device accounts. Passwords are hashed with PBKDF2-HMAC-SHA256, 600,000 rounds (OWASP 2023), with a 16-byte random salt per account; the hash is checked against the RFC 7914 test vector. Comparison is constant-time, and unknown emails cost the same work as known ones, so timing doesn't reveal which accounts exist. After 5 failures an account locks for 30 s, doubling up to 1 h. Passwords follow NIST 800-63B: at least 10 characters, a blocklist, and no email in the password. Deleting an account requires its password. Hashing runs off the main thread. Each account's data lives in its own folder. The session is only an account ID in UserDefaults: these accounts separate people on a shared device, and a stolen unlocked device is out of scope until sync exists (`AccountTests`, `AuthServiceTests`). |
| 2 | API keys hidden | ✅ | No keys exist. A source scan for `key/secret/token/password` finds none. |
| 3 | Database locked down | N/A | Local JSON file only (see 5). |
| 4 | HTTPS enforced | ✅ | Every endpoint is `https://`/`wss://`. App Transport Security is left at its strict default. RSS links are upgraded to HTTPS (`rss()` test). |
| 5 | Data at rest | ✅ | Paper account, watchlists and alerts are written atomically with `completeFileProtection` inside the app container. |
| 6 | Input validated | ✅ | Command line is capped at 64 chars. Watchlists cap at 100 symbols and 24-char names, and alerts at 200 active; alert levels must be positive and finite and on the far side of the last price. Ad-hoc tickers must match `^[A-Z][A-Z0-9-]{0,7}$`. URLs are built with `URLComponents`. Quantity and limit must be positive `Decimal`s (`rejectsGarbage`, `rejectsOverspend…` tests). |
| 7 | XSS / injection | ✅ | Native UI with no web views. Feed links are restricted to http(s) with a host, so `javascript:` and `file:` are dropped (`rss()` test). XML external entities are disabled. |
| 8 | Suspicious activity logged | ✅ | Feed failures and HTTP errors go to `os.Logger`, with only symbols marked public. |
| 10 | Parameterized queries | N/A | No SQL. |
| 12 | Rate limiting (outbound) | ✅ | Yahoo polling uses at most 6 concurrent requests on a 45 s cycle. The WebSocket reconnects with exponential backoff (0.5 s → 30 s) and has a 15 s stale-feed watchdog. |
| 19 | Prices verified by the engine | ✅ | Fill prices come from the live touch inside `PaperAccount`, never from the UI. Cash checks include working-order reservations and short margin (150%), re-checked at fill time. |
| 20 | Debug off in release | ✅ | Release config uses whole-module optimisation with no debug-only paths. |
| 21–22 | Dependencies | ✅ | Zero third-party packages (only Foundation, SwiftUI and os). |
| 23 | No exposed files | ✅ | `.gitignore` excludes build output, `xcuserdata` and `.DS_Store`. |
| 24–25 | Secrets in git history | ✅ | The repo starts clean, and there are no secrets to leak. |
| — | macOS hardening | ✅ | App Sandbox is on with outgoing network only, plus the Hardened Runtime. |
| — | Untrusted network data | ✅ | WebSocket messages are capped at 16 MB. Decoding uses Swift `Codable` (memory-safe). A sequence gap triggers a full resync. |

Not applicable to a client-only app: 9 (admin routes), 11 (server env vars), 13 (CORS), 14 (security headers),
15 (cookies), 16 (CSRF), 17 (password reset: there is no server to send a reset email, so the sign-in screen says accounts can't be recovered yet), 18 (uploads), 26 (GitHub account settings: owner action).

**Residual risk:** market data comes from free, unauthenticated sources (Yahoo's unofficial chart endpoint and
Coinbase's public feed). It can be delayed, change format or rate-limit without notice. The app degrades to
"no data" states rather than crashing, but quotes should never be treated as executable prices.
