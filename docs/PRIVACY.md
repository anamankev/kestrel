# Kestrel privacy policy

*Last updated: November 17, 2026*

Kestrel is a market terminal for iPad and Mac. This policy says what it does with your information.

**What stays on your device.** Your account (name, email, and a salted PBKDF2 hash of your password, never the
password itself), your paper-trading book, watchlists, alerts and settings are stored only on your device,
encrypted with a key that your password unlocks. There is no Kestrel server and no Kestrel account database. We
cannot see, recover or delete your data; deleting your account in the app removes it from the device.

**What leaves your device.**
- Requests for public market data go to Coinbase, Yahoo Finance, Deribit, the U.S. Bureau of Labor Statistics,
  the Federal Reserve Bank of New York and public news feeds (CNBC, MarketWatch, CoinDesk, Yahoo). These requests
  contain the symbols you view, not your identity.
- If you add an SEC contact email in Settings, it is sent only to the SEC (sec.gov), in the User-Agent header the
  SEC requires of every application.
- Subscriptions are processed by Apple. Kestrel receives only Apple's signed confirmation of which plan is
  active; it never sees your payment details.
- A transfer file you export is encrypted with a passphrase you choose and goes wherever you send it.

**What we don't do.** No analytics, advertising, tracking, data sale, or third-party SDKs.

**Children.** Kestrel is not directed to children under 13.

**Contact.** Open an issue at https://github.com/anamankev/kestrel/issues.
