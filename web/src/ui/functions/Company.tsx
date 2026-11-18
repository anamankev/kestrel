import type { Instrument } from "../../core/instrument";
import { compact } from "../../core/format";
import { fyMetrics, earningsEstimate, type FiscalYear } from "../../core/sec";
import { dividendSummary, csv, csvNum } from "../../core/quant";
import { instrument, resolve } from "../../core/universe";
import { cik, dividends, filings, fundamentals, releases } from "../../data/research";
import { market } from "../../data/market";
import { useStore } from "../../data/store";
import { userData, workspace } from "../../data/workspace";
import { Empty, Section, Tile } from "../components";
import { Bars, ExportCSV } from "../charts";
import { useAsync } from "../useAsync";

const pctOf = (v?: number | null, d = 1) => (v == null || !Number.isFinite(v) ? "—" : `${(v * 100).toFixed(d)}%`);
const isoDay = (t: number) => new Date(t).toISOString().slice(0, 10);
const niceDay = (t: number) => new Date(t).toLocaleDateString("en-US", { year: "numeric", month: "short", day: "numeric", timeZone: "UTC" });

/** FA: 10-K financials from SEC company facts. */
export function Financials({ i }: { i: Instrument }) {
  useStore(market);
  const s = useAsync(async () => { const c = await cik(i); return c ? fundamentals(c) : null; }, [i.symbol]);
  if (i.assetClass !== "EQUITY") return <Empty title={`No SEC filings for ${i.ticker}`} detail="FA covers US-listed companies that file 10-Ks. ETFs, indices, FX and crypto don't file." />;
  if (s.loading) return <Empty title="Loading 10-K data from SEC…" />;
  if (s.error) return <Empty title="SEC request failed" detail={s.error} />;
  const f = s.data;
  if (!f || !f.years.length) return <Empty title={`No SEC filings for ${i.ticker}`} detail="FA covers US-listed companies that file 10-Ks with the SEC." />;
  const last = f.years[f.years.length - 1], q = market.quotes.get(i.symbol);
  const cap = f.sharesOutstanding && q ? f.sharesOutstanding * q.last : undefined;
  const pe = last.epsDiluted && last.epsDiluted > 0 && q ? q.last / last.epsDiluted : undefined;
  const rows: [string, (y: FiscalYear) => string][] = [
    ["Revenue", (y) => compact(y.revenue)], ["Gross profit", (y) => compact(y.grossProfit)], ["Operating income", (y) => compact(y.operatingIncome)],
    ["Net income", (y) => compact(y.netIncome)], ["EPS (diluted)", (y) => (y.epsDiluted == null ? "—" : y.epsDiluted.toFixed(2))],
    ["Gross margin", (y) => pctOf(fyMetrics(y).grossMargin)], ["Operating margin", (y) => pctOf(fyMetrics(y).operatingMargin)], ["Net margin", (y) => pctOf(fyMetrics(y).netMargin)],
    ["Operating cash flow", (y) => compact(y.operatingCashFlow)], ["Capex", (y) => compact(y.capex)], ["Free cash flow", (y) => compact(fyMetrics(y).freeCashFlow)],
    ["Cash", (y) => compact(y.cash)], ["Long-term debt", (y) => compact(y.longTermDebt)], ["Equity", (y) => compact(y.equity)], ["Total assets", (y) => compact(y.assets)],
    ["Return on equity", (y) => pctOf(fyMetrics(y).roe)], ["Debt / equity", (y) => { const d = fyMetrics(y).debtToEquity; return d == null ? "—" : d.toFixed(2); }],
  ];
  const growth = (k: "revenue" | "netIncome") => { const a = f.years[f.years.length - 2]?.[k], b = last[k]; return a && b != null ? (b - a) / Math.abs(a) : null; };
  return (
    <div>
      <div className="tiles">
        <Tile k="MARKET CAP" v={compact(cap)} s="SHARES × LAST" /><Tile k="P/E (FY)" v={pe ? `${pe.toFixed(1)}x` : "—"} s={`FY${last.year} DILUTED EPS`} />
        <Tile k="REVENUE GROWTH" v={pctOf(growth("revenue"))} s="YEAR OVER YEAR" /><Tile k="NET INCOME GROWTH" v={pctOf(growth("netIncome"))} s="YEAR OVER YEAR" />
      </div>
      <Section title={`${f.name.toUpperCase()} · ANNUAL (10-K) · SEC EDGAR`} right={<ExportCSV name={`${i.ticker}-financials.csv`} build={() => csv(["Metric", ...f.years.map((y) => `FY${y.year}`)], rows.map(([n, fn]) => [n, ...f.years.map(fn)]))} />} />
      <table className="t"><thead><tr><th>USD</th>{f.years.map((y) => <th key={y.year}>FY{y.year}</th>)}</tr></thead>
        <tbody>{rows.map(([n, fn]) => <tr key={n}><td style={{ fontFamily: "var(--ui)" }}>{n}</td>{f.years.map((y) => <td key={y.year}>{fn(y)}</td>)}</tr>)}</tbody></table>
      <p className="faint" style={{ fontSize: 10, padding: 8 }}>Source: SEC EDGAR XBRL company facts. Fiscal years end {niceDay(last.periodEnd)}; last filed {f.lastFiled ? niceDay(f.lastFiled) : "—"}.</p>
    </div>
  );
}

