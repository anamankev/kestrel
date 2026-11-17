# Gap list

What a desk user would reach for in Bloomberg that Kestrel does not have yet, ranked by value per
effort under the free-data rule. Done items move to the README.

| # | Gap | Bloomberg analogue | Data | Status |
|---|---|---|---|---|
| 1 | Accounts: sign up, sign in, per-user portfolios, watchlists and alerts | Login / user profile | On device | Done |
| 2 | Option strategy builder: legs, payoff at expiry and today, greeks of the package, breakevens | `OSA` | Deribit + Black-76 | Done |
| 3 | Strategy backtester on daily history (SMA cross, RSI, Bollinger), with equity curve, CAGR, Sharpe, max drawdown | `BT` / `BTST` | Yahoo / Coinbase history | Done |
| 4 | News search and keyword filter across all feeds | `NSE` / `N` | RSS | Next |
| 5 | Earnings calendar across the watchlist | `ERN` / `EVTS` | SEC (needs contact) | Later |
| 6 | Equity screener (sector, market cap, P/E, move) | `EQS` | Needs a screener feed; free sources are thin | Later |
| 7 | Background alerts when the app is closed | `ALRT` push | Needs the backend | With backend |
| 8 | Sync across iPad and Mac | Bloomberg Anywhere | Needs the backend | With backend |
| 9 | Live US equities | Real-time tape | Alpaca free (user's own key, IEX only) | With backend |

Known bug: on iPad, after the on-screen keyboard closes, the bottom key bar can sit ~60 pt high with a
black strip below it until the next layout pass.
