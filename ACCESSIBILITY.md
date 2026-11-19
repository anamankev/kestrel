# Kestrel accessibility

**Date:** 2026-11-18. **Target:** WCAG 2.2 level AA, on the web app and the iPad/Mac app.

## How it was checked

- **Web:** an automated axe-core 4.14 audit (WCAG 2.0, 2.1 and 2.2 A/AA rules) across all 38 function screens, the
  4-panel layout, the guide, sign-in, sign-up and the subscribe page. Result: **0 violations**. Before the fixes
  there were 4 kinds of failure on 17 or more screens (136 contrast failures alone).
- **Keyboard:** a real Enter key press on a focused watchlist row loaded that security into the linked panel, with a
  visible focus outline.
- **Colour:** WCAG contrast ratios were computed for every text colour on every surface the theme uses, in both apps.

## What was fixed

| Area | Before | After |
|------|--------|-------|
| Secondary text ("faint") | #46515E: 2.3–2.5:1 | #7A8694: ≥ 4.9:1 on every text surface (web and app) |
| Tertiary text ("dim") | 3.7:1 on highlighted rows | #95A1AF: ≥ 5:1 everywhere |
| Text on green/red/cancel buttons | white: 2.0–3.9:1 | dark text: 5.2–10:1 (order tickets, CXL, CANCEL, delete) |
| Heatmap tiles (HMAP) | light text on tiles up to 90% tint: down to 2:1 | tint capped at 50%: ≥ 5:1 |
| Correlation cells (CORR) | light text on strong cells: 1.7:1 | dark text on \|r\| ≥ 0.5 cells: ≥ 5:1 |
| Chart price tags (app) | white on up/down/amber | dark text (white kept on the dark accent, 5.7:1) |
| Clickable rows (15 tables) | mouse only | Tab to focus, Enter/Space to open, visible outline |
| Sortable headers (EQS, ECST) | mouse only | focusable, keyboard-operable, `aria-sort` |
| Panels | made active only by click | also made active by keyboard focus; scrollable bodies are focusable and named |
| GO button, account chip | name didn't match the visible text | "GO: run command", "TT: account menu for …" |
| Password field | announced "Password Show" | "Password"; the Show button is labelled and has `aria-pressed`; the strength hint is linked and announced |
| Guide | answers not announced | conversation is a polite live region |
| Segmented buttons | 18.5 px tall | ≥ 24 px (WCAG 2.2 target size) |
| App icon buttons | VoiceOver read symbol names | labelled: maximise/restore, steppers, strike and size steppers, clear search |
| App heatmap tiles | tap only, not exposed to VoiceOver | VoiceOver buttons with ticker and change |
| App text size | fixed point sizes | PREF → Text size (90–150%), multiplied by iPad Dynamic Type, capped at 150% |

## Known limits

- **Charts** (GP, payoffs, smiles) are images to screen readers. Each has a descriptive label, and the same data is
  available as tables: HP (history, CSV export), FA, DVD, BETA and EVST.
- **Option chain cells** (OMON) open trades by click. By keyboard, type the contract on the command line
  (for example `BTC-25DEC26-70000-C BUY`). The table itself is focusable and labelled with this tip.
- **App text size** was checked at 150% on the iPad Pro 13" simulator: DES, WEI, TRADE, OMON, EQS, PORT, W, TOP
  and the 4-panel layout. Column widths and row heights now grow with the text (291 fixed sizes scaled; unchanged at
  100%), so WEI tickers (MEXBOL, MERVAL, COLCAP) and news sources (MKTWATCH) no longer truncate or wrap. In the 4-panel
  layout, long security names abbreviate ("Ether…"), as at 100%, while tickers and prices stay whole. The Mac build
  compiles, but the Mac app at large sizes wasn't captured.
- **VoiceOver** (app) and **NVDA/JAWS** (web) haven't been run by hand. The checks above are automated or computed.

## Apple's accessibility audit (iPad)

`KestrelUITests/AccessibilityAuditTests` runs `performAccessibilityAudit` (all checks except Dynamic Type, which only
recognises Apple's text styles; Kestrel scales its own fonts, verified at 150%). It's opt-in:
`TEST_RUNNER_KESTREL_A11Y_AUDIT=1 xcodebuild test -scheme Kestrel -only-testing:KestrelUITests …`. It launches with
`-uitest` (debug only): a throwaway account, one panel, and live updates frozen after 20 s.

**Fixed from its findings:**
- **Unlabelled text fields.** The command line, news and security search, the watchlist add box, the screener
  filter, the alert level, the ticket's quantity, stop and limit fields, and the SEC email field were all
  unlabelled. They now have labels, and the command line has a hint and a 44 pt touch height.
- **Motion.** The ticker tape scrolled forever and ignored Reduce Motion (WCAG 2.2.2). It now stops for Reduce
  Motion and has a pause button; with motion off it scrolls by hand. The guide button no longer bobs under Reduce
  Motion. The web tape got the same pause button and pauses on hover.

**Touch targets, per platform (2026-11-18):**
- **iPad:** every button has a 44 pt touch target via one shared style (`TerminalButtonStyle`, 80 buttons). Bars
  that hold buttons (panel headers, ticker tape) are 44 pt. Visual sizes barely change.
- **Mac:** keeps the dense 20–28 pt controls normal for a pointer; the same style is plain there.
- **Web:** 44 px targets on touch screens only (`pointer: coarse`); mouse users keep the compact sizes. Measured on
  an emulated phone: no control under 44 px. On desktop the sizes are unchanged (keys 26 px).

**On the main screen, issues fell from 457 to 23 before the touch-target change:**
- **14 "hit area too small":** the function keys and tape tickers at 24 pt, now addressed on iPad as above.
- **6 "label not human-readable":** numeric cells such as "-5.17%".
- **3 contrast samples:** text next to overlays. The theme colours pass by calculation.

**Not finished:** on the other screens the audit times out, because panels still waiting for data keep a loading
indicator spinning once updates are frozen. Getting all 38 screens to audit needs a data fixture for test mode.

