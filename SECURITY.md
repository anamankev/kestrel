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
**97 core tests** (`cd KestrelCore && swift test`) and **15 app tests** on both macOS and the iPad simulator
(`xcodebuild test -scheme Kestrel`). All pass.

| # | Item | Status | What was done and how it was verified |
|---|------|--------|---------------------------------------|
| 1 | Authentication | ✅ fixed | Before: the signed-in account was a bare UUID in UserDefaults, so editing one settings value switched accounts without a password. Now: sign-in issues a 256-bit random session token stored only in the **Keychain** (`AfterFirstUnlockThisDeviceOnly`, never synced). The account file keeps only its SHA-256, compared in constant time, with a 30-day sliding expiry. Sign-out and deletion revoke it, so a copied token stops working. Tests: `SessionTests` (forged, expired, other-account and revoked tokens rejected; token never stored in plaintext), `SessionHardeningTests` (replay after sign-out fails, another account's ID with my token fails, Keychain round trip asserted on iPad and Mac). |
| 2 | API keys hidden | ✅ | There are none: every data source is public. `gitleaks detect --log-opts=--all`: "22 commits scanned … no leaks found". |
| 3 | Database locked down | ✅ encrypted | There is no server database. Each account's files (paper book, equity curve, watchlists and alerts) are **sealed with AES-256-GCM** under a random per-account data key. That key is stored only wrapped by a key derived from the password (PBKDF2, 600k rounds, its own salt). Between launches the data key sits beside the session token in the Keychain, and sign-out wipes both, so a copy of the files is unreadable without the password. Tampering is detected. Files from before encryption are sealed at the owner's next sign-in, and a file that won't open is never overwritten. Tests: `VaultTests`, `EncryptionAtRestTests` (no plaintext on disk, reopen after relaunch, legacy migration, wrong key never clobbers data). |
| 4 | HTTPS enforced | ✅ | Every endpoint is `https://` or `wss://`. The release build's Info.plist has no App Transport Security exceptions (checked with `plutil`). RSS links are restricted to https with a host (`rss()` test). |
| 5 | Passwords hashed | ✅ | PBKDF2-HMAC-SHA256, 600,000 rounds (OWASP 2023), 16-byte random salt per account, derived off the main thread. The implementation is checked against the RFC 7914 test vector. Rules follow NIST 800-63B: at least 10 characters, a blocklist, and the email can't be part of the password. Tests: `AccountTests`. |
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
| 19 | Prices verified | ✅ | Paper fills are priced by the engine from the live touch, never from the UI. Cash and margin are re-checked at fill time. Stops trigger on the last trade. |
| 20 | Debug off in production | ✅ fixed | The snapshot and demo tours are now compiled only into DEBUG builds. In the release binary, `strings` finds no `-snapshot`, `-demo`, tour paths or test passwords. |
| 21 | Vulnerable dependencies | ✅ | Zero third-party packages (Foundation, SwiftUI, CryptoKit, Security, os only). Dependabot alerts and security updates are enabled. |
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
- **Old session key removed:** the UserDefaults value from earlier builds is deleted on launch, so it can't be used as a backdoor.

### Owner decisions (I did not do these without you)

1. **Commit email:** every commit carries `kanaman@brandeis.edu` as its author, and that is public on a public repo. Options: use GitHub's `noreply` address for future commits (no history change), or also rewrite history (destructive force-push). I recommend the first.
2. **Two-factor authentication on GitHub:** use a passkey or hardware key. This is in your account settings; my token can't see or change it.

### Residual risk

- Files are encrypted, but while you are signed in the data key is in the Keychain. Someone using your
  unlocked, signed-in device can see your paper book, just as they could see the screen. Signing out locks it.
- Market data comes from free, unauthenticated sources. It can be delayed or change format, so quotes are never
  executable prices.

## When the backend exists

The backend planned for push alerts and sync must ship with: TLS only; HSTS, CSP, `X-Content-Type-Options`,
`Referrer-Policy` and `frame-ancestors 'none'`; a CORS allow-list with no `*`; session cookies (if web) that
are `Secure`, `HttpOnly` and `SameSite=Strict`, with CSRF tokens; parameterized SQL only; server-side
validation that mirrors KestrelCore; per-IP and per-account rate limits; single-use reset tokens that expire
in 15 minutes and are stored hashed; secrets in a secret manager, never in env files committed to git; and
uploads (if any) restricted by type sniffing and size. These rows move from N/A to tested at that point.
