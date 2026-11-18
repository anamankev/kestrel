import { useMemo, useState } from "react";
import type { Instrument } from "../../core/instrument";
import { compact, price } from "../../core/format";
import { alignedCloses, alignedReturns, adjustedBeta, backtest, calmar, car, carSummary, correlationMatrix, csv, csvNum, eventStudy, frontier, lastDay, linearFit, moments, ols, performance, rebased, returnStats, returns, sharpeOf, strategyLabel, tStat, winRate, yyyymmdd, type Strategy } from "../../core/quant";
import { MODELS, DESCRIBE } from "../../core/factors";
import { screenMetrics, type ScreenRow } from "../../core/sec";
import { instrument, resolve } from "../../core/universe";
import { cik, factors, history, releases, screen } from "../../data/research";
import { market } from "../../data/market";
import { useStore } from "../../data/store";
import { userData, workspace } from "../../data/workspace";
import { Empty, Section, Seg, Tile } from "../components";
import { Bars, ExportCSV, LineChart, Scatter, seriesColor } from "../charts";
import { useAsync } from "../useAsync";

const pc = (v?: number | null, d = 1, sign = true) => (v == null || !Number.isFinite(v) ? "—" : `${sign && v > 0 ? "+" : ""}${(v * 100).toFixed(d)}%`);
const tint = (v?: number | null) => (v == null || v === 0 ? "" : v > 0 ? "up" : "down");
const shortDate = (t: number) => new Date(t).toLocaleDateString("en-US", { month: "short", year: "2-digit", timeZone: "UTC" });
const isoDay = (t: number) => new Date(t).toISOString().slice(0, 10);
const riskFree = () => (market.quotes.get("^IRX")?.last ?? 0) / 100;
const perYear = (list: Instrument[]) => (list.every((i) => i.assetClass === "CRYPTO") ? 365 : 252);
const basket = (max: number) => { const seen = new Set<string>(); return userData.active.symbols.map((s) => instrument(s) ?? resolve(s)).filter((i): i is Instrument => !!i && i.assetClass !== "OPTION" && !seen.has(i.symbol) && !!seen.add(i.symbol)).slice(0, max); };
const keep = <T extends string>(key: string, def: T) => (localStorage.getItem(key) as T) ?? def;
function useSetting<T extends string = string>(key: string, def: NoInfer<T>): [T, (v: T) => void] { const [v, set] = useState<T>(() => keep(key, def)); return [v, (x) => { localStorage.setItem(key, x); set(x); }]; }

/** HP: price history with stats and CSV. */
export function History({ i }: { i: Instrument }) {
  const [span, setSpan] = useSetting("hp.span", "1y");
  const [weekly, setWeekly] = useSetting<"DAILY" | "WEEKLY">("hp.freq", "DAILY");
  const s = useAsync(() => history(i, span, { weekly: weekly === "WEEKLY" }), [i.symbol, span, weekly]);
  const bars = s.data ?? [];
  const st = returnStats(bars.map((b) => b.close), weekly === "WEEKLY" ? 52 : i.assetClass === "CRYPTO" ? 365 : 252);
  return (
    <div>
      <div className="toolbar">
        <Seg label="Span" value={span} options={["3mo", "6mo", "1y", "2y", "5y", "10y"]} onChange={setSpan} />
        <Seg label="Frequency" value={weekly} options={["DAILY", "WEEKLY"] as const} onChange={setWeekly} />
        <span className="spacer" />
        {bars.length > 0 && <ExportCSV name={`${i.ticker}-${span}-${weekly.toLowerCase()}.csv`} build={() => csv(["Date", "Open", "High", "Low", "Close", "Volume"], bars.map((b) => [isoDay(b.time), String(b.open), String(b.high), String(b.low), String(b.close), String(b.volume)]))} />}
      </div>
      {st && <div className="tiles"><Tile k="TOTAL RETURN" v={pc(st.totalReturn)} className={tint(st.totalReturn)} /><Tile k="ANN. VOLATILITY" v={pc(st.annualizedVolatility, 1, false)} /><Tile k="MAX DRAWDOWN" v={pc(st.maxDrawdown)} className="down" /><Tile k="BEST / WORST" v={`${pc(st.best)} / ${pc(st.worst)}`} s={`${st.periods} PERIODS`} /></div>}
      {s.loading ? <Empty title="Loading history…" /> : s.error ? <Empty title="History unavailable" detail={s.error} /> :
        <table className="t"><thead><tr><th>DATE</th><th>OPEN</th><th>HIGH</th><th>LOW</th><th>CLOSE</th><th>CHG</th><th>VOLUME</th></tr></thead>
          <tbody>{[...bars].reverse().slice(0, 400).map((b, k, arr) => { const prev = arr[k + 1]; const ch = prev ? b.close / prev.close - 1 : null;
            return <tr key={b.time}><td>{isoDay(b.time)}</td><td>{price(b.open, i.assetClass)}</td><td>{price(b.high, i.assetClass)}</td><td>{price(b.low, i.assetClass)}</td><td>{price(b.close, i.assetClass)}</td><td className={tint(ch)}>{pc(ch, 2)}</td><td className="dim">{compact(b.volume)}</td></tr>; })}</tbody></table>}
    </div>
  );
}