/** EVTS: SEC filings and corporate events. */
export function Events({ i }: { i: Instrument }) {
  const s = useAsync(async () => { const c = await cik(i); return c ? filings(c) : null; }, [i.symbol]);
  if (i.assetClass !== "EQUITY") return <Empty title={`No SEC filings for ${i.ticker}`} detail="EVTS covers US-listed companies." />;
  if (s.loading) return <Empty title="Loading filings from SEC…" />;
  if (s.error) return <Empty title="SEC request failed" detail={s.error} />;
  if (!s.data?.length) return <Empty title={`No SEC filings for ${i.ticker}`} />;
  const insiders = s.data.filter((f) => f.form === "4"), rest = s.data.filter((f) => f.form !== "4");
  return (
    <div>
      <Section title={`${i.ticker} · SEC FILINGS`} right={`${insiders.length} INSIDER TRANSACTIONS (FORM 4) RECENTLY`} />
      {rest.map((f) => (
        <a key={f.url} href={f.url} target="_blank" rel="noopener noreferrer" style={{ display: "flex", gap: 12, padding: "7px 8px", borderBottom: "1px solid var(--rule)", color: "var(--text)", textDecoration: "none" }}>
          <span className="mono dim" style={{ fontSize: 11, width: 90, flex: "none" }}>{isoDay(f.date)}</span>
          <span className="mono" style={{ fontSize: 11, width: 60, flex: "none", color: f.isEarnings ? "var(--warn)" : "var(--label)" }}>{f.form}</span>
          <span style={{ fontSize: 13 }}>{f.title}</span>
        </a>
      ))}
    </div>
  );
}

