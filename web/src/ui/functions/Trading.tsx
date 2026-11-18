import { useEffect, useState } from "react";
import type { Instrument } from "../../core/instrument";
import type { TradeSide } from "../../core/command";
import { compact, money, price, pct } from "../../core/format";
import { alignedReturns, betaOf, expectedShortfall, historicalVaR, pnlSeries } from "../../core/quant";
import { contractGreeks, parseOption } from "../../core/options";
import { contracts } from "../../data/options";
import { history } from "../../data/research";
import { useAsync } from "../useAsync";
import { changePercent } from "../../core/market";
import { isPendingStop, OrderReject, PaperAccount, type Order, type OrderType } from "../../core/paper";
import { AlertError, conditionLabel, type AlertCondition } from "../../core/alerts";
import { instrument, resolve, isStreaming } from "../../core/universe";
import { clock } from "../../core/format";
import { broker } from "../../data/broker";
import { alerts } from "../../data/alerts";
import { market } from "../../data/market";
import { useStore } from "../../data/store";
import { workspace } from "../../data/workspace";
import { Empty, Section, Seg, Tile } from "../components";
import { LineChart } from "../charts";

const num = (s: string) => { const v = Number(s.replace(/,/g, "").trim()); return s.trim() && Number.isFinite(v) ? v : undefined; };
const qty = (v: number) => new Intl.NumberFormat("en-US", { maximumFractionDigits: 8 }).format(v);
const signedMoney = (v: number) => (v > 0 ? "+" : "") + money(v);
const tint = (v: number) => (Math.abs(v) < 0.005 ? "" : v > 0 ? "up" : "down");
const tickerOf = (s: string) => instrument(s)?.ticker ?? resolve(s)?.ticker ?? s;
const plain = (v: number | undefined, i: Instrument) => (v == null ? "" : price(v, i.assetClass).replace(/,/g, ""));
const typeLabel = (t: OrderType) => t.kind === "market" ? "MKT" : t.kind === "limit" ? `LMT ${price(t.limit)}` : t.kind === "stop" ? `STP ${price(t.stop)}` : `STP ${price(t.stop)} LMT ${price(t.limit)}`;

type Kind = "MARKET" | "LIMIT" | "STOP" | "STOP LMT";

