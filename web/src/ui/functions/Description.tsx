import { useEffect } from "react";
import type { Instrument } from "../../core/instrument";
import { change, changePercent } from "../../core/market";
import { compact, price, clock } from "../../core/format";
import { isStreaming } from "../../core/universe";
import { market } from "../../data/market";
import { useStore } from "../../data/store";
import { workspace } from "../../data/workspace";
import { Change, Sparkline } from "../components";

const LINKS: [string, string][] = [["GP", "Price Chart"], ["HP", "History"], ["FA", "Financials"], ["EVTS", "Events"], ["DEPTH", "Market Depth"], ["TAS", "Time & Sales"], ["CN", "News"], ["DVD", "Dividends"], ["TRADE", "Trade"]];

export function Description({ panel, i }: { panel: number; i: Instrument }) {
  useStore(market);
  const q = market.quotes.get(i.symbol);
  const d = market.details.get(i.symbol);
  const live = isStreaming(i);
  const links = LINKS.filter(([c]) => live ? !["FA", "EVTS", "DVD"].includes(c) : !["DEPTH", "TAS"].includes(c));
  useEffect(() => { workspace.setHotspots(panel, links.map(([c]) => ({ cmd: { fn: c, instrument: i } }))); });
  const range = q?.high52 != null && q?.low52 != null && q.high52 > q.low52 ? (q.last - q.low52) / (q.high52 - q.low52) : undefined;
  return (
    <div style={{ padding: 16, display: "grid", gridTemplateColumns: "minmax(0, 1fr)", gap: 14, alignContent: "start" }}>
      <div>
        <div style={{ fontSize: 20, fontWeight: 600 }}>{market.displayName(i)}</div>
        <div className="mono dim" style={{ fontSize: 11 }}>{[i.ticker, i.assetClass, d?.exchange ?? (live ? "Coinbase" : undefined), d?.currency ?? "USD"].filter(Boolean).join(" · ")}</div>
      </div>
      <div style={{ display: "flex", alignItems: "baseline", gap: 12, flexWrap: "wrap" }}>
        <span className="price-big">{price(q?.last, i.assetClass)}</span>
        <Change value={change(q)} like={q?.last} cls={i.assetClass} /> <Change value={changePercent(q)} percent />
        <span className="spacer" />
        <span className={`badge mono ${live ? "" : "warn"}`} style={{ color: live ? "var(--go)" : undefined }}>{live ? "STREAMING" : "DELAYED"}</span>
      </div>
      <Sparkline values={market.sparks.get(i.symbol)} w={600} h={90} />
      <div className="tiles">
        {([["PREV CLOSE", price(q?.previousClose, i.assetClass)], ["VOLUME", compact(q?.volume)], [live ? "24H HIGH" : "DAY HIGH", price(q?.high, i.assetClass)],
          [live ? "24H LOW" : "DAY LOW", price(q?.low, i.assetClass)], ["BID", price(q?.bid, i.assetClass)], ["ASK", price(q?.ask, i.assetClass)],
          ["UPDATED", q ? clock(q.time) : "—"]] as [string, string][]).map(([k, v]) => <div className="tile" key={k}><div className="k">{k}</div><div className="v mono" style={{ fontSize: 14 }}>{v}</div></div>)}
      </div>
      {range !== undefined && (
        <div>
          <div className="mono label" style={{ fontSize: 9, fontWeight: 700, display: "flex", justifyContent: "space-between" }}><span>52-WEEK RANGE</span><span className="dim">{price(q!.low52, i.assetClass)} — {price(q!.high52, i.assetClass)}</span></div>
          <div style={{ height: 4, background: "var(--rule)", marginTop: 6, position: "relative" }}><div style={{ width: `${Math.min(Math.max(range, 0), 1) * 100}%`, height: 4, background: "var(--accent-dim)" }} /></div>
        </div>
      )}
      <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
        {links.map(([c, t], n) => <button key={c} className="hotspot" onClick={() => workspace.load({ fn: c, instrument: i }, panel)}><span className="n">{n + 1}</span>{c} <span className="dim">{t}</span></button>)}
      </div>
    </div>
  );
}