const BENCHMARKS = ["SPX", "CCMP", "RTY", "INDU", "UKX", "DAX", "SX5E", "NKY", "HSI", "BTC"];

/** BETA: OLS regression on a benchmark. */
export function Beta({ i }: { i: Instrument }) {
  useStore(market);
  const [bench, setBench] = useSetting("beta.bench", "SPX");
  const [win, setWin] = useSetting("beta.win", "2y");
  const [freq, setFreq] = useSetting<"DAILY" | "WEEKLY">("beta.freq", "WEEKLY");
  const b = resolve(bench)!;
  const s = useAsync(async () => {
    if (b.symbol === i.symbol) throw new Error("Pick a benchmark other than the security");
    const [a, m] = await Promise.all([history(i, win, { weekly: freq === "WEEKLY", adjusted: true }), history(b, win, { weekly: freq === "WEEKLY", adjusted: true })]);
    const al = alignedCloses({ a, m }), x = returns(al.closes.m ?? []), y = returns(al.closes.a ?? []);
    return { fit: ols(y, x), x, y, dates: al.dates.slice(1) };
  }, [i.symbol, bench, win, freq]);
  const periods = freq === "WEEKLY" ? 52 : i.assetClass === "CRYPTO" ? 365 : 252;
  const f = s.data?.fit;
  return (
    <div>
      <div className="toolbar">
        <select className="field" value={bench} onChange={(e) => setBench(e.target.value)} aria-label="Benchmark">{BENCHMARKS.map((x) => <option key={x}>{x}</option>)}</select>
        <Seg label="Window" value={win} options={["1y", "2y", "5y"]} onChange={setWin} />
        <Seg label="Frequency" value={freq} options={["DAILY", "WEEKLY"] as const} onChange={setFreq} />
        <span className="spacer" />
        {s.data && <ExportCSV name={`${i.ticker}-vs-${bench}.csv`} build={() => csv(["Date", `${bench} return`, `${i.ticker} return`], s.data!.x.map((v, k) => [isoDay(s.data!.dates[k]), csvNum(v), csvNum(s.data!.y[k])]))} />}
      </div>
      <Section title={`${i.ticker} VS ${bench} · OLS ON ${freq} TOTAL RETURNS`} right={f ? `${f.n} OBSERVATIONS · ${win.toUpperCase()}` : undefined} />
      {s.loading ? <Empty title="Computing…" /> : !f ? <Empty title={s.error ?? "Not enough shared history"} detail="Try a longer window or another benchmark." /> : <>
        <div className="tiles">
          <Tile k="RAW BETA" v={f.beta.toFixed(3)} s={`SE ${f.betaSE.toFixed(3)} · t ${tStat(f.beta, f.betaSE).toFixed(1)}`} className="accent" />
          <Tile k="ADJUSTED BETA" v={adjustedBeta(f.beta).toFixed(3)} s="BLUME 0.67 / 0.33" />
          <Tile k="ALPHA (ANNUAL)" v={pc(f.alpha * periods, 2)} s={`t ${tStat(f.alpha, f.alphaSE).toFixed(2)}`} className={tint(f.alpha)} />
          <Tile k="R²" v={f.r2.toFixed(3)} s={`CORRELATION ${f.correlation.toFixed(3)}`} />
          <Tile k="RESIDUAL VOL" v={pc(f.residualSD * Math.sqrt(periods), 1, false)} s="IDIOSYNCRATIC, ANNUAL" />
          <Tile k="SYSTEMATIC SHARE" v={`${(f.r2 * 100).toFixed(0)}%`} s="OF RETURN VARIANCE" />
        </div>
        <div style={{ padding: 8 }}><Scatter x={s.data!.x.map((v) => v * 100)} y={s.data!.y.map((v) => v * 100)} fit={{ alpha: f.alpha * 100, beta: f.beta }} xLabel={`${bench} RETURN %`} yLabel={`${i.ticker} RETURN %`} h={260} /></div>
        <p className="faint" style={{ fontSize: 10, padding: "0 8px 8px" }}>Raw beta = cov(r, rₘ) / var(rₘ). Adjusted beta = 0.67 × raw + 0.33 (Blume). Alpha is the intercept, annualized. |t| &gt; 2 is roughly 95% significance.</p>
      </>}
    </div>
  );
}

