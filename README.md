# Kestrel: a pro trading terminal for iPad and Mac

A native SwiftUI market terminal built around a command line: type `AAPL GP`, `BTC DEPTH` or `WEI`, press GO.
It uses live data from free public sources and has paper trading built in.

## Run
Open `Kestrel.xcodeproj` in Xcode 26+, pick an **iPad simulator** or **My Mac**, then press ⌘R.
Core logic tests: `cd KestrelCore && swift test` (30 tests).

## Functions
| Security | Markets | Trading |
|---|---|---|
| `DES` description · `GP` chart · `DEPTH` L2 book · `TAS` time & sales · `OMON` options, smile & term structure · `CN` news | `W` monitor · `WEI` world indices · `MOST` movers · `HMAP` heat map · `FX` · `COMD` · `RATES` · `TOP` news | `TRADE` ticket (`SOL BUY`) · `PORT` P&L · `BLOT` orders & fills |

Keys: ⌘1–⌘6 focus a panel, ⌘[ back, ⌘↩ maximize, ⌘L layout, ↑↓/Tab for autocomplete, Esc to cancel.
Tap a row to **link** that security into every security panel. Long-press a row for its functions.

## Architecture
```
KestrelCore (Swift package, no UI, fully tested)
  Universe        security master + ticker resolution
  CommandParser   TICKER [EXCH] [CLASS] FUNCTION grammar + autocomplete
  OrderBook       price-level L2 book: snapshot + deltas, ladder, imbalance
  PaperAccount    Decimal cash/positions, market & limit orders, reservations, realized P&L
  Indicators      SMA, EMA, Bollinger, Wilder RSI, VWAP
  Options         Black-76 greeks, implied-vol solver, chain analytics (ATM IV, max pain, P/C)
  Decoders        Coinbase WS / REST, Yahoo chart, RSS (hardened)
Kestrel (SwiftUI app, iPadOS + macOS from one target)
  CoinbaseStream  actor: decodes ~100–200 msg/s off the main thread, coalesced to the UI at 10 Hz,
                  sequence-gap resync, backoff reconnect, stale-feed watchdog
  MarketStore     @Observable store; bounded-concurrency polling for delayed assets
  ChartView       single Canvas pass for candles, volume and studies (no per-candle views)
```

## Data (all free, no keys)
- **Crypto:** Coinbase Advanced Trade WebSocket, tick-by-tick, full L2 depth.
- **Equities, indices, FX, futures, rates:** Yahoo Finance chart endpoint (delayed snapshots).
- **Options:** Deribit public API (BTC, ETH), with greeks computed locally.
- **News:** CNBC, MarketWatch and CoinDesk RSS, plus Yahoo per-ticker headlines.

## Honest comparison with Bloomberg
Kestrel matches the terminal *workflow* (command line, linked panels, density, keyboard-first) and beats
Bloomberg's iPad app on touch and rendering. It does not have Bloomberg's data: there's no real-time
equity L2, fundamentals, fixed income or chat network, because those require paid exchange licences.

See [SECURITY.md](SECURITY.md) for the security review and [DESIGN_RESEARCH.md](DESIGN_RESEARCH.md) for the
design research.
