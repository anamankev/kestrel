# Kestrel vs the Bloomberg Terminal

*November 2026. Sources: Bloomberg's own "Terminal Essentials" playlist (8 videos), university library guides,
and pricing reports, linked at the end.*

## The one-line answer

Bloomberg is the best data network in finance at **about $32,000 a year** per seat, and students mostly reach it
on a **booked library terminal with delayed data and download caps**. Kestrel gives students, early-career workers
and researchers the **same command-line workflow** plus the research methods they actually need (screening,
regressions, factor models, event studies, backtests, paper trading) for **$99.99 a year**, on their own iPad, Mac or
browser, with unlimited CSV exports.

## What Bloomberg costs and how students actually get it

- **Price:** about **$31,980 a year** for one seat ($2,665 a month) on two-year contracts. About $28,320 per seat
  for two or more seats, rising to about $33,840 from 2027. Exchange fees are billed separately.
- **Universities:** terminals are for current members only, often **on-site only** (Johns Hopkins, Purdue, Boston
  University) and **booked by the hour** (Purdue, Yale). Some schools give priority to business school or graduate
  students (St Andrews, Berkeley).
- **Educational terminals** often have **no trading module and 15-minute delayed data** (NYU). They also have
  **monthly download caps** for the Excel add-in (Columbia), so students are told to ration downloads.
- **Bloomberg Market Concepts (BMC):** an 8-hour self-paced certificate taught at more than 900 universities.
  Students take it to show recruiters they "know Bloomberg".

## Area by area: the 8 videos vs Kestrel

| Playlist video | What Bloomberg shows | Kestrel today | Verdict |
|---|---|---|---|
| **1. Getting started** | Command line with yellow-key mnemonics, menus, HELP, IB messaging | Same model: `AAPL DES <GO>`, 38 functions with Bloomberg-style mnemonics and aliases, HELP, numbered hotspots, an offline guide that answers in plain English, 1/2/4/6 panels | ✅ Same workflow, easier to learn. ❌ No IB chat network |
| **2. Best equities functions** (EQS, WATC, RV, FA, DSCO, EE, ANR, BI) | Screen, watch, peer comparison, financials, consensus estimates, analyst ratings, Bloomberg Intelligence research | EQS (about 5,700 US filers), W, FA (SEC 10-K), DES, DVD, ERN, HP, BETA, FACT, EVST | ✅ EQS, FA, RV peer table, watchlists. ❌ EE estimates, ANR ratings, BI research |
| **3. FX** (FXIP, FXFC, monitors, price discovery) | FX portal, bank forecasts, dealer quotes | FX board (G10, crosses, EM, DXY), any pair charted, CORR cross-asset | ✅ Monitoring. ❌ Forecasts, dealer prices |
| **4. News and research** | Bloomberg News, morning briefs, worksheets, document search, broker research | TOP (multi-source search with "phrases" and -exclude), CN, EVTS (SEC filings), ALRT | ✅ Searchable public news and filings. ❌ No first-party newswire or broker research |
| **5. IB, Worksheets, Launchpad** | Chat with the whole industry, live sheets, saved layouts | W (live watchlists), PAGES (saved layouts), panels, CSV export | ✅ Launchpad and worksheets equivalents. ❌ IB |
| **6. Commodities** | Prices, fundamentals, seasonality, supply/demand, BNEF | COMD board (energy, metals, ags, livestock, index and Treasury futures), charts | ✅ Prices. ❌ Seasonality, supply/demand, inventories |
| **7. Charting** | Charts, studies, overlays, export | GP: 1D–5Y, SMA/Bollinger/VWAP/RSI, trendlines, VS overlay, PNG export; CSV via HP | ✅ Comparable for students |
| **8. Fixed income** (SRCH, YAS, ALLQ, WB, CRVF) | Bond search, yield and spread analytics, dealer quotes, world curves | RATES (UST 3M–30Y), GC (curve history, 10Y–2Y), YAS (price/yield, duration, convexity, DV01), ECO | ✅ Yield analytics for any fixed-coupon bond. ❌ No bond search or dealer quotes |

Kestrel also has things Bloomberg doesn't give students on a library terminal:
- **Paper trading with real risk numbers:** market, limit, stop and stop-limit orders, shorts with margin, and PORT
  with beta, VaR and expected shortfall. Educational Bloomberg terminals often have no trading module.
- **Research methods built in:** Fama-French and Carhart factor regressions (FACT), earnings event studies with CAR
  and t-stats (EVST), strategy backtests against buy-and-hold (BT), a Markowitz efficient frontier (MVO) and
  correlation matrices (CORR). On Bloomberg these usually mean exporting to Excel or Python and building them yourself.
- **Live crypto order book and tape** (DEPTH, TAS) and **BTC/ETH options** with greeks, the smile and a strategy
  builder (OMON, OSA).
- **Unlimited exports:** every table exports to CSV, with no monthly cap.
- **Access anywhere:** iPad, Mac and web, any time, with no booking, and offline-readable accounts that are encrypted
  on the device.

## Why each group would pay $99.99 a year

**Students (finance, economics, business)**
1. **Practise the Bloomberg workflow before the internship.** The commands match (DES, GP, FA, EQS, WEI, TOP, BETA),
   so they can drill what BMC teaches on their own iPad instead of waiting for a library slot.
2. **Do coursework and projects at home:** a beta regression, a factor model or an event study for a class
   assignment, exported to CSV.