/** FACT: Fama-French factor regression. */
export function Factors({ i }: { i: Instrument }) {
  const [model, setModel] = useSetting("fact.model", "FF3");
  const [win, setWin] = useSetting("fact.win", "2y");
  const ok = i.assetClass === "EQUITY" || i.assetClass === "INDEX";
  const s = useAsync(async () => {
    if (!ok) return null;
    const [t, bars] = await Promise.all([factors(model), history(i, win, { adjusted: true })]);
    const rf = t.names.indexOf("RF"), idx = MODELS[model].factors.map((f) => t.names.indexOf(f));
    const y: number[] = [], cols: number[][] = idx.map(() => []), dates: number[] = [];
    for (let k = 1; k < bars.length; k++) {
      const d = yyyymmdd(bars[k].time), row = t.rows.get(d);
      if (!row || !(bars[k - 1].close > 0)) continue;
      y.push(bars[k].close / bars[k - 1].close - 1 - row[rf]); idx.forEach((c, j) => cols[j].push(row[c])); dates.push(d);
    }
    const ends = Math.max(...t.rows.keys());
    return { fit: linearFit(y, cols, MODELS[model].factors), first: dates[0], last: dates[dates.length - 1], ends };
  }, [i.symbol, model, win]);
  const day = (d?: number) => (d ? `${Math.floor(d / 10000)}-${String(Math.floor(d / 100) % 100).padStart(2, "0")}-${String(d % 100).padStart(2, "0")}` : "—");
  const f = s.data?.fit;
  if (!ok) return <Empty title="Factor models describe stock returns" detail="Load a US stock or ETF, e.g. MSFT FACT or SPY FACT." />;
  return (
    <div>
      <div className="toolbar">
        <Seg label="Model" value={model} options={Object.keys(MODELS)} onChange={setModel} />
        <Seg label="Window" value={win} options={["1y", "2y", "5y"]} onChange={setWin} />
        <span className="spacer" />
        {f && <ExportCSV name={`${i.ticker}-${model.replace(" ", "")}.csv`} build={() => csv(["Term", "Coefficient", "Std error", "t-stat"], f.terms.map((t) => [t.name, csvNum(t.coefficient, 8), csvNum(t.standardError, 8), csvNum(tStat(t.coefficient, t.standardError), 4)]))} />}
      </div>
      <Section title={`${i.ticker} · ${model} · DAILY EXCESS TOTAL RETURNS`} right={f ? `${f.n} DAYS · ${day(s.data!.first)} → ${day(s.data!.last)}` : s.loading ? "LOADING FACTORS…" : undefined} />
      {s.loading ? <Empty title="Loading factor data…" /> : !f ? <Empty title={s.error ?? "Not enough days overlap the factor data"} /> : <>
        <div className="tiles">
          <Tile k="ALPHA (ANNUAL)" v={pc(f.terms[0].coefficient * 252, 2)} s={`t ${tStat(f.terms[0].coefficient, f.terms[0].standardError).toFixed(2)}`} className={tint(f.terms[0].coefficient)} />
          <Tile k="MARKET BETA" v={f.terms[1].coefficient.toFixed(3)} s={`t ${tStat(f.terms[1].coefficient, f.terms[1].standardError).toFixed(1)}`} className="accent" />
          <Tile k="R² / ADJ. R²" v={f.r2.toFixed(3)} s={`ADJUSTED ${f.adjustedR2.toFixed(3)}`} />
          <Tile k="RESIDUAL VOL" v={pc(f.residualSD * Math.sqrt(252), 1, false)} s="ANNUALIZED, UNEXPLAINED" />
        </div>
        <table className="t"><thead><tr><th>FACTOR</th><th style={{ textAlign: "left" }}>MEANING</th><th>LOADING</th><th>STD ERR</th><th>T-STAT</th></tr></thead>
          <tbody>{f.terms.slice(1).map((t) => { const tv = tStat(t.coefficient, t.standardError); return (
            <tr key={t.name}><td><b>{t.name}</b></td><td style={{ textAlign: "left", fontFamily: "var(--ui)" }} className="dim">{DESCRIBE[t.name]}</td>
              <td>{t.coefficient > 0 ? "+" : ""}{t.coefficient.toFixed(3)}</td><td className="dim">{t.standardError.toFixed(3)}</td>
              <td className={Math.abs(tv) > 1.96 ? "accent" : "dim"}>{tv.toFixed(2)}{Math.abs(tv) > 2.58 ? " **" : Math.abs(tv) > 1.96 ? " *" : ""}</td></tr>); })}</tbody></table>
        <div style={{ padding: 8 }}><Bars items={f.terms.slice(1).map((t) => ({ label: t.name, value: t.coefficient }))} errors={f.terms.slice(1).map((t) => 1.96 * t.standardError)} format={(v) => v.toFixed(2)} /></div>
        <p className="faint" style={{ fontSize: 10, padding: "0 8px 8px" }}>Excess total return regressed on Fama-French factors from the Kenneth R. French Data Library (US stocks); data runs to {day(s.data!.ends)}. Alpha is annualized ×252; bars show ±1.96 standard errors.</p>
      </>}
    </div>
  );
}

