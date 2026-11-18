import { useEffect, useRef, useState } from "react";
import type { SearchHit } from "../../core/yahoo";
import { searchSecurities } from "../../data/relay";
import { useStore } from "../../data/store";
import { userData, workspace } from "../../data/workspace";
import { Empty, Section, Seg } from "../components";

const FILTERS = ["ALL", "STOCKS & FUNDS", "INDICES", "FX", "FUTURES", "CRYPTO"] as const;
const CLS: Record<string, string> = { "STOCKS & FUNDS": "EQUITY", INDICES: "INDEX", FX: "CURNCY", FUTURES: "CMDTY", CRYPTO: "CRYPTO" };

export function SecurityFinder({ panel, initial }: { panel: number; initial?: string }) {
  useStore(userData);
  const [q, setQ] = useState(initial?.toLowerCase() ?? "");
  const [hits, setHits] = useState<SearchHit[] | null>(null);
  const [filter, setFilter] = useState<(typeof FILTERS)[number]>("ALL");
  const [note, setNote] = useState<string | null>(null);
  const box = useRef<HTMLInputElement>(null);
  useEffect(() => { if (initial) setQ(initial.toLowerCase()); else box.current?.focus(); }, [initial]);
  useEffect(() => {
    const t = q.trim();
    if (t.length < 2) { setHits(null); return; }
    const ctl = new AbortController();
    const timer = setTimeout(() => searchSecurities(t, 25, ctl.signal).then(setHits).catch(() => !ctl.signal.aborted && setHits([])), 300);
    return () => { clearTimeout(timer); ctl.abort(); };
  }, [q]);
  const shown = (hits ?? []).filter((h) => filter === "ALL" || h.instrument.assetClass === CLS[filter]);
  return (
    <div>
      <div style={{ padding: 8 }}><input ref={box} className="field" style={{ width: "100%", fontSize: 13 }} value={q} onChange={(e) => setQ(e.target.value)} placeholder="Company or ticker: toyota, nestle, 7203.T, gold, GBPJPY" aria-label="Search securities" /></div>
      <div style={{ padding: "0 8px 8px" }}><Seg label="Type" value={filter} options={FILTERS} onChange={setFilter} /></div>
      <Section title="SECURITY FINDER · ALL EXCHANGES" right={note ?? (hits ? `${shown.length} OF ${hits.length} MATCHES` : undefined)} />
      {!shown.length ? <Empty title={q.trim().length < 2 ? "Search every market" : hits ? "No matches" : "Searching…"} detail={q.trim().length < 2 ? "Stocks and ETFs worldwide, indices, currency pairs, futures and crypto. Results come from Yahoo Finance; prices are delayed except Coinbase crypto." : undefined} /> :
        <table className="t">
          <thead><tr><th>TICKER</th><th style={{ textAlign: "left" }}>NAME</th><th style={{ textAlign: "left" }}>TYPE</th><th style={{ textAlign: "left" }}>EXCHANGE</th><th /></tr></thead>
          <tbody>{shown.map((h) => (
            <tr key={h.instrument.symbol} className="click" onClick={() => workspace.load({ fn: "DES", instrument: h.instrument }, panel)}>
              <td className="accent"><b>{h.token}</b></td>
              <td style={{ textAlign: "left", fontFamily: "var(--ui)" }}>{h.instrument.name}</td>
              <td style={{ textAlign: "left" }} className="dim">{h.kind.toUpperCase()}</td>
              <td style={{ textAlign: "left" }} className="dim">{h.exchange}</td>
              <td><button className="accent" aria-label={`Add ${h.token} to watchlist`} onClick={(e) => { e.stopPropagation(); setNote(userData.add(h.token) ?? `ADDED ${h.token} TO ${userData.active.name}`); }}>{userData.active.symbols.includes(h.instrument.symbol) ? "✓" : "+"}</button></td>
            </tr>
          ))}</tbody>
        </table>}
    </div>
  );
}