/** TRADE: paper order ticket with a two-step send. */
export function Ticket({ i, side: initial }: { i: Instrument; side?: TradeSide }) {
  useStore(market); useStore(broker);
  const q = market.quotes.get(i.symbol);
  const [side, setSide] = useState<TradeSide>(initial ?? "BUY");
  const [kind, setKind] = useState<Kind>("MARKET");
  const [qtyText, setQty] = useState(""), [limitText, setLimit] = useState(""), [stopText, setStop] = useState("");
  const [armed, setArmed] = useState(false);
  const [msg, setMsg] = useState<[string, boolean] | null>(null);
  const isLimit = kind === "LIMIT" || kind === "STOP LMT", isStop = kind === "STOP" || kind === "STOP LMT";
  const prefillLimit = (s = side) => q && setLimit(plain(s === "BUY" ? q.bid ?? q.last : q.ask ?? q.last, i));
  const prefillStop = (s = side) => q && setStop(plain(q.last * (s === "BUY" ? 1.02 : 0.98), i));
  useEffect(() => { if (!limitText && q) prefillLimit(); }, [q != null]);
  useEffect(() => setArmed(false), [qtyText, limitText, stopText, side, kind]);
  const amount = num(qtyText), lim = num(limitText), stp = num(stopText);
  const est = isLimit ? lim : isStop ? stp : side === "BUY" ? q?.ask ?? q?.last : q?.bid ?? q?.last;
  const pos = broker.account.positions[i.symbol];
  const held = pos?.quantity ?? 0;
  const presets = i.assetClass === "OPTION" ? [0.1, 1, 5, 10] : isStreaming(i) ? (i.ticker === "BTC" ? [0.01, 0.1, 0.5, 1] : [0.1, 1, 10, 100]) : [1, 10, 50, 100];
  const short = ["MKT", "LMT", "STP", "STP LMT"][["MARKET", "LIMIT", "STOP", "STOP LMT"].indexOf(kind)];
  const terms = kind === "MARKET" ? "AT MARKET" : kind === "LIMIT" ? `@ ${limitText}` : kind === "STOP" ? `STOP ${stopText}` : `STOP ${stopText} LMT ${limitText}`;
  const send = () => {
    if (amount == null) return;
    let type: OrderType;
    if (kind === "MARKET") type = { kind: "market" };
    else if (kind === "LIMIT") { if (lim == null) return setMsg(["Enter a limit price", false]); type = { kind: "limit", limit: lim }; }
    else if (kind === "STOP") { if (stp == null) return setMsg(["Enter a stop price", false]); type = { kind: "stop", stop: stp }; }
    else { if (stp == null || lim == null) return setMsg(["Enter stop and limit prices", false]); type = { kind: "stopLimit", stop: stp, limit: lim }; }
    try {
      const o = broker.submit(i, side, amount, type);
      setMsg(o.status === "FILLED" ? [`Filled #${o.id} @ ${price(o.fillPrice, i.assetClass)}`, true] : [`Order #${o.id} ${isPendingStop(o) ? "armed: waiting for the stop" : "working"}`, true]);
      setQty("");
    } catch (e) { setMsg([e instanceof OrderReject ? e.message : "Rejected", false]); }
  };
  const working = broker.account.workingOrders.filter((o) => o.symbol === i.symbol);
  return (
    <div className="ticket">
      <div className="sides">
        {(["SELL", "BUY"] as const).map((s) => <button key={s} className={`side ${s.toLowerCase()} ${side === s ? "on" : ""}`} onClick={() => { setSide(s); prefillLimit(s); if (isStop) prefillStop(s); }}>{s}<b>{price(s === "BUY" ? q?.ask ?? q?.last : q?.bid ?? q?.last, i.assetClass)}</b></button>)}
      </div>
      <div className="mono" style={{ display: "flex", fontSize: 9, fontWeight: 700 }}>
        <span style={{ color: isStreaming(i) || i.assetClass === "OPTION" ? "var(--go)" : "var(--warn)" }}>{i.assetClass === "OPTION" ? "DERIBIT BOOK · LONG ONLY" : isStreaming(i) ? "LIVE TOP OF BOOK" : "DELAYED · FILLS AT LAST"}</span>
        <span className="spacer" />{q?.bid != null && q?.ask != null && <span className="dim" style={{ fontWeight: 400 }}>SPREAD {price(q.ask - q.bid, i.assetClass)}</span>}
      </div>
      {side === "SELL" && amount != null && amount > Math.max(held, 0) && <div className="warn mono" style={{ fontSize: 10, fontWeight: 600 }}>This sell opens or extends a SHORT. 150% of its value is held as margin.</div>}
      <label className="tfield"><span>QUANTITY</span><input inputMode="decimal" value={qtyText} onChange={(e) => setQty(e.target.value)} placeholder="0" aria-label="Quantity" /></label>
      <div className="presets">{presets.map((p) => <button key={p} onClick={() => setQty(String(p))}>{qty(p)}</button>)}</div>
      <Seg label="Order type" value={kind} options={["MARKET", "LIMIT", "STOP", "STOP LMT"] as const} onChange={(k) => { setKind(k); if ((k === "LIMIT" || k === "STOP LMT") && !limitText) prefillLimit(); if (k === "STOP" || k === "STOP LMT") prefillStop(); }} />
      {isStop && <label className="tfield"><span>STOP PRICE · TRIGGERS AT OR {side === "BUY" ? "ABOVE" : "BELOW"}</span><input inputMode="decimal" value={stopText} onChange={(e) => setStop(e.target.value)} placeholder="0.00" /></label>}
      {isLimit && <label className="tfield"><span>LIMIT PRICE</span><input inputMode="decimal" value={limitText} onChange={(e) => setLimit(e.target.value)} placeholder="0.00" /></label>}
      <div className="kv">
        <div><span>EST. NOTIONAL</span><b>{amount != null && est != null ? money(amount * est) : "—"}</b></div>
        <div><span>BUYING POWER</span><b>{money(broker.account.buyingPower)}</b></div>
        <div><span>POSITION</span><b>{held < 0 ? `${qty(held)} SHORT` : qty(held)}</b></div>
        <div><span>AVG COST</span><b>{pos && pos.quantity ? price(pos.averageCost, i.assetClass) : "—"}</b></div>
      </div>
      <div className="send">
        <button className={armed ? "arm" : side === "BUY" ? "go-buy" : "go-sell"} disabled={amount == null} onClick={() => { if (armed) { setArmed(false); send(); } else setArmed(true); }}>
          {armed ? `CONFIRM ${side} ${qtyText} ${i.ticker} ${terms}` : `${side} ${qtyText ? qtyText + " " : ""}${i.ticker} ${short}`}
        </button>
        {armed && <button className="cxl" onClick={() => setArmed(false)}>CXL</button>}
      </div>
      {armed && <div className="dim mono" style={{ fontSize: 9 }}>Paper order: simulated execution, no real money moves.</div>}
      {msg && <div className={`mono ${msg[1] ? "up" : ""}`} style={{ fontSize: 11, color: msg[1] ? undefined : "var(--cancel)" }} role="status">{msg[0]}</div>}
      {working.length > 0 && <><Section title="WORKING ORDERS" /><Orders list={working} /></>}
    </div>
  );
}