/** EVST: earnings event study. */
export function EventStudyView({ i, panel }: { i: Instrument; panel: number }) {
  const [bench, setBench] = useSetting("evst.bench", "SPY");
  const [span, setSpan] = useSetting<"±5" | "±10">("evst.span", "±5");
  const w = span === "±5" ? 5 : 10;
  const s = useAsync(async () => {
    if (i.assetClass !== "EQUITY") return { kind: "na" as const };
    const c = await cik(i);
    if (!c) return { kind: "nosec" as const };
    const dates = await releases(c);
    const [a, m] = await Promise.all([history(i, "10y", { adjusted: true }), history(resolve(bench)!, "10y", { adjusted: true })]);
    return { kind: "ok" as const, study: eventStudy(a, m, dates, [-w, w]) };
  }, [i.symbol, bench, w]);
  const d = s.data;
  if (d?.kind === "na") return <Empty title="Event studies need a company that reports earnings" detail="Load a US-listed stock, e.g. NVDA EVST." />;
  if (d?.kind === "nosec") return <Empty title={`${i.ticker} doesn't file with the SEC`} detail="EVST needs earnings 8-Ks, so it covers US-listed companies." />;
  const st = d?.kind === "ok" ? d.study : null;
  const stat = (from: number, to: number) => { const r = st ? carSummary(st, from, to) : null; return r ? { v: pc(r.mean, 2), s: r.t != null ? `t ${r.t.toFixed(2)} · ${(r.positive * 100).toFixed(0)}% POSITIVE` : "", c: tint(r.mean) } : { v: "—", s: "", c: "" }; };
  const utc = (t: number) => new Date(t).toLocaleDateString("en-US", { year: "numeric", month: "short", day: "numeric", timeZone: "UTC" });
  const days = st ? Array.from({ length: 2 * w + 1 }, (_, k) => k - w) : [];
  return (
    <div>
      <div className="toolbar">
        <select className="field" value={bench} onChange={(e) => setBench(e.target.value)} aria-label="Benchmark">{["SPY", "QQQ", "IWM", "DIA"].map((x) => <option key={x}>{x}</option>)}</select>
        <Seg label="Window" value={span} options={["±5", "±10"] as const} onChange={setSpan} />
        <span className="spacer" />
        {st && <ExportCSV name={`${i.ticker}-earnings-event-study.csv`} build={() => csv(["Day 0", "Alpha", "Beta", "Estimation days", ...days.map((x) => `AR[${x}]`)], [...st.events, ...st.pending].map((e) => [isoDay(e.day0), csvNum(e.alpha, 8), csvNum(e.beta, 4), String(e.estimationDays), ...e.abnormal.map((a) => csvNum(a, 8))]))} />}
      </div>
      <Section title={`${i.ticker} · EARNINGS EVENT STUDY · MARKET MODEL VS ${bench}`} right={st ? `${st.events.length} RELEASES${st.pending.length ? ` · ${st.pending.length} IN PROGRESS` : ""}` : undefined} />
      {s.loading ? <Empty title="Loading earnings dates and prices…" /> : !st ? <Empty title={s.error ?? "No earnings releases with enough price history"} /> : <>
        {st.events.length > 0 && <>
          <div className="tiles">{([["CAR [−1, +1]", -1, 1], ["DAY 0 ABNORMAL", 0, 0], [`DRIFT [+2, +${w}]`, 2, w], [`RUN-UP [−${w}, −2]`, -w, -2]] as const).map(([k, a, b]) => { const x = stat(a, b); return <Tile key={k} k={k} v={x.v} s={x.s} className={x.c} />; })}</div>
          <div style={{ padding: 8 }}><LineChart x={days} series={[{ name: "CAAR %", values: st.caar.map((v) => v * 100), width: 2 }]} band={{ lo: st.caar.map((v, k) => (v - 1.96 * st.caarSE[k]) * 100), hi: st.caar.map((v, k) => (v + 1.96 * st.caarSE[k]) * 100) }} zero={0} xFormat={(v) => String(v)} yLabel="Cumulative abnormal return %" h={200} /></div>
        </>}
        <table className="t"><thead><tr><th>EARNINGS (DAY 0)</th><th>CAR [−1,+1]</th><th>DAY 0</th><th>DRIFT [+2,+{w}]</th><th>β (EST.)</th></tr></thead>
          <tbody>{[...st.pending.slice().reverse(), ...st.events.slice().reverse()].map((e) => { const L = lastDay(st, e);
            const a = L >= 1 ? car(st, e, -1, 1) : null, z = L >= 0 ? car(st, e, 0, 0) : null, dr = L >= w ? car(st, e, 2, w) : null;
            return <tr key={e.day0} className="click" tabIndex={0} onClick={() => workspace.load({ fn: "GP", instrument: i }, panel)}>
              <td>{utc(e.day0)} {L < w && <span className="badge" style={{ background: "var(--warn)", color: "var(--canvas)" }}>IN PROGRESS {L >= 0 ? "+" : ""}{L}/+{w}</span>}</td>
              <td className={tint(a)}>{pc(a, 2)}</td><td className={tint(z)}>{pc(z, 2)}</td><td className={tint(dr)}>{dr != null ? pc(dr, 2) : L >= 2 ? `~${pc(car(st, e, 2, L), 2)}` : "—"}</td><td className="dim">{e.beta.toFixed(2)}</td></tr>; })}</tbody></table>
        <p className="faint" style={{ fontSize: 10, padding: 8 }}>Day 0 is the first session on or after the earnings 8-K filing date (it can trail the announcement by a day or two); releases after the close move the stock on day +1. Market model fitted on up to 250 earlier sessions, excluding other earnings windows. Total returns; cross-sectional t-stats.</p>
      </>}
    </div>
  );
}