3. **Learn trading without risking money:** $1M paper book, real order types, risk metrics.
4. **Price:** less than one textbook, and below Koyfin's paid tiers (up to $1,188 a year) and Yahoo Finance
   Premium (about $350 a year).

**Early-career workers (analysts, advisers, ops, people at firms without Bloomberg)**
1. A fast **morning screen**: WEI, MOST, HMAP, FX, RATES, ECO and TOP in a 6-panel page.
2. **Quick company checks**: DES, FA, EVTS, DVD, ERN and CN without opening five websites.
3. **Their own terminal**, separate from their employer's, with saved pages and alerts that follow them across iPad,
   Mac and web.

**Researchers (thesis writers, PhD students, faculty)**
1. **Ready-made empirical methods**: FF3/FF5/Carhart (FACT), event studies (EVST), backtests (BT) and MVO, each
   with the method stated on screen.
2. **No download caps**: Bloomberg's academic Excel limits are a known bottleneck, and Kestrel exports every table.
3. **Primary sources**: SEC XBRL, BLS, New York Fed, World Bank (217 countries), the Kenneth French library, all cited.

## Where Kestrel loses, honestly

- **Data depth:** no consensus estimates (EE), analyst ratings (ANR), broker research, bond prices, FX forecasts or
  commodity fundamentals. These come from licensed feeds that cost money.
- **Network:** IB messaging is why professionals keep Bloomberg, and it can't be copied.
- **Coverage:** fundamentals are US SEC filers only. Quotes are delayed about 15 minutes, except live crypto.
- **Data licensing:** stock quotes currently come from Yahoo's unofficial endpoints, which needs a licensed source
  before charging (noted earlier; deferred).
- **Credential:** Bloomberg has BMC; Kestrel has no certificate yet.

## Gaps closed (November 2026)

All six gaps found in this comparison are now built on the web, iPad and Mac, from free data at no new cost:

1. **RV (relative valuation):** peers under the same SEC SIC industry code (widened to the 3-digit group when sparse),
   closest in revenue, with P/E, P/S, P/B, margin, growth, ROE and leverage against the peer median. `AAPL RV`
2. **Excel and Python access:** every exportable table has COPY (tab-separated, pastes straight into Excel or
   `pandas.read_clipboard()`) beside EXPORT CSV.
3. **SEAS (seasonality):** average, median, share of up years, best and worst return by calendar month over 5, 10
   years or all history, from monthly total returns. `CL1 SEAS`
4. **GC and YAS:** the Treasury par curve today against 1 month, 1 year and 5 years ago, with 5 years of 10Y–2Y spread
   history (Treasury.gov); and a bond calculator for price ↔ yield, accrued interest (actual/actual), duration,
   convexity, DV01, spread to the Treasury curve and yield scenarios. `GC`, `YAS`
5. **LEARN:** four modules (Economics, Fixed Income, Currencies, Equities) of four drills each. Every drill opens a real
   function in the next panel and asks what it shows; a module badge is saved in the account. `LEARN`
6. **Chart image export:** PNG on GP saves the chart as drawn, with a title bar and timestamp.

Still not covered (they need paid data): consensus estimates (EE), analyst ratings (ANR), dealer bond quotes (ALLQ),
real-time exchange equities, and Bloomberg Intelligence research.

## Sources

- Bloomberg, [Terminal Essentials playlist](https://www.youtube.com/playlist?list=PLIDqCVGxWScUOoyL-74VQaesYlfjw02wa) (8 videos, 2024)
- Bloomberg, [Terminal Essentials: Best equities functions](https://www.bloomberg.com/professional/?p=81819)
- Pricing: [privateequitylist.com](https://privateequitylist.com/intelligence/bloomberg-terminal-cost), [costbench.com](https://www.costbench.com/software/financial-data-terminals/bloomberg-terminal/), [Koyfin](https://www.koyfin.com/blog/bloomberg-terminal-cost/)
- University access: [NYU](https://guides.nyu.edu/bloombergguide), [Johns Hopkins](https://guides.library.jhu.edu/bloomberg/general), [Purdue](https://guides.lib.purdue.edu/bloomberg), [Boston University](https://questromworld.bu.edu/tech/bloomberg-in-campus/), [Yale](https://guides.library.yale.edu/Bloomberg/bloomberg_getting_started), [St Andrews](https://libanswers.st-andrews.ac.uk/faq/262320), [Berkeley](https://ucberkeley.libanswers.com/business/faq/375635), [Columbia download limits](https://guides.library.columbia.edu/bloomberg/downloadlimit)
- BMC: [Washington College](https://www.washcoll.edu/learn-by-doing/opportunities-research/brown-advisory/BMC.php), [Bloomberg](https://spotlight.bloomberg.com/story/experience-the-financial-world-in-real-time/page/5)
- Functions: [CFI function list](https://corporatefinanceinstitute.com/resources/equities/bloomberg-functions-shortcuts-list/), [Michigan fixed income guide](https://kresgeguides.bus.umich.edu/bloomberg/FixedIncome), [UPenn Excel add-in](https://guides.library.upenn.edu/bloomberg/excel)
- Alternatives: [Hudson Labs](https://hudson-labs.com/post/free-and-low-cost-alternatives-to-bloomberg), [DataSetIQ](https://datasetiq.com/blog/bloomberg-terminal-alternatives)
