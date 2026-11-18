import { useEffect, useMemo, useRef, useState, type CSSProperties } from "react";
import type { Instrument } from "../../core/instrument";
import { compact, money, price, pct } from "../../core/format";
import { contractGreeks, DERIBIT_CURRENCIES, isITM, optionInstrument, StrategyAnalysis, templateLegs, TEMPLATES, type Leg, type OptionChain, type OptionContract, type StrikeRow, type Template } from "../../core/options";
import { optionChain } from "../../data/options";
import { market } from "../../data/market";
import { useStore } from "../../data/store";
import { workspace } from "../../data/workspace";
import { Empty, Section, Tile } from "../components";
import { LineChart } from "../charts";

const supported = (i: Instrument) => i.assetClass === "CRYPTO" && DERIBIT_CURRENCIES.has(i.ticker);
const MON = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];
const expiryLabel = (e: number) => { const d = new Date(e); return `${d.getUTCDate()} ${MON[d.getUTCMonth()]} ${String(d.getUTCFullYear()).slice(2)}`; };
const daysTo = (e: number) => Math.ceil((e - Date.now()) / 86_400_000);
const strikeText = (k: number) => k.toLocaleString("en-US", { maximumFractionDigits: 2 });
/** The first expiry at least a week out: weeklies are noisy. */
const defaultExpiry = (c: OptionChain) => c.expiries.find((e) => e - Date.now() > 7 * 86_400_000) ?? c.expiries[0];

/** Loads the chain and refreshes it every 15 s while the screen is open. */
function useChain(i: Instrument) {
  const [chain, setChain] = useState<OptionChain | null>(null), [error, setError] = useState<string | null>(null), [updated, setUpdated] = useState(0);
  useEffect(() => {
    if (!supported(i)) return;
    let live = true;
    const load = () => optionChain(i.ticker).then((c) => { if (live) { setChain(c); setError(null); setUpdated(Date.now()); } }, (e) => live && setError(String(e?.message ?? e)));
    void load();
    const t = window.setInterval(load, 15_000);
    return () => { live = false; clearInterval(t); };
  }, [i.ticker]);
  return { chain, error, updated };
}

function ExpiryBar({ chain, value, onChange }: { chain: OptionChain; value: number; onChange: (e: number) => void }) {
  return (
    <div style={{ display: "flex", gap: 4, overflowX: "auto", padding: "4px 6px" }} role="radiogroup" aria-label="Expiry">
      {chain.expiries.map((e) => (
        <button key={e} role="radio" aria-checked={e === value} onClick={() => onChange(e)} className="mono"
          style={{ flex: "0 0 auto", padding: "3px 7px", borderRadius: 2, background: e === value ? "var(--accent)" : "var(--header)", color: e === value ? "var(--canvas)" : "var(--label)", fontSize: 10, fontWeight: 700, lineHeight: 1.2 }}>
          {expiryLabel(e)}<br /><span style={{ fontSize: 8, opacity: 0.7 }}>{daysTo(e)}D</span>
        </button>
      ))}
    </div>
  );
}

