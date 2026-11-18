import type { Instrument } from "../../core/instrument";
import { price, clock } from "../../core/format";
import { market } from "../../data/market";
import { useStore } from "../../data/store";
import { Empty, Section } from "../components";

export function Depth({ i }: { i: Instrument }) {
  useStore(market);
  const b = market.books.get(i.symbol);
  if (!b) return <Empty title="Connecting to the order book…" />;
  const { bids, asks } = b.ladder(14);
  const max = Math.max(bids[bids.length - 1]?.cumulative ?? 0, asks[asks.length - 1]?.cumulative ?? 0, 1e-12);
  const row = (side: "bid" | "ask") => (l: { price: number; size: number; cumulative: number }) => (
    <div key={`${side}${l.price}`} className={`lrow ${side}`} style={{ ["--w" as string]: `${(l.cumulative / max) * 100}%` }}>
      <span className={side === "bid" ? "up" : "down"}>{price(l.price, i.assetClass)}</span><span>{l.size.toFixed(5)}</span><span className="dim">{l.cumulative.toFixed(4)}</span>
    </div>
  );
  return (
    <div className="mono">
      <Section title={`${i.ticker} · LIVE ORDER BOOK`} right="COINBASE" />
      <div className="lrow head"><span>PRICE</span><span>SIZE</span><span>TOTAL</span></div>
      {[...asks].reverse().map(row("ask"))}
      <div className="lrow mid"><span>{b.spread !== undefined ? `SPREAD ${price(b.spread, i.assetClass)}` : ""}</span><span /><span>{b.bestBid !== undefined && b.bestAsk !== undefined ? `MID ${price((b.bestBid + b.bestAsk) / 2, i.assetClass)}` : ""}</span></div>
      {bids.map(row("bid"))}
    </div>
  );
}

export function TimeAndSales({ i }: { i: Instrument }) {
  useStore(market);
  const t = market.tapes.get(i.symbol) ?? [];
  if (!t.length) return <Empty title="Waiting for trades…" />;
  return (
    <div>
      <Section title={`${i.ticker} · TIME & SALES`} right={`${t.length} PRINTS`} />
      <table className="t"><thead><tr><th>TIME</th><th>PRICE</th><th>SIZE</th><th>SIDE</th></tr></thead>
        <tbody>{t.slice(0, 120).map((p) => <tr key={p.id}><td className="dim">{clock(p.time)}</td><td className={p.side === "BUY" ? "up" : "down"}>{price(p.price, i.assetClass)}</td><td>{p.size.toFixed(5)}</td><td className={p.side === "BUY" ? "up" : "down"}>{p.side}</td></tr>)}</tbody>
      </table>
    </div>
  );
}