/** BT: strategy backtest vs buy-and-hold. */
export function Backtest({ i }: { i: Instrument }) {
  const [kind, setKind] = useSetting<"SMA CROSS" | "RSI" | "BOLLINGER">("bt.kind", "SMA CROSS");
  const [span, setSpan] = useSetting("bt.span", "5y");
  const strategy: Strategy = kind === "SMA CROSS" ? { kind: "sma", fast: 50, slow: 200 } : kind === "RSI" ? { kind: "rsi", period: 14, buyBelow: 30, sellAbove: 70 } : { kind: "bollinger", period: 20, k: 2 };
  const s = useAsync(async () => {
    const [bars, irx] = await Promise.all([history(i, span, { adjusted: true }), history(resolve("US3M")!, span).catch(() => [])]);
    const rfBy = new Map(irx.map((b) => [yyyymmdd(b.time), b.close / 100]));
    let last = 0;
    const rf = bars.map((b) => (last = rfBy.get(yyyymmdd(b.time)) ?? last));
    return backtest(bars, strategy, 5, i.assetClass === "CRYPTO" ? 365 : 252, rf);
  }, [i.symbol, kind, span]);
  const r = s.data;
  return (
    <div>
      <div className="toolbar">
        <Seg label="Strategy" value={kind} options={["SMA CROSS", "RSI", "BOLLINGER"] as const} onChange={setKind} />
        <Seg label="Period" value={span} options={["1y", "2y", "5y", "10y"]} onChange={setSpan} />
        <span className="spacer" />
        {r && <ExportCSV name={`${i.ticker}-backtest.csv`} build={() => csv(["Date", "Strategy", "Buy and hold"], r.dates.map((d, k) => [isoDay(d), csvNum(r.equity[k]), csvNum(r.benchmark[k])]))} />}
      </div>
      <Section title={`${i.ticker} · ${strategyLabel(strategy).toUpperCase()} · 5 BP PER TRADE`} right={r ? `${r.trades.length} TRADES` : undefined} />
      {s.loading ? <Empty title="Running backtest…" /> : !r ? <Empty title={s.error ?? "Not enough history"} /> : <>
        <div className="tiles">
          <Tile k="TOTAL RETURN" v={pc(r.totalReturn)} s={`BUY & HOLD ${pc(r.benchmarkReturn)}`} className={tint(r.totalReturn)} />
          <Tile k="CAGR" v={pc(r.cagr)} className={tint(r.cagr)} /><Tile k="SHARPE" v={r.sharpe?.toFixed(2) ?? "—"} s={`EXCESS OF T-BILLS (${(r.riskFree * 100).toFixed(2)}%)`} />
          <Tile k="SORTINO" v={r.sortino?.toFixed(2) ?? "—"} /><Tile k="VOLATILITY" v={pc(r.volatility, 1, false)} /><Tile k="MAX DRAWDOWN" v={pc(-r.maxDrawdown)} className="down" />
          <Tile k="CALMAR" v={calmar(r)?.toFixed(2) ?? "—"} /><Tile k="WIN RATE" v={winRate(r) != null ? `${(winRate(r)! * 100).toFixed(0)}%` : "—"} /><Tile k="TIME IN MARKET" v={`${(r.exposure * 100).toFixed(0)}%`} />
        </div>
        <div style={{ padding: 8 }}><LineChart x={r.dates} series={[{ name: "Strategy", values: r.equity, width: 2 }, { name: "Buy & hold", values: r.benchmark, color: "var(--dim)" }]} zero={1} xFormat={shortDate} yLabel="Growth of $1" h={240} /></div>
        <p className="faint" style={{ fontSize: 10, padding: "0 8px 8px" }}>No look-ahead: signals at the close act at the next open. Idle cash earns the 13-week T-bill. Total returns (dividends reinvested).</p>
      </>}
    </div>
  );
}

const WINDOWS = ["3mo", "6mo", "1y", "2y", "5y"];

/** COMP: rebased total-return comparison of the watchlist. */
export function Compare({ panel }: { panel: number }) {
  useStore(userData); useStore(market);
  const [win, setWin] = useSetting("comp.win", "1y");
  const list = basket(8);
  const s = useAsync(async () => {
    const h = Object.fromEntries((await Promise.all(list.map(async (i) => [i.symbol, await history(i, win, { adjusted: true }).catch(() => [])] as const))).filter(([, c]) => c.length >= 20));
    return alignedCloses(h);
  }, [win, list.map((i) => i.symbol).join()]);
  if (list.length < 2) return <Empty title="Need two or more securities" detail="COMP compares the active watchlist. Add symbols with W or SECF." />;
  const al = s.data, kept = al ? list.filter((i) => al.closes[i.symbol]) : [];
  const rf = riskFree(), ppy = perYear(list);
  return (
    <div>
      <div className="toolbar"><Seg label="Window" value={win} options={WINDOWS} onChange={setWin} /><span className="spacer" />
        {al && <ExportCSV name={`comparison-${win}.csv`} build={() => csv(["Date", ...kept.map((i) => i.ticker)], al.dates.map((d, k) => [isoDay(d), ...kept.map((i) => csvNum(al.closes[i.symbol][k]))]))} />}</div>
      <Section title={`TOTAL RETURN · REBASED TO 100 · ${userData.active.name.toUpperCase()}`} right={al ? `${al.dates.length} SHARED SESSIONS` : undefined} />
      {s.loading ? <Empty title="Loading…" /> : !al || kept.length < 2 ? <Empty title="Not enough shared history" /> : <>
        <div style={{ padding: 8 }}><LineChart x={al.dates} series={kept.map((i, k) => ({ name: i.ticker, values: rebased(al.closes[i.symbol]), color: seriesColor(k) }))} zero={100} xFormat={shortDate} yLabel="Rebased total return" h={240} /></div>
        <table className="t"><thead><tr><th>SECURITY</th><th>TOTAL</th><th>ANN. RETURN</th><th>ANN. VOL</th><th>SHARPE</th><th>MAX DD</th></tr></thead>
          <tbody>{kept.map((i, k) => { const p = performance(al.closes[i.symbol], ppy, rf); return (
            <tr key={i.symbol} className="click" tabIndex={0} onClick={() => workspace.link(i, panel)}>
              <td><span style={{ display: "inline-block", width: 10, height: 3, background: seriesColor(k), marginRight: 6, verticalAlign: "middle" }} /><b>{i.ticker}</b></td>
              <td className={tint(p?.totalReturn)}>{pc(p?.totalReturn)}</td><td className={tint(p?.annualizedReturn)}>{pc(p?.annualizedReturn)}</td>
              <td>{pc(p?.annualizedVol, 1, false)}</td><td>{p?.sharpe?.toFixed(2) ?? "—"}</td><td className="down">{pc(p?.maxDrawdown)}</td></tr>); })}</tbody></table>
        <p className="faint" style={{ fontSize: 10, padding: 8 }}>Sharpe uses the 13-week T-bill ({(rf * 100).toFixed(2)}%). Total returns (dividends reinvested) on shared trading days.</p>
      </>}
    </div>
  );
}