/** OMON: the Deribit option chain with greeks (Black-76), the smile and the ATM term structure. */
export function OptionMonitor({ i, panel }: { i: Instrument; panel: number }) {
  useStore(market);
  const { chain, error, updated } = useChain(i);
  const [picked, setPicked] = useState<number | null>(null);
  const atmRow = useRef<HTMLTableRowElement>(null), centered = useRef("");
  useEffect(() => {
    // Centre the chain on the at-the-money strike once per expiry, as the app does.
    const key = `${picked}|${!!chain}`;
    if (chain && atmRow.current && centered.current !== key) { centered.current = key; atmRow.current.scrollIntoView({ block: "center" }); }
  });
  if (!supported(i)) return <Empty title={`No free options feed for ${i.ticker}`} detail="Listed options stream for BTC and ETH from Deribit: try BTC OMON. Equity options need a paid OPRA licence." />;
  if (!chain) return <Empty title={error ? "Options data unavailable" : "Loading Deribit options…"} detail={error ? "Deribit didn't answer. Retrying shortly." : undefined} />;
  const e = picked != null && chain.expiries.includes(picked) ? picked : defaultExpiry(chain);
  const rows = chain.rows(e), fwd = chain.forward(e) ?? 0, atm = chain.atmStrike(e), spot = market.quotes.get(i.symbol)?.last;
  // Smile: out-of-the-money marks (puts below the forward, calls above).
  const smile = rows.flatMap((r) => { const c = r.strike < fwd ? r.put : r.call; return c?.iv != null ? [{ k: r.strike, v: c.iv * 100 }] : []; }).filter((p) => p.k > fwd * 0.5 && p.k < fwd * 1.8);
  const term = chain.expiries.flatMap((x) => { const v = chain.atmIV(x); return v != null ? [{ d: Math.max(daysTo(x), 0), v: v * 100 }] : []; });
  const trade = (c?: OptionContract) => { const o = c && optionInstrument(c.name); if (o) workspace.load({ fn: "TRADE", instrument: o, side: "BUY" }, panel); };
  const side = (c: OptionContract | undefined, call: boolean) => {
    const g = c ? contractGreeks(c) : undefined;
    const cells: Record<string, [string, string]> = {
      OI: [c ? compact(c.openInterest) : "—", "dim"], IV: [c?.iv != null ? (c.iv * 100).toFixed(1) : "—", "accent"], D: [g ? g.delta.toFixed(2) : "—", ""],
      VEGA: [g ? g.vega.toFixed(1) : "—", "dim"], BID: [price(c?.bid, "CRYPTO"), "up"], ASK: [price(c?.ask, "CRYPTO"), "down"],
    };
    const order = call ? ["OI", "IV", "D", "VEGA", "BID", "ASK"] : ["BID", "ASK", "VEGA", "D", "IV", "OI"];
    const style = { cursor: c ? "pointer" : undefined, background: c && isITM(c) ? "color-mix(in srgb, var(--selection) 55%, transparent)" : undefined };
    return order.map((k) => <td key={k} className={cells[k][1]} style={style} onClick={() => trade(c)} title={c ? `Trade ${c.name}` : undefined}>{cells[k][0]}</td>);
  };
  return (
    <div>
      <ExpiryBar chain={chain} value={e} onChange={setPicked} />
      <div className="tiles">
        <Tile k="FORWARD" v={price(fwd, "CRYPTO")} /><Tile k="BASIS" v={spot ? pct((fwd / spot - 1) * 100) : "—"} />
        <Tile k="ATM IV" v={chain.atmIV(e) != null ? `${(chain.atmIV(e)! * 100).toFixed(1)}%` : "—"} className="accent" />
        <Tile k="MAX PAIN" v={chain.maxPain(e) != null ? strikeText(chain.maxPain(e)!) : "—"} className="warn" />
        <Tile k="P/C OI" v={chain.putCallOI(e)?.toFixed(2) ?? "—"} s={`DERIBIT · ${new Date(updated).toLocaleTimeString("en-GB")}`} />
      </div>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(280px, 1fr))", gap: 1, background: "var(--rule)" }}>
        <div style={{ background: "var(--panel)", padding: 6 }}><div className="label mono" style={{ fontSize: 9, fontWeight: 700 }}>VOL SMILE · OTM MARK IV</div>
          {smile.length > 2 ? <LineChart x={smile.map((p) => p.k)} series={[{ name: "IV %", values: smile.map((p) => p.v), width: 2 }]} xFormat={(k) => compact(k)} markX={{ value: fwd, label: "FWD" }} h={150} /> : <Empty title="Too few strikes" />}</div>
        <div style={{ background: "var(--panel)", padding: 6 }}><div className="label mono" style={{ fontSize: 9, fontWeight: 700 }}>ATM TERM STRUCTURE</div>
          {term.length > 1 ? <LineChart x={term.map((p) => p.d)} series={[{ name: "ATM IV %", values: term.map((p) => p.v), color: "var(--warn)", width: 2 }]} xFormat={(d) => `${d}D`} h={150} /> : <Empty title="One expiry" />}</div>
      </div>
      <table className="t" style={{ fontSize: 11 }} tabIndex={0} aria-label={`Option chain, ${expiryLabel(e)}. Click a contract to trade it, or type its name and BUY on the command line.`}>
        <thead>
          <tr><th colSpan={6} className="accent" style={{ textAlign: "center" }}>CALLS</th><th /><th colSpan={6} className="accent" style={{ textAlign: "center" }}>PUTS</th></tr>
          <tr>{["OI", "IV", "Δ", "VEGA", "BID", "ASK"].map((h) => <th key={h}>{h}</th>)}<th style={{ textAlign: "center" }}>STRIKE</th>{["BID", "ASK", "VEGA", "Δ", "IV", "OI"].map((h) => <th key={"p" + h}>{h}</th>)}</tr>
        </thead>
        <tbody>{rows.map((r: StrikeRow) => (
          <tr key={r.strike} ref={r.strike === atm ? atmRow : undefined}>
            {side(r.call, true)}
            <td style={{ textAlign: "center", fontWeight: 700, background: r.strike === atm ? "var(--accent)" : "var(--header)", color: r.strike === atm ? "var(--canvas)" : undefined }}>{strikeText(r.strike)}</td>
            {side(r.put, false)}
          </tr>))}</tbody>
      </table>
      <p className="faint mono" style={{ fontSize: 9, padding: 8 }}>USD prices from Deribit's coin quotes at each expiry's forward. Greeks are Black-76 at the mark IV. Click a contract to open its paper ticket (long premium only).</p>
    </div>
  );
}

