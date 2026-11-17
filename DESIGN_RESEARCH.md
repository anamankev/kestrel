# Bloomberg Terminal: how it looks and works (research, 2026-11-16)

Goal: learn the Terminal's design language so our iPad terminal feels just as professional,
with its **own name, colors and identity** (Bloomberg protects its amber-on-black look as a brand asset).

## 1. Visual look
- **Black background, amber text.** Amber is the base font color. Bloomberg calls it the
  company's strongest visual hallmark. Unofficial hex values: amber about `#FFA028`, black about `#0B0B0B`.
- **Semantic colors on top of amber:** green = up, red = down. Values are white or yellow, labels are amber.
  Selected rows and fields are highlighted with filled blocks. Heatmaps use green and red tiles.
- **Extreme density.** Monospaced-feeling grids with no padding. Each screen holds dozens of
  tables, sparklines, charts and pies at once. Traders read this as "pro", and critics call it hideous.
- **Color accessibility:** about 20,000 users have color-vision deficiency, so Bloomberg offers alternate
  palettes besides red and green.
- **Very conservative.** Even a font change or a moved button is treated as disruptive.
  Bloomberg's UX strategy is to "conceal complexity" and evolve, never redesign.

## 2. Layout
- **2–6 monitors.** The Core Terminal has **4 Panels**, each a full window with its own command line.
- **Launchpad (`BLP <GO>`):** a free-form canvas of small, always-live **components**: monitors
  (watchlists), charts, news tickers, IB chat and the Launchpad "worksheets". Users save layouts as views.
- Each panel has a **title bar** (function name, security), a **red-on-black menu row**
  of numbered actions (`1) Actions 2) Settings`), then the data area.
- A **news ticker and headlines** are on screen almost everywhere.

## 3. Interaction model (the actual heart of it)
- **Command line in every panel.** The syntax is `TICKER [EXCHANGE] <YELLOW KEY> FUNCTION <GO>`,
  for example `AAPL US <EQUITY> GP <GO>` or `VOD LN <EQUITY> DES <GO>`.
- **Color-coded keyboard:** yellow sector keys (`<EQUITY>`, `<CORP>`, `<CURNCY>`, `<INDEX>`, `<CMDTY>`),
  green `<GO>` (Enter), red `<CANCEL>` (Esc), plus `<MENU>` (back) and `<HELP>`.
- **Numbered hotspots:** type `1 <GO>` to drill into row or menu item 1. Everything is reachable by keyboard.
- **Autocomplete** suggests securities and functions as you type in the command line.

## 4. Most-used functions (from university training guides)
| Code | What it is |
|------|------------|
| `DES` | Security description: the starting point for any security |
| `GP` / `GPO` / `GIP` | Price chart (line), OHLC/candles, intraday |
| `FA` | Financial analysis: income statement, balance sheet, ratios |
| `HP` | Historical price table |
| `CN` / `N` / `TOP` | Company news, the news menu, top news |
| `WEI` | World equity indices |
| `MOST` | Most active, gainers and losers |
| `W` / `MON` | Watchlist / monitor |
| `ECO` / `EVTS` | Economic calendar / corporate events |
| `IB` / `MSG` | Instant Bloomberg chat / messages |
| `BQL` | Query language (Excel `=BQL()`) |
| `EMSX` | Order execution management |

## 5. What this means for our iPad app
**What to keep (it's why Wall Street trusts it):**
- A command line in every panel, with yellow-key style asset classes and a GO key.
- 2–4 tiled panels, each running one function, with a Launchpad-style customizable grid.
- Extreme density, a black canvas, tabular monospaced digits, green/red ticks that flash on change.
- Numbered drill-down and full hardware-keyboard control (Magic Keyboard on iPad).

**What to do better (where iPad can beat the original):**
- Our **own palette.** Don't use amber/orange. Pick one accent color (for example electric cyan or phosphor
  green) and keep a CVD-safe up/down option from day one.
- **Touch and Pencil:** pinch charts, drag panels, and long-press a row to open it in another panel.
- **Modern typography:** SF Mono with tabular numerals. Same density, sharper rendering.
- **Fast rendering:** smooth 120 Hz ProMotion charts and order books, which Bloomberg's iPad app doesn't attempt.

**Honest gap (zero budget, free data):** no real-time US equities level 2, no bonds, FX forwards or
chat network. Live crypto (Coinbase public WebSocket), delayed equities and indices, RSS news.
The engineering (matching engine, rendering, concurrency) has to carry the impression.

## Sources
- [Tech at Bloomberg: customer-centric design ethos](https://www.bloomberg.com/company/stories/bloombergs-customer-centric-design-ethos)
- [Tech at Bloomberg: designing the Terminal for color accessibility](https://www.techatbloomberg.com/blog/designing-the-terminal-for-color-accessibility/)
- [How Bloomberg Terminal UX designers conceal complexity](https://www.bloomberg.com/company/stories/how-bloomberg-terminal-ux-designers-conceal-complexity)
- [Relaunching Launchpad](https://www.bloomberg.com/ux/2017/11/10/relaunching-launchpad-disguising-ux-revolution-within-evolution/)
- [Wikipedia: Bloomberg Terminal](https://en.wikipedia.org/wiki/Bloomberg_Terminal)
- [UX Magazine: The impossible Bloomberg makeover](https://uxmag.com/articles/the-impossible-bloomberg-makeover)
- [Fast Company: The Bloomberg Terminal](https://www.fastcompany.com/3051883/the-bloomberg-terminal)
- [CFI: Bloomberg functions list](https://corporatefinanceinstitute.com/resources/data/bloomberg-functions-shortcuts-list)
- [U. Delaware Lerner: Bloomberg functions list](https://lerner.udel.edu/seeing-opportunity/bloomberg-functions-list/)
- [webdesignhot: Bloomberg design reference](https://www.webdesignhot.com/design.md/bloomberg/) (unofficial hex values)
