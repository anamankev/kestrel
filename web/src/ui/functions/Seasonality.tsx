import { useState } from "react";
import type { Instrument } from "../../core/instrument";
import { csv, csvNum, monthlyReturns, seasonality } from "../../core/quant";
import { chart } from "../../data/relay";
import { Empty, Section, Seg, Tile } from "../components";
import { Bars, ExportCSV } from "../charts";
import { useAsync } from "../useAsync";

const MONTHS = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];
const SPANS = { "5Y": "5y", "10Y": "10y", ALL: "max" } as const;
const pc = (v?: number, d = 1) => (v == null || !Number.isFinite(v) ? "—" : `${v > 0 ? "+" : ""}${(v * 100).toFixed(d)}%`);
const tint = (v?: number) => (v == null || v === 0 ? "" : v > 0 ? "up" : "down");

/** SEAS: average return in each calendar month, from monthly bars (Yahoo's long history, crypto included). */
export function Seasonality({ i }: { i: Instrument }) {
  const [span, setSpan] = useState<keyof typeof SPANS>(() => (localStorage.getItem("seas.span") as keyof typeof SPANS) ?? "10Y");
  const s = useAsync(async () => {
    if (i.assetClass === "OPTION") return null;
    const { candles } = await chart(i.symbol, SPANS[span], "1mo", { adjusted: true, intraday: false });
    const rets = monthlyReturns(candles);
    return { rets, stats: seasonality(rets), from: rets[0]?.year, to: rets[rets.length - 1]?.year };
  }, [i.symbol, span]);
  const now = new Date().getUTCMonth();
  const d = s.data;
  if (i.assetClass === "OPTION") return <Empty title="Seasonality needs a price history" detail="Try CL1 SEAS, SPY SEAS or BTC SEAS." />;
  return (
    <div>
      <div className="toolbar">
        <Seg label="History" value={span} options={["5Y", "10Y", "ALL"] as const} onChange={(v) => { localStorage.setItem("seas.span", v); setSpan(v); }} />
        <span className="spacer" />
        {d && <ExportCSV name={`${i.ticker}-seasonality.csv`} build={() => csv(["Month", "Average return", "Median return", "Share positive", "Best", "Worst", "Years"],
          d.stats.map((m) => [MONTHS[m.month], csvNum(m.mean), csvNum(m.median), csvNum(m.positive), csvNum(m.best), csvNum(m.worst), String(m.n)]))} />}
      </div>
      {s.loading ? <Empty title="Loading monthly history…" /> : s.error ? <Empty title="History unavailable" detail={s.error} /> : !d || d.rets.length < 12 ? <Empty title="Not enough monthly history" detail="Seasonality needs at least a year of monthly closes." /> : <>
        {(() => {
          const ranked = d.stats.filter((m) => m.mean != null).sort((a, b) => b.mean! - a.mean!);
          const cur = d.stats[now];
          return (
            <div className="tiles">
              <Tile k="STRONGEST MONTH" v={MONTHS[ranked[0].month]} s={`AVG ${pc(ranked[0].mean)} · UP ${((ranked[0].positive ?? 0) * 100).toFixed(0)}% OF YEARS`} className="up" />
              <Tile k="WEAKEST MONTH" v={MONTHS[ranked[ranked.length - 1].month]} s={`AVG ${pc(ranked[ranked.length - 1].mean)} · UP ${((ranked[ranked.length - 1].positive ?? 0) * 100).toFixed(0)}% OF YEARS`} className="down" />
              <Tile k={`${MONTHS[now]} (THIS MONTH)`} v={pc(cur.mean)} s={`UP IN ${((cur.positive ?? 0) * 100).toFixed(0)}% OF ${cur.n} YEARS`} className={tint(cur.mean)} />
            </div>
          );
        })()}
        <Section title={`${i.ticker} · AVERAGE RETURN BY CALENDAR MONTH`} right={`${d.from}–${d.to} · ${d.rets.length} MONTHS`} />
        <div style={{ padding: 8 }}><Bars items={d.stats.map((m) => ({ label: MONTHS[m.month], value: (m.mean ?? 0) * 100, dim: m.month !== now }))} format={(v) => `${v.toFixed(1)}%`} /></div>
        <table className="t">
          <thead><tr><th style={{ textAlign: "left" }}>MONTH</th><th>AVERAGE</th><th>MEDIAN</th><th>% UP</th><th>BEST</th><th>WORST</th><th>YEARS</th></tr></thead>
          <tbody>{d.stats.map((m) => (
            <tr key={m.month} style={m.month === now ? { outline: "1px solid var(--accent-dim)" } : undefined}>
              <td style={{ textAlign: "left" }}><b>{MONTHS[m.month]}</b></td><td className={tint(m.mean)}>{pc(m.mean, 2)}</td><td className={tint(m.median)}>{pc(m.median, 2)}</td>
              <td>{m.positive == null ? "—" : `${(m.positive * 100).toFixed(0)}%`}</td><td className="up">{pc(m.best)}</td><td className="down">{pc(m.worst)}</td><td className="dim">{m.n}</td>
            </tr>))}</tbody>
        </table>
        <p className="faint" style={{ fontSize: 10, padding: 8 }}>Monthly total returns (dividends reinvested) from month-end closes; the current month is left out until it ends. Past seasonality is a tendency, not a forecast.</p>
      </>}
    </div>
  );
}