/** OSA: build a multi-leg position from the live chain; payoff at expiry and today, greeks, breakevens. */
export function OptionStrategy({ i }: { i: Instrument }) {
  const { chain, error } = useChain(i);
  const [template, setTemplate] = useState<Template>("STRADDLE");
  const [picked, setPicked] = useState<number | null>(null);
  const [legs, setLegs] = useState<Leg[] | null>(null);
  const e = chain ? (picked != null && chain.expiries.includes(picked) ? picked : defaultExpiry(chain)) : 0;
  const ready = !!chain;
  useEffect(() => { if (chain) setLegs(templateLegs(template, chain, e) ?? []); }, [ready, template, e]);
  const a = useMemo(() => new StrategyAnalysis(legs ?? []), [legs]);
  if (!supported(i)) return <Empty title={`No free options feed for ${i.ticker}`} detail="OSA uses Deribit's public chain: try BTC OSA or ETH OSA." />;
  if (!chain || !legs) return <Empty title={error ? "Options data unavailable" : "Loading Deribit options…"} detail={error ? "Deribit didn't answer." : undefined} />;
  const f = chain.forward(e) ?? 0, g = a.greeks(), debit = a.netPremium;
  const strikes = chain.rows(e).filter((r) => r.call?.mark != null && r.put?.mark != null);
  const xs = Array.from({ length: 161 }, (_, k) => f * (0.65 + (0.7 * k) / 160));
  const update = (n: number, l: Leg) => setLegs(legs.map((x, k) => (k === n ? l : x)));
  const shift = (n: number, d: number) => {
    const c = legs[n].contract, at = strikes.findIndex((r) => r.strike === c.strike), r = strikes[at + d];
    const next = r && (c.isCall ? r.call : r.put);
    if (at >= 0 && next && !legs.some((l) => l.contract.name === next.name)) update(n, { ...legs[n], contract: next });
  };
  const step: CSSProperties = { color: "var(--accent)", background: "none", fontWeight: 800, width: 18 };
  return (
    <div>
      <div className="toolbar">
        <div className="seg" role="radiogroup" aria-label="Strategy">{TEMPLATES.map((t) => <button key={t} role="radio" aria-checked={t === template} className={t === template ? "on" : ""} onClick={() => setTemplate(t)}>{t}</button>)}</div>
        <select className="field" value={e} onChange={(ev) => setPicked(Number(ev.target.value))} aria-label="Expiry">{chain.expiries.map((x) => <option key={x} value={x}>EXPIRY {expiryLabel(x)} · {daysTo(x)}D</option>)}</select>
      </div>
      {legs.length === 0 ? <Empty title={`This expiry is too sparse for a ${template.toLowerCase()}`} detail="Pick a later expiry." /> : <>
        <div className="tiles">
          <Tile k={debit >= 0 ? "NET DEBIT" : "NET CREDIT"} v={money(Math.abs(debit))} className={debit < 0 ? "up" : ""} />
          <Tile k="MAX PROFIT" v={a.maxProfit != null ? money(a.maxProfit) : "UNLIMITED"} className="up" />
          <Tile k="MAX LOSS" v={a.maxLoss != null ? money(Math.abs(a.maxLoss)) : "UNLIMITED"} className="down" />
          <Tile k="BREAKEVEN" v={a.breakevens.length ? a.breakevens.map((b) => price(b, "CRYPTO")).join(" / ") : "—"} s={a.breakevens.map((b) => pct((b / f - 1) * 100)).join(" / ")} className="warn" />
          <Tile k="DELTA" v={(g.delta >= 0 ? "+" : "") + g.delta.toFixed(3)} s="COINS" /><Tile k="GAMMA" v={g.gamma.toExponential(2)} s="PER $1" />
          <Tile k="VEGA" v={(g.vega >= 0 ? "+" : "") + g.vega.toFixed(2)} s="$ PER VOL PT" /><Tile k="THETA" v={(g.theta >= 0 ? "+" : "") + g.theta.toFixed(2)} s="$ PER DAY" className={g.theta >= 0 ? "up" : "down"} />
        </div>
        <Section title={`P&L VS ${i.ticker} AT EXPIRY AND TODAY`} right={`FORWARD ${price(f, "CRYPTO")}`} />
        <div style={{ padding: 8 }}>
          <LineChart x={xs} series={[{ name: "Expiry", values: xs.map((s) => a.payoffAtExpiry(s)), color: "var(--accent)", width: 2 }, { name: "Today", values: xs.map((s) => a.valueToday(s)), color: "var(--warn)", width: 1.5 }]}
            zero={0} markX={{ value: f, label: "FWD" }} xFormat={(v) => compact(v)} yLabel="Profit and loss ($)" h={240} />
        </div>
        <Section title="LEGS" right={String(legs.length)} />
        <table className="t"><thead><tr><th style={{ textAlign: "left" }}>SIDE</th><th style={{ textAlign: "center" }}>QTY</th><th style={{ textAlign: "left" }}>TYPE</th><th style={{ textAlign: "center" }}>STRIKE</th><th>MARK</th><th>IV</th><th>DELTA</th></tr></thead>
          <tbody>{legs.map((l, n) => { const c = l.contract, q = Math.abs(l.quantity), sgn = Math.sign(l.quantity), lg = contractGreeks(c); return (
            <tr key={c.name}>
              <td style={{ textAlign: "left" }}><button className={`textbtn ${l.quantity > 0 ? "up" : "down"}`} style={{ padding: 0, color: l.quantity > 0 ? "var(--up)" : "var(--down)" }} onClick={() => update(n, { ...l, quantity: -l.quantity })} title="Flip long/short">{l.quantity > 0 ? "LONG" : "SHORT"}</button></td>
              <td style={{ textAlign: "center" }}><button style={step} onClick={() => q > 1 && update(n, { ...l, quantity: (q - 1) * sgn })} aria-label="Fewer">−</button>{q}<button style={step} onClick={() => q < 50 && update(n, { ...l, quantity: (q + 1) * sgn })} aria-label="More">+</button></td>
              <td style={{ textAlign: "left" }} className="label">{c.isCall ? "CALL" : "PUT"}</td>
              <td style={{ textAlign: "center" }}><button style={step} onClick={() => shift(n, -1)} aria-label="Lower strike">‹</button>{strikeText(c.strike)}<button style={step} onClick={() => shift(n, 1)} aria-label="Higher strike">›</button></td>
              <td>{price(c.mark, "CRYPTO")}</td><td className="dim">{c.iv != null ? `${(c.iv * 100).toFixed(1)}%` : "—"}</td><td>{lg ? (lg.delta * l.quantity >= 0 ? "+" : "") + (lg.delta * l.quantity).toFixed(2) : "—"}</td>
            </tr>); })}</tbody></table>
        <p className="faint mono" style={{ fontSize: 9, padding: 8 }}>Model values use Black-76 at each leg's Deribit mark IV, with premiums at the mark. Paper trading supports long legs only; shorts here are for analysis.</p>
      </>}
    </div>
  );
}
