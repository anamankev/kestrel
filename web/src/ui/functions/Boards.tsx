import { useEffect } from "react";
import type { Instrument } from "../../core/instrument";
import { change, changePercent } from "../../core/market";
import { price } from "../../core/format";
import { crypto, equities } from "../../core/universe";
import { market } from "../../data/market";
import { useStore } from "../../data/store";
import { workspace } from "../../data/workspace";
import { Change, Empty, Section, Sparkline } from "../components";

export function QuoteBoard({ panel, groups, yields }: { panel: number; groups: [string, Instrument[]][]; yields?: boolean }) {
  useStore(market);
  const flat = groups.flatMap(([, l]) => l);
  useEffect(() => { workspace.setHotspots(panel, flat.map((i) => ({ link: i }))); });
  let n = 0;
  return (
    <div>
      {groups.map(([title, list]) => {
        const ups = list.filter((i) => (changePercent(market.quotes.get(i.symbol)) ?? 0) > 0).length;
        return (
          <div key={title}>
            <Section title={title} right={<><span className="up">▲{ups}</span> <span className="down">▼{list.length - ups}</span></>} />
            <table className="t">
              <thead><tr><th>SECURITY</th><th>LAST</th><th>NET</th><th>%CHG</th><th>HIGH</th><th>LOW</th><th>INTRADAY</th></tr></thead>
              <tbody>{list.map((i) => {
                const q = market.quotes.get(i.symbol);
                n++;
                return (
                  <tr key={i.symbol} className="click" onClick={() => workspace.link(i, panel)}>
                    <td><span className="faint" style={{ marginRight: 6 }}>{n}</span><b>{i.ticker}</b> <span className="dim" style={{ fontFamily: "var(--ui)", fontSize: 11 }}>{i.name}</span></td>
                    <td>{price(q?.last, i.assetClass)}{yields ? "%" : ""}</td>
                    <td><Change value={change(q)} like={q?.last} cls={i.assetClass} /></td>
                    <td><Change value={changePercent(q)} percent /></td>
                    <td className="dim">{price(q?.high, i.assetClass)}</td>
                    <td className="dim">{price(q?.low, i.assetClass)}</td>
                    <td><Sparkline values={market.sparks.get(i.symbol)} w={70} h={16} /></td>
                  </tr>
                );
              })}</tbody>
            </table>
          </div>
        );
      })}
    </div>
  );
}

export function Movers({ panel }: { panel: number }) {
  useStore(market);
  const pool = [...equities, ...crypto].map((i) => ({ i, p: changePercent(market.quotes.get(i.symbol)) })).filter((x) => x.p !== undefined) as { i: Instrument; p: number }[];
  if (!pool.length) return <Empty title="Loading movers…" />;
  const gainers = [...pool].sort((a, b) => b.p - a.p).slice(0, 8), losers = [...pool].sort((a, b) => a.p - b.p).slice(0, 8);
  const block = (title: string, l: typeof pool) => (
    <><Section title={title} /><table className="t"><tbody>{l.map(({ i, p }) => (
      <tr key={i.symbol} className="click" onClick={() => workspace.link(i, panel)}><td><b>{i.ticker}</b> <span className="dim" style={{ fontFamily: "var(--ui)", fontSize: 11 }}>{i.name}</span></td><td>{price(market.quotes.get(i.symbol)?.last, i.assetClass)}</td><td><Change value={p} percent /></td></tr>
    ))}</tbody></table></>
  );
  return <div>{block("TOP GAINERS", gainers)}{block("TOP LOSERS", losers)}</div>;
}

export function Heatmap({ panel }: { panel: number }) {
  useStore(market);
  const tile = (i: Instrument) => {
    const p = changePercent(market.quotes.get(i.symbol));
    const a = p === undefined ? 0 : Math.min(Math.abs(p) / 4, 1);
    const bg = p === undefined ? "var(--header)" : `color-mix(in srgb, ${p >= 0 ? "var(--up)" : "var(--down)"} ${Math.round(12 + a * 60)}%, var(--panel))`;
    return (
      <button key={i.symbol} onClick={() => workspace.link(i, panel)} style={{ background: bg, padding: 8, textAlign: "left", minHeight: 58 }} aria-label={`${i.ticker} ${p?.toFixed(2) ?? "no data"}%`}>
        <div className="mono" style={{ fontWeight: 700, fontSize: 12 }}>{i.ticker}</div>
        <div className="mono" style={{ fontSize: 11 }}>{p === undefined ? "—" : `${p > 0 ? "+" : ""}${p.toFixed(2)}%`}</div>
      </button>
    );
  };
  return (
    <div>
      <Section title="EQUITIES" /><div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(84px, 1fr))", gap: 1, background: "var(--rule)" }}>{equities.map(tile)}</div>
      <Section title="CRYPTO" /><div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(84px, 1fr))", gap: 1, background: "var(--rule)" }}>{crypto.map(tile)}</div>
    </div>
  );
}