/** DVD: ten years of dividends. */
export function Dividends({ i }: { i: Instrument }) {
  useStore(market);
  const s = useAsync(() => dividends(i), [i.symbol]);
  if (s.loading) return <Empty title="Loading dividends…" />;
  if (s.error) return <Empty title="Couldn't load dividends" detail={s.error} />;
  const divs = s.data!.dividends, sum = dividendSummary(divs, market.quotes.get(i.symbol)?.last ?? s.data!.price);
  if (!sum) return <Empty title="No cash dividends in the last 10 years" detail={`${i.ticker} hasn't paid a dividend in this period.`} />;
  const amt = (v: number) => (v >= 0.1 ? v.toFixed(2) : v.toFixed(4));
  const freq = ({ 12: "MONTHLY", 4: "QUARTERLY", 2: "SEMIANNUAL", 1: "ANNUAL", 0: "IRREGULAR" } as Record<number, string>)[sum.paymentsPerYear] ?? `${sum.paymentsPerYear}× A YEAR`;
  const first = sum.annual[0], years = first && first.count < sum.paymentsPerYear ? sum.annual.slice(1) : sum.annual, thisYear = new Date().getUTCFullYear();
  return (
    <div>
      <div className="toolbar"><span className="spacer" /><ExportCSV name={`${i.ticker}-dividends.csv`} build={() => csv(["Ex-date", "Amount"], divs.map((d) => [isoDay(d.date), csvNum(d.amount)]))} /></div>
      <div className="tiles">
        <Tile k="TRAILING 12M" v={amt(sum.trailing12M)} s="PER SHARE" className="accent" />
        <Tile k="YIELD (TTM)" v={sum.yield != null ? `${(sum.yield * 100).toFixed(2)}%` : "—"} s="ON THE LAST PRICE" />
        <Tile k="5Y GROWTH" v={sum.growth5Y != null ? `${sum.growth5Y > 0 ? "+" : ""}${(sum.growth5Y * 100).toFixed(1)}%` : "—"} s="CAGR, COMPLETE YEARS" className={sum.growth5Y != null ? (sum.growth5Y >= 0 ? "up" : "down") : ""} />
        <Tile k="FREQUENCY" v={freq} s={`LAST ${amt(divs[divs.length - 1].amount)} · ${niceDay(divs[divs.length - 1].date).toUpperCase()}`} />
      </div>
      <div style={{ padding: 8 }}><Bars items={years.map((a) => ({ label: String(a.year), value: a.total, dim: a.year === thisYear }))} format={amt} /></div>
      <table className="t"><thead><tr><th>EX-DATE</th><th>AMOUNT</th><th>CHANGE</th></tr></thead>
        <tbody>{[...divs].reverse().map((d, k, arr) => { const prev = arr[k + 1]; const ch = prev ? d.amount / prev.amount - 1 : null;
          return <tr key={d.date}><td>{niceDay(d.date)}</td><td>{amt(d.amount)}</td><td className={ch == null || Math.abs(ch) < 0.0005 ? "faint" : ch > 0 ? "up" : "down"}>{ch == null || Math.abs(ch) < 0.0005 ? "—" : `${ch > 0 ? "+" : ""}${(ch * 100).toFixed(1)}%`}</td></tr>; })}</tbody></table>
    </div>
  );
}

/** ERN: projected earnings dates for the watchlist's companies. */
export function EarningsCalendar({ panel }: { panel: number }) {
  useStore(userData);
  const list = userData.active.symbols.map((s) => instrument(s) ?? resolve(s)).filter((i): i is Instrument => !!i && i.assetClass === "EQUITY").slice(0, 40);
  const s = useAsync(async () => Promise.all(list.map(async (i) => { try { const c = await cik(i); return { i, est: c ? earningsEstimate(await releases(c)) : null }; } catch { return { i, est: null }; } })), [userData.active.id, list.length]);
  if (!list.length) return <Empty title={`No equities on ${userData.active.name}`} detail="Add stocks with W, then come back to ERN." />;
  if (s.loading) return <Empty title={`Loading earnings history for ${list.length} companies from SEC…`} />;
  const rows = (s.data ?? []).filter((r) => r.est).sort((a, b) => a.est!.next - b.est!.next);
  return (
    <div>
      <Section title={`EARNINGS · ${userData.active.name.toUpperCase()}`} right={`${rows.length} OF ${list.length} COMPANIES · SEC EDGAR`} />
      <table className="t"><thead><tr><th>COMPANY</th><th>NEXT (EST.)</th><th>±</th><th>IN</th><th>LAST RELEASE</th></tr></thead>
        <tbody>{rows.map(({ i, est }) => (
          <tr key={i.symbol} className="click" tabIndex={0} onClick={() => workspace.load({ fn: "EVST", instrument: i }, panel)}>
            <td><b>{i.ticker}</b> <span className="dim" style={{ fontFamily: "var(--ui)", fontSize: 11 }}>{market.displayName(i)}</span></td>
            <td>{niceDay(est!.next)}</td><td className="dim">{est!.spreadDays != null ? `${Math.round(est!.spreadDays)}d` : "—"}</td>
            <td>{Math.max(0, Math.round((est!.next - Date.now()) / 86_400_000))}d</td><td className="dim">{niceDay(est!.last)}</td>
          </tr>
        ))}</tbody></table>
      <p className="faint" style={{ fontSize: 10, padding: 8 }}>Estimated: last earnings release (8-K item 2.02) plus the company's median gap between releases; ± is the median deviation. Tap a company for its earnings event study.</p>
    </div>
  );
}