/** MVO: long-only efficient frontier for the watchlist. */
export function Optimizer({ panel }: { panel: number }) {
  useStore(userData); useStore(market);
  const [win, setWin] = useSetting("mvo.win", "2y");
  const list = basket(12);
  const s = useAsync(async () => {
    const h = Object.fromEntries((await Promise.all(list.map(async (i) => [i.symbol, await history(i, win, { adjusted: true }).catch(() => [])] as const))).filter(([, c]) => c.length >= 40));
    const kept = list.filter((i) => h[i.symbol]), r = alignedReturns(h), m = moments(kept.map((i) => r[i.symbol]), perYear(kept));
    if (!m) return null;
    const f = frontier(m.mu, m.cov, riskFree());
    return f && { kept, mu: m.mu, vol: m.cov.map((row, k) => Math.sqrt(row[k])), ...f, days: r[kept[0].symbol]?.length ?? 0 };
  }, [win, list.map((i) => i.symbol).join()]);
  if (list.length < 2) return <Empty title="Need two or more securities" detail="MVO optimizes the active watchlist (up to 12). Add symbols with W or SECF." />;
  const o = s.data, rf = riskFree();
  return (
    <div>
      <div className="toolbar"><Seg label="Window" value={win} options={["1y", "2y", "5y"]} onChange={setWin} /><span className="spacer" />
        {o && <ExportCSV name={`optimizer-${win}.csv`} build={() => csv(["Asset", "Annual return", "Annual volatility", "Min variance weight", "Max Sharpe weight"], o.kept.map((a, k) => [a.ticker, csvNum(o.mu[k]), csvNum(o.vol[k]), csvNum(o.minVariance.weights[k]), csvNum(o.maxSharpe.weights[k])]))} />}</div>
      <Section title={`EFFICIENT FRONTIER · LONG ONLY · ${userData.active.name.toUpperCase()}`} right={o ? `${o.days} DAILY RETURNS · ${o.kept.length} ASSETS` : undefined} />
      {s.loading ? <Empty title="Optimizing…" /> : !o ? <Empty title="Not enough shared history" /> : <>
        <div className="tiles">
          <Tile k="MAX SHARPE · RETURN" v={pc(o.maxSharpe.expectedReturn)} s={`VOL ${pc(o.maxSharpe.volatility, 1, false)}`} className="accent" />
          <Tile k="MAX SHARPE · RATIO" v={sharpeOf(o.maxSharpe, rf).toFixed(2)} s={`RF ${(rf * 100).toFixed(2)}% (13W T-BILL)`} />
          <Tile k="MIN VARIANCE · RETURN" v={pc(o.minVariance.expectedReturn)} s={`VOL ${pc(o.minVariance.volatility, 1, false)}`} className="warn" />
          <Tile k="MIN VARIANCE · RATIO" v={sharpeOf(o.minVariance, rf).toFixed(2)} />
        </div>
        <div style={{ padding: 8 }}><Scatter x={[...o.frontier.map((p) => p.volatility * 100), ...o.vol.map((v) => v * 100)]} y={[...o.frontier.map((p) => p.expectedReturn * 100), ...o.mu.map((v) => v * 100)]} xLabel="ANNUAL VOLATILITY %" yLabel="ANNUAL RETURN % (FRONTIER AND ASSETS)" h={220} /></div>
        <table className="t"><thead><tr><th>ASSET</th><th>ANN. RET</th><th>ANN. VOL</th><th>MIN VAR</th><th>MAX SHARPE</th></tr></thead>
          <tbody>{o.kept.map((a, k) => (
            <tr key={a.symbol} className="click" tabIndex={0} onClick={() => workspace.link(a, panel)}><td><b>{a.ticker}</b></td><td>{pc(o.mu[k])}</td><td>{pc(o.vol[k], 1, false)}</td>
              <td className={o.minVariance.weights[k] < 0.0005 ? "faint" : "warn"}>{o.minVariance.weights[k] < 0.0005 ? "—" : pc(o.minVariance.weights[k], 1, false)}</td>
              <td className={o.maxSharpe.weights[k] < 0.0005 ? "faint" : "accent"}>{o.maxSharpe.weights[k] < 0.0005 ? "—" : pc(o.maxSharpe.weights[k], 1, false)}</td></tr>))}</tbody></table>
        <p className="faint" style={{ fontSize: 10, padding: 8 }}>Inputs are historical means and covariances, which are noisy estimates of the future. Treat the weights as a study of risk and diversification, not advice.</p>
      </>}
    </div>
  );
}

