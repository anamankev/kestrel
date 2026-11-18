import { useEffect, useState } from "react";
import type { Instrument } from "../../core/instrument";
import { change, changePercent } from "../../core/market";
import { compact, price } from "../../core/format";
import { instrument, isStreaming, resolve } from "../../core/universe";
import { market } from "../../data/market";
import { useStore } from "../../data/store";
import { userData, workspace, MAX_SYMBOLS } from "../../data/workspace";
import { Change, Empty, Section, Sparkline } from "../components";

export function Monitor({ panel }: { panel: number }) {
  useStore(market); useStore(userData);
  const [add, setAdd] = useState("");
  const [note, setNote] = useState<string | null>(null);
  const l = userData.active;
  const list = l.symbols.map((s) => instrument(s) ?? resolve(s)).filter((i): i is Instrument => !!i);
  useEffect(() => { market.focus = new Set([...market.focus, ...l.symbols]); void market.refresh(list.filter((i) => !isStreaming(i) && !market.quotes.has(i.symbol))); }, [l.id, l.symbols.length]);
  useEffect(() => { workspace.setHotspots(panel, list.map((i) => ({ link: i }))); });
  const live = list.filter(isStreaming), delayed = list.filter((i) => !isStreaming(i));
  const submit = () => { const e = userData.add(add); setNote(e); if (!e) setAdd(""); };
  const rows = (items: Instrument[], offset: number) => items.map((i, n) => {
    const q = market.quotes.get(i.symbol);
    return (
      <tr key={i.symbol} className="click" onClick={() => workspace.link(i, panel)} title="Load into linked panels">
        <td><span className="faint" style={{ marginRight: 6 }}>{offset + n + 1}</span><b>{i.ticker}</b> <span className="dim" style={{ fontFamily: "var(--ui)", fontSize: 11 }}>{market.displayName(i).slice(0, 18)}</span></td>
        <td>{price(q?.last, i.assetClass)}</td>
        <td><Change value={change(q)} like={q?.last} cls={i.assetClass} /></td>
        <td><Change value={changePercent(q)} percent /></td>
        <td className="dim">{compact(q?.volume)}</td>
        <td><Sparkline values={market.sparks.get(i.symbol)} w={70} h={16} /></td>
        <td><button className="dim" aria-label={`Remove ${i.ticker}`} onClick={(e) => { e.stopPropagation(); userData.remove(i.symbol); }}>×</button></td>
      </tr>
    );
  });
  const head = <tr><th>SECURITY</th><th>LAST</th><th>NET</th><th>%CHG</th><th>VOLUME</th><th>INTRADAY</th><th /></tr>;
  return (
    <div>
      <div className="toolbar">
        <select className="field" value={l.id} onChange={(e) => e.target.value === "__new" ? userData.create(prompt("New watchlist name") ?? "") : userData.select(e.target.value)} aria-label="Watchlist">
          {userData.lists.map((w) => <option key={w.id} value={w.id}>{w.name} ({w.symbols.length})</option>)}
          <option value="__new">New list…</option>
        </select>
        <button className="key fn" onClick={() => { const n = prompt("Rename watchlist", l.name); if (n) userData.rename(n); }}>RENAME</button>
        {userData.lists.length > 1 && <button className="key fn" onClick={() => confirm(`Delete ${l.name}?`) && userData.deleteActive()}>DELETE</button>}
        <form onSubmit={(e) => { e.preventDefault(); submit(); }} style={{ display: "flex" }}>
          <input className="field" value={add} onChange={(e) => setAdd(e.target.value)} placeholder="ADD ticker ↩" aria-label="Add ticker" style={{ width: 130, textTransform: "uppercase" }} />
        </form>
        <span className="mono dim" style={{ fontSize: 10 }}>{l.symbols.length}/{MAX_SYMBOLS}</span>
        {note && <span className="mono warn" style={{ fontSize: 11 }}>{note}</span>}
      </div>
      {!list.length ? <Empty title={`${l.name} is empty`} detail="Type a ticker in the ADD box (AAPL, BTC, SPX, EURUSD)." /> : <>
        {live.length > 0 && <><Section title="STREAMING" right="COINBASE" /><table className="t"><thead>{head}</thead><tbody>{rows(live, 0)}</tbody></table></>}
        {delayed.length > 0 && <><Section title="DELAYED" right="~15 MIN · YAHOO" /><table className="t"><thead>{head}</thead><tbody>{rows(delayed, live.length)}</tbody></table></>}
      </>}
    </div>
  );
}