function Orders({ list }: { list: Order[] }) {
  return (
    <table className="t"><tbody>{list.map((o) => (
      <tr key={o.id} title={o.note ?? ""}>
        <td className="dim">#{o.id}</td><td className="dim">{clock(o.created)}</td><td className={o.side === "BUY" ? "up" : "down"}>{o.side}</td>
        <td>{qty(o.quantity)}</td><td><b>{tickerOf(o.symbol)}</b></td><td className="label">{typeLabel(o.type)}</td><td>{o.fillPrice != null ? `@ ${price(o.fillPrice)}` : ""}</td>
        <td style={{ fontWeight: 700, color: o.status === "WORKING" ? "var(--warn)" : o.status === "FILLED" ? "var(--up)" : o.status === "REJECTED" ? "var(--cancel)" : "var(--dim)" }}>{o.status === "WORKING" && o.triggered ? "TRIGGERED" : o.status}</td>
        <td>{o.status === "WORKING" && <button className="cxl-sm" onClick={() => broker.cancel(o.id)} aria-label={`Cancel order ${o.id}`}>CXL</button>}</td>
      </tr>))}</tbody></table>
  );
}

/** PORT: account value, P&L and positions. */
export function Portfolio({ panel }: { panel: number }) {
  useStore(broker); useStore(market);
  const a = broker.account;
  const [confirm, setConfirm] = useState(false);
  const mark = (s: string, cost: number) => market.quotes.get(s)?.last ?? broker.marks[s] ?? cost;
  return (
    <div>
      <div className="tiles">
        <Tile k="NET LIQUIDATION" v={money(broker.equity)} /><Tile k="TOTAL P&L" v={signedMoney(broker.totalPnL)} className={tint(broker.totalPnL)} s={pct((broker.totalPnL / PaperAccount.startingCash) * 100)} />
        <Tile k="UNREALIZED" v={signedMoney(broker.unrealized)} className={tint(broker.unrealized)} /><Tile k="REALIZED" v={signedMoney(a.realizedPnL)} className={tint(a.realizedPnL)} />
        <Tile k="CASH" v={money(a.cash)} /><Tile k="BUYING POWER" v={money(a.buyingPower)} s={a.shortMarginHeld ? `${money(a.shortMarginHeld)} SHORT MARGIN` : undefined} />
      </div>
      <RiskPanel />
      {broker.curve.length > 1 && <Section title="EQUITY CURVE" right={`${broker.curve.length} SNAPSHOTS`} />}
      {broker.curve.length > 1 && <div style={{ padding: 8 }}><LineChart x={broker.curve.map((p) => p.t)} series={[{ name: "Account value", values: broker.curve.map((p) => p.v), width: 2 }]} zero={PaperAccount.startingCash} xFormat={(t) => new Date(t).toLocaleDateString("en-US", { month: "short", day: "numeric" })} yLabel="Account value ($)" h={150} /></div>}
      <Section title="POSITIONS" right={`${a.openPositions.length} OPEN`} />
      {a.openPositions.length === 0 ? <Empty title="No positions" detail="Try BTC BUY or AAPL TRADE. Every account starts with $1,000,000 of paper money." /> :
        <table className="t"><thead><tr><th style={{ textAlign: "left" }}>SECURITY</th><th>QTY</th><th>AVG COST</th><th>MARK</th><th>MKT VALUE</th><th>UNRL P&L</th><th>%</th></tr></thead>
          <tbody>{a.openPositions.map((p) => { const m = mark(p.symbol, p.averageCost), u = p.quantity * (m - p.averageCost), basis = Math.abs(p.quantity) * p.averageCost, inst = instrument(p.symbol) ?? resolve(p.symbol);
            return <tr key={p.symbol} className="click" tabIndex={0} onClick={() => inst && workspace.link(inst, panel)}>
              <td style={{ textAlign: "left" }}><b>{inst?.assetClass === "OPTION" ? inst.name : tickerOf(p.symbol)}</b>{p.quantity < 0 && <span className="badge" style={{ marginLeft: 6, background: "var(--down)", color: "var(--canvas)" }}>SHORT</span>}</td>
              <td>{qty(p.quantity)}</td><td>{price(p.averageCost)}</td><td>{price(m)}</td><td>{money(p.quantity * m)}</td><td className={tint(u)}>{signedMoney(u)}</td><td className={tint(u)}>{basis ? pct((u / basis) * 100) : "—"}</td></tr>; })}</tbody></table>}
      <div style={{ display: "flex", justifyContent: "flex-end", padding: 8, gap: 8 }}>
        {confirm ? <><span className="mono warn" style={{ fontSize: 10, alignSelf: "center" }}>Reset to $1,000,000 and erase all orders?</span><button className="textbtn danger" onClick={() => { broker.reset(); setConfirm(false); }}>RESET</button><button className="textbtn" onClick={() => setConfirm(false)}>KEEP</button></>
          : <button className="textbtn danger" onClick={() => setConfirm(true)}>Reset paper account</button>}
      </div>
    </div>
  );
}