const CROSS = ["SPX", "CCMP", "RTY", "UKX", "DAX", "VIX", "EURUSD", "USDJPY", "GC1", "CL1", "BTC", "ETH"];

/** CORR: correlation matrix of daily returns. */
export function Correlation({ panel }: { panel: number }) {
  useStore(userData);
  const [which, setWhich] = useSetting<"CROSS-ASSET" | "WATCHLIST">("corr.basket", "CROSS-ASSET");
  const [win, setWin] = useSetting("corr.win", "1y");
  const list = which === "CROSS-ASSET" ? CROSS.map((t) => resolve(t)!) : basket(14);
  const s = useAsync(async () => {
    const h = Object.fromEntries((await Promise.all(list.map(async (i) => [i.symbol, await history(i, win).catch(() => [])] as const))).filter(([, c]) => c.length > 20));
    const kept = list.filter((i) => h[i.symbol]), r = alignedReturns(h);
    return { kept, m: correlationMatrix(r, kept.map((i) => i.symbol)), days: r[kept[0]?.symbol]?.length ?? 0 };
  }, [which, win, list.map((i) => i.symbol).join()]);
  // Light text on cells up to 45% tint, dark text on 62%+ (|r| ≥ 0.5): every cell keeps ≥ 5:1 contrast (WCAG AA).
  const strong = (v: number | null) => v != null && Math.abs(v) >= 0.5;
  const color = (v: number | null, diag: boolean) => (v == null || diag ? "var(--panel)" : `color-mix(in srgb, ${v >= 0 ? "var(--accent)" : "var(--warn)"} ${Math.round(strong(v) ? 62 + 28 * Math.min((Math.abs(v) - 0.5) / 0.5, 1) : 6 + 39 * (Math.abs(v) / 0.5))}%, var(--panel))`);
  return (
    <div>
      <div className="toolbar"><Seg label="Basket" value={which} options={["CROSS-ASSET", "WATCHLIST"] as const} onChange={setWhich} /><Seg label="Window" value={win} options={["3mo", "1y", "2y"]} onChange={setWin} /></div>
      <Section title="DAILY RETURNS · PEARSON" right={s.data ? `${s.data.days} SHARED DAYS · ${s.data.kept.length} SECURITIES` : undefined} />
      {s.loading ? <Empty title="Computing…" /> : !s.data || s.data.kept.length < 2 ? <Empty title="Need at least two securities with history" /> :
        <div style={{ padding: 8, overflow: "auto" }}><table className="mono" style={{ borderCollapse: "separate", borderSpacing: 1, fontSize: 11 }}>
          <thead><tr><th />{s.data.kept.map((i) => <th key={i.symbol} className="label" style={{ fontSize: 9, padding: "2px 4px" }}>{i.ticker}</th>)}</tr></thead>
          <tbody>{s.data.kept.map((a, r) => <tr key={a.symbol}><th className="label" scope="row" tabIndex={0} data-click style={{ textAlign: "left", fontSize: 10, paddingRight: 6, cursor: "pointer" }} onClick={() => workspace.link(a, panel)}>{a.ticker}</th>
            {s.data!.m[r].map((v, c) => <td key={c} title={`${a.ticker} × ${s.data!.kept[c].ticker}: ${v?.toFixed(2) ?? "—"}`} style={{ background: color(v, r === c), width: 46, height: 30, textAlign: "center", color: r === c ? "var(--faint)" : strong(v) ? "var(--canvas)" : "var(--text)" }}>{v == null ? "—" : v.toFixed(2).replace("0.", ".")}</td>)}</tr>)}</tbody>
        </table></div>}
    </div>
  );
}