/** BLOT: every order and execution. */
export function Blotter() {
  useStore(broker);
  const a = broker.account;
  return (
    <div>
      <Section title="ORDERS" right={`${a.workingOrders.length} WORKING`} />
      {a.orders.length ? <Orders list={[...a.orders].reverse().slice(0, 500)} /> : <Empty title="No orders yet" detail="Open a ticket with BTC BUY, AAPL SELL or NVDA TRADE." />}
      <Section title="EXECUTIONS" right={String(a.fills.length)} />
      <table className="t"><tbody>{[...a.fills].reverse().slice(0, 500).map((f) => (
        <tr key={f.id}><td className="dim">{clock(f.time)}</td><td className={f.side === "BUY" ? "up" : "down"}>{f.side}</td><td>{qty(f.quantity)} <b>{tickerOf(f.symbol)}</b></td><td>@ {price(f.price)}</td>
          <td className="dim">NOTIONAL {money(f.quantity * f.price)}</td><td className={tint(f.realized)}>{f.realized !== 0 || f.side === "SELL" ? `RLZD ${signedMoney(f.realized)}` : ""}</td></tr>))}</tbody></table>
    </div>
  );
}

/** ALRT: create, watch and review price alerts. */
export function Alerts({ i, panel }: { i?: Instrument; panel: number }) {
  useStore(alerts); useStore(market);
  const [kind, setKind] = useState<"ABOVE" | "BELOW" | "MOVE %">("ABOVE");
  const [text, setText] = useState("");
  const [msg, setMsg] = useState<[string, boolean] | null>(null);
  const q = i ? market.quotes.get(i.symbol) : undefined;
  const prefill = (k = kind) => setText(k === "MOVE %" ? "3" : q && i ? plain(q.last * (k === "ABOVE" ? 1.02 : 0.98), i) : "");
  useEffect(() => { if (!text) prefill(); }, [q != null]);
  const level = num(text);
  const create = () => {
    if (!i) return;
    if (level == null) return setMsg(["Enter a number", false]);
    const c: AlertCondition = kind === "ABOVE" ? { kind: "above", level } : kind === "BELOW" ? { kind: "below", level } : { kind: "move", percent: level };
    try { alerts.add(i, c); setMsg([`Alert set: ${i.ticker} ${conditionLabel(c)}`, true]); }
    catch (e) { setMsg([e instanceof AlertError ? e.message : "Rejected", false]); }
  };
  const b = alerts.book;
  return (
    <div>
      {i ? <div style={{ padding: 8, display: "flex", flexDirection: "column", gap: 8 }}>
        <div className="mono" style={{ display: "flex", gap: 10, alignItems: "baseline" }}><b className="accent" style={{ fontSize: 10 }}>NEW ALERT</b><b>{i.ticker}</b><span className="label" style={{ fontSize: 9 }}>LAST</span><b>{price(q?.last, i.assetClass)}</b><span className={tint(changePercent(q) ?? 0)} style={{ fontSize: 11 }}>{pct(changePercent(q))}</span></div>
        <Seg label="Condition" value={kind} options={["ABOVE", "BELOW", "MOVE %"] as const} onChange={(k) => { setKind(k); prefill(k); }} />
        <form style={{ display: "flex", gap: 8, alignItems: "center" }} onSubmit={(e) => { e.preventDefault(); create(); }}>
          <input className="field" style={{ width: 160, fontSize: 15 }} inputMode="decimal" value={text} onChange={(e) => setText(e.target.value)} placeholder={kind === "MOVE %" ? "e.g. 5" : "price"} aria-label="Alert level" />
          {kind !== "MOVE %" && level != null && q?.last ? <span className="dim mono" style={{ fontSize: 10 }}>{pct((level / q.last - 1) * 100)} away</span> : null}
          <button className="primary" style={{ width: 64, height: 32 }} type="submit">SET</button>
        </form>
        {msg && <div className="mono" style={{ fontSize: 11, color: msg[1] ? "var(--up)" : "var(--cancel)" }} role="status">{msg[0]}</div>}
        <div className="faint" style={{ fontSize: 10 }}>Alerts fire once, on the first quote that meets the condition, while Kestrel is open in a tab. Delayed securities are checked on each refresh.</div>
      </div> : <p className="dim" style={{ fontSize: 11, padding: 8 }}>Load a security to create an alert: AAPL ALRT, BTC ALRT.</p>}
      <Section title="ACTIVE" right={String(b.active.length)} />
      {b.active.length === 0 ? <p className="dim mono" style={{ fontSize: 11, padding: 8 }}>No active alerts.</p> :
        <table className="t"><tbody>{b.active.map((a) => { const aq = market.quotes.get(a.symbol), c = a.condition;
          const dist = !aq?.last ? "—" : c.kind === "move" ? pct(changePercent(aq)) : pct((c.level / aq.last - 1) * 100);
          return <tr key={a.id} className="click" tabIndex={0} onClick={() => { const x = instrument(a.symbol) ?? resolve(a.symbol); if (x) workspace.link(x, panel); }}>
            <td style={{ textAlign: "left" }}><span className="warn">●</span> <b>{tickerOf(a.symbol)}</b></td><td className="label">{conditionLabel(c)}</td><td>LAST {price(aq?.last)}</td><td className="dim">{dist}</td>
            <td><button className="cxl-sm" onClick={(e) => { e.stopPropagation(); alerts.cancel(a.id); }} aria-label="Cancel alert">CXL</button></td></tr>; })}</tbody></table>}
      <Section title="TRIGGERED" right={b.history.length ? String(b.history.length) : undefined} />
      <table className="t"><tbody>{b.history.slice(0, 50).map((a) => <tr key={a.id}><td style={{ textAlign: "left" }}><span className="up">✓</span> <b>{tickerOf(a.symbol)}</b></td><td className="dim">{conditionLabel(a.condition)}</td><td>@ {price(a.triggerPrice)}</td>
        <td className="dim">{new Date(a.triggered!).toLocaleString("en-US", { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit", hour12: false })}</td></tr>)}</tbody></table>
      {b.history.length > 0 && <button className="textbtn" onClick={() => alerts.clearHistory()}>Clear history</button>}
    </div>
  );
}

/** Banner for fills and fired alerts. */
export function Toasts() {
  useStore(alerts); useStore(broker);
  const [shown, setShown] = useState<{ k: string; v: string; id: string } | null>(null);
  const a = alerts.lastAlert, f = broker.lastFill;
  useEffect(() => { if (a) setShown({ id: a.id, k: `ALERT · ${tickerOf(a.symbol)}`, v: `${conditionLabel(a.condition)} · last ${price(a.triggerPrice)}` }); }, [a]);
  useEffect(() => { if (f) setShown({ id: `f${f.id}`, k: `FILLED · ${tickerOf(f.symbol)}`, v: `${f.side} ${qty(f.quantity)} @ ${price(f.price)}` }); }, [f]);
  useEffect(() => { if (!shown) return; const t = setTimeout(() => setShown(null), 6000); return () => clearTimeout(t); }, [shown]);
  return shown ? <div className="toast" role="status"><div className="k">{shown.k}</div><div className="v">{shown.v}</div></div> : null;
}

/** PORT risk: exposures, equity-weighted beta to the S&P 500, 1-day historical VaR and expected shortfall, net crypto delta. */
function RiskPanel() {
  useStore(broker); useStore(market);
  const a = broker.account;
  const exposures = a.openPositions.flatMap((p) => {
    const i = instrument(p.symbol) ?? resolve(p.symbol);
    return i ? [{ i, value: p.quantity * (market.quotes.get(p.symbol)?.last ?? broker.marks[p.symbol] ?? p.averageCost) }] : [];
  });
  const key = a.openPositions.map((p) => `${p.symbol}:${p.quantity}`).join(",");
  const risk = useAsync(async () => {
    const held = exposures.filter((e) => e.i.assetClass !== "OPTION");
    if (!held.length) return null;
    const spx = resolve("SPX")!;
    const hist = Object.fromEntries((await Promise.all([...held.map((e) => e.i), spx].map(async (i) => [i.symbol, await history(i, "1y").catch(() => [])] as const))).filter(([, c]) => c.length > 20));
    if (!hist[spx.symbol]) return null;
    const r = alignedReturns(hist), eq = Math.max(broker.equity, 1);
    const exp: Record<string, number> = {};
    for (const e of held) if (r[e.i.symbol]) exp[e.i.symbol] = (exp[e.i.symbol] ?? 0) + e.value;
    const pnl = pnlSeries(exp, r);
    const beta = Object.entries(exp).reduce((s, [k, v]) => s + (v / eq) * (betaOf(r[k] ?? [], r[spx.symbol] ?? []) ?? 0), 0);
    return { beta, var95: historicalVaR(pnl), es95: expectedShortfall(pnl), days: pnl.length };
  }, [key]);
  if (!exposures.length) return null;
  const eq = Math.max(broker.equity, 1);
  const long = exposures.filter((e) => e.value > 0).reduce((s, e) => s + e.value, 0);
  const short = exposures.filter((e) => e.value < 0).reduce((s, e) => s + e.value, 0);
  const gross = long - short;
  const deltas = new Map<string, number>();
  for (const p of a.openPositions) {
    const o = parseOption(p.symbol);
    if (o) { const c = contracts.get(p.symbol), g = c && contractGreeks(c); if (g) deltas.set(o.underlying, (deltas.get(o.underlying) ?? 0) + p.quantity * g.delta); }
    else if (/^(BTC|ETH)-USD$/.test(p.symbol)) { const u = p.symbol.slice(0, 3); deltas.set(u, (deltas.get(u) ?? 0) + p.quantity); }
  }
  const byClass = new Map<string, number>();
  for (const e of exposures) byClass.set(e.i.assetClass, (byClass.get(e.i.assetClass) ?? 0) + Math.abs(e.value));
  const loss = (v?: number | null) => (v == null ? "—" : `-$${compact(v)}`);
  const r = risk.data;
  return (
    <>
      <Section title="RISK" right={r ? `${r.days} DAYS · HISTORICAL` : risk.loading ? "COMPUTING…" : undefined} />
      <div className="tiles">
        <Tile k="GROSS EXPOSURE" v={`$${compact(gross)}`} s={`${((gross / eq) * 100).toFixed(0)}% OF EQUITY`} />
        <Tile k="NET EXPOSURE" v={`${long + short < 0 ? "-" : ""}$${compact(Math.abs(long + short))}`} s={`${(((long + short) / eq) * 100).toFixed(0)}% OF EQUITY`} />
        <Tile k="LONG / SHORT" v={`$${compact(long)} / $${compact(Math.abs(short))}`} s={`${exposures.filter((e) => e.value < 0).length} SHORT`} />
        <Tile k="BETA (S&P 500)" v={r ? r.beta.toFixed(2) : "—"} s="EQUITY-WEIGHTED" />
        <Tile k="1-DAY VaR 95%" v={loss(r?.var95)} s="HISTORICAL SIMULATION" className="warn" />
        <Tile k="EXP. SHORTFALL 95%" v={loss(r?.es95)} s="AVG LOSS BEYOND VaR" className="down" />
        {deltas.size > 0 && <Tile k="NET DELTA" v={[...deltas].map(([u, d]) => `${u} ${d >= 0 ? "+" : ""}${d.toFixed(3)}`).join("  ")} s="SPOT + OPTIONS, IN COINS" className="accent" />}
      </div>
      <div style={{ padding: "6px 8px", display: "flex", flexDirection: "column", gap: 3 }}>
        {[...byClass].sort((x, y) => y[1] - x[1]).map(([cls, v]) => (
          <div key={cls} className="mono" style={{ display: "flex", alignItems: "center", gap: 8, fontSize: 9 }}>
            <b className="label" style={{ width: 60 }}>{cls}</b>
            <div style={{ flex: 1, height: 8 }}><div style={{ width: `${gross ? (v / gross) * 100 : 0}%`, height: "100%", background: "var(--accent)", opacity: 0.7 }} /></div>
            <span className="dim" style={{ width: 40, textAlign: "right" }}>{gross ? ((v / gross) * 100).toFixed(0) : 0}%</span>
          </div>
        ))}
      </div>
    </>
  );
}