/** EQS: screener over every SEC filer's latest 10-K. */
export function Screener({ panel }: { panel: number }) {
  const s = useAsync(() => screen(), []);
  const [text, setText] = useState("");
  const [minRev, setMinRev] = useSetting("eqs.rev", "0"), [minMargin, setMinMargin] = useSetting("eqs.margin", "-1"), [minROE, setMinROE] = useSetting("eqs.roe", "-1"), [maxLev, setMaxLev] = useSetting("eqs.lev", "10");
  const [sort, setSort] = useSetting("eqs.sort", "size"), [desc, setDesc] = useState(true);
  const COLS: [string, string, (r: ScreenRow) => number | undefined][] = [["revenue", "REVENUE", (r) => r.revenue], ["netIncome", "NET INCOME", (r) => r.netIncome],
    ["margin", "NET MARGIN", (r) => screenMetrics(r).netMargin], ["roe", "ROE", (r) => screenMetrics(r).roe], ["roa", "ROA", (r) => screenMetrics(r).roa], ["lev", "LIAB/ASSETS", (r) => screenMetrics(r).leverage]];
  const rows = useMemo(() => {
    if (!s.data) return [];
    const q = text.trim().toUpperCase();
    const pass = (r: ScreenRow) => { const m = screenMetrics(r);
      return (+minRev <= 0 || (r.revenue ?? 0) >= +minRev) && (+minMargin <= -1 || (m.netMargin ?? -Infinity) >= +minMargin) && (+minROE <= -1 || (m.roe ?? -Infinity) >= +minROE)
        && (+maxLev >= 10 || (m.leverage ?? Infinity) <= +maxLev) && (!q || r.ticker.startsWith(q) || r.name.toUpperCase().includes(q)); };
    const val = sort === "size" ? (r: ScreenRow) => -r.sizeRank : COLS.find((c) => c[0] === sort)![2];
    return s.data.rows.filter(pass).sort((a, b) => { const x = val(a), y = val(b); if (x == null) return 1; if (y == null) return -1; return desc ? y - x : x - y; });
  }, [s.data, text, minRev, minMargin, minROE, maxLev, sort, desc]);
  const sel = (label: string, v: string, set: (x: string) => void, opts: [string, string][]) => <label className="mono label" style={{ fontSize: 9, fontWeight: 700, display: "flex", gap: 4, alignItems: "center" }}>{label}<select className="field" value={v} onChange={(e) => set(e.target.value)}>{opts.map(([t, x]) => <option key={x} value={x}>{t}</option>)}</select></label>;
  const fmt = (k: string, v?: number) => (v == null ? "—" : k === "revenue" || k === "netIncome" ? compact(v) : Math.abs(v) >= 10 ? ">999%" : `${(v * 100).toFixed(1)}%`);
  if (s.loading) return <Empty title="Loading annual filings for every SEC registrant…" />;
  if (s.error) return <Empty title="SEC request failed" detail={s.error} />;
  return (
    <div>
      <div className="toolbar">
        <input className="field" value={text} onChange={(e) => setText(e.target.value)} placeholder="filter by name or ticker" aria-label="Filter" />
        {sel("REVENUE", minRev, setMinRev, [["ANY", "0"], ["$100M+", "1e8"], ["$1B+", "1e9"], ["$10B+", "1e10"], ["$100B+", "1e11"]])}
        {sel("NET MARGIN", minMargin, setMinMargin, [["ANY", "-1"], ["PROFITABLE", "0"], ["10%+", "0.1"], ["20%+", "0.2"]])}
        {sel("ROE", minROE, setMinROE, [["ANY", "-1"], ["10%+", "0.1"], ["15%+", "0.15"], ["25%+", "0.25"]])}
        {sel("LIAB/ASSETS", maxLev, setMaxLev, [["ANY", "10"], ["< 80%", "0.8"], ["< 60%", "0.6"], ["< 40%", "0.4"]])}
        <span className="spacer" />
        <ExportCSV name={`screen-FY${s.data!.year}.csv`} build={() => csv(["Ticker", "Company", "CIK", "SEC size rank", "Revenue", "Net income", "Assets", "Liabilities", "Equity", "Net margin", "ROE", "ROA", "Liabilities/assets"],
          rows.map((r) => { const m = screenMetrics(r); return [r.ticker, r.name, String(r.cik), String(r.sizeRank), csvNum(r.revenue, 0), csvNum(r.netIncome, 0), csvNum(r.assets, 0), csvNum(r.liabilities, 0), csvNum(r.equity, 0), csvNum(m.netMargin), csvNum(m.roe), csvNum(m.roa), csvNum(m.leverage)]; }))} />
      </div>
      <Section title={`EQUITY SCREEN · FY${s.data!.year} 10-K DATA · SEC XBRL`} right={`${rows.length} OF ${s.data!.rows.length} COMPANIES${rows.length > 250 ? " · TOP 250 SHOWN" : ""}`} />
      <table className="t"><thead><tr>
        <th style={{ cursor: "pointer" }} tabIndex={0} data-click aria-sort={sort === "size" ? (desc ? "descending" : "ascending") : "none"} onClick={() => { if (sort === "size") setDesc(!desc); else { setSort("size"); setDesc(true); } }}>COMPANY{sort === "size" ? (desc ? " ▼" : " ▲") : ""}</th>
        {COLS.map(([k, t]) => <th key={k} style={{ cursor: "pointer" }} tabIndex={0} data-click aria-sort={sort === k ? (desc ? "descending" : "ascending") : "none"} className={sort === k ? "accent" : ""} onClick={() => { if (sort === k) setDesc(!desc); else { setSort(k); setDesc(true); } }}>{t}{sort === k ? (desc ? " ▼" : " ▲") : ""}</th>)}
      </tr></thead>
        <tbody>{rows.slice(0, 250).map((r) => (
          <tr key={r.cik} className="click" tabIndex={0} onClick={() => { const i = resolve(r.ticker, "EQUITY"); if (i) workspace.load({ fn: "FA", instrument: i }, panel); }}>
            <td><b className="accent">{r.ticker}</b> <span style={{ fontFamily: "var(--ui)", fontSize: 11 }}>{r.name.slice(0, 32)}</span></td>
            {COLS.map(([k, , f]) => { const v = f(r); return <td key={k} className={v == null ? "faint" : k === "lev" || k === "revenue" ? "" : tint(v)}>{fmt(k, v)}</td>; })}
          </tr>))}</tbody></table>
    </div>
  );
}

