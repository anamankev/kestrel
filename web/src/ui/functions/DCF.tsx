import { useEffect, useMemo, useState } from "react";
import type { Instrument } from "../../core/instrument";
import { compact, price } from "../../core/format";
import { dcf, defaultInputs, ERP, freeCashFlow, sensitivity, type DCFInputs } from "../../core/dcf";
import { csv, csvNum } from "../../core/quant";
import { resolve } from "../../core/universe";
import { cik, fundamentals } from "../../data/research";
import { market } from "../../data/market";
import { useStore } from "../../data/store";
import { Empty, Section, Tile } from "../components";
import { ExportCSV } from "../charts";
import { useAsync } from "../useAsync";

const pct = (v?: number, d = 1) => (v == null || !Number.isFinite(v) ? "—" : `${(v * 100).toFixed(d)}%`);
const signed = (v?: number) => (v == null || !Number.isFinite(v) ? "—" : `${v > 0 ? "+" : ""}${(v * 100).toFixed(0)}%`);
const TEN_YEAR = resolve("US10Y");

/** DCF: intrinsic value per share from SEC free cash flow, with editable assumptions and a sensitivity grid. */
export function DCF({ i }: { i: Instrument }) {
  useStore(market);
  useEffect(() => { market.touch(i); if (TEN_YEAR) market.touch(TEN_YEAR); }, [i]);
  const s = useAsync(async () => { const c = await cik(i); return c ? fundamentals(c) : null; }, [i.symbol]);
  if (i.assetClass !== "EQUITY") return <Empty title="DCF values companies" detail="Load a US-listed stock, e.g. AAPL DCF." />;
  if (s.loading) return <Empty title="Loading 10-K cash flows from SEC…" />;
  if (s.error) return <Empty title="SEC request failed" detail={s.error} />;
  const f = s.data;
  if (!f || !f.years.length) return <Empty title={`No SEC filings for ${i.ticker}`} detail="DCF uses 10-K cash flows, so it covers US-listed companies." />;
  return <Model key={i.symbol} i={i} f={f} />;
}

function Model({ i, f }: { i: Instrument; f: NonNullable<Awaited<ReturnType<typeof fundamentals>>> }) {
  const tenYear = TEN_YEAR ? market.quotes.get(TEN_YEAR.symbol)?.last : undefined;
  const start = useMemo(() => defaultInputs(f.years, tenYear != null ? tenYear / 100 : undefined), [f, tenYear != null]);   // set once the yield arrives
  const [inp, setInp] = useState<DCFInputs>(start);
  useEffect(() => setInp(start), [start]);
  const last = f.years[f.years.length - 1];
  const netCash = (last.cash ?? 0) - (last.longTermDebt ?? 0);
  const shares = f.sharesOutstanding;
  const px = market.quotes.get(i.symbol)?.last;
  const r = dcf(inp, netCash, shares);
  const field = (label: string, k: keyof DCFInputs, scale: number, step: number, hint?: string) => (
    <label style={{ display: "grid", gap: 3, fontSize: 9, color: "var(--label)", fontWeight: 700 }} title={hint}>{label}
      <input className="field" type="number" step={step} style={{ width: 120 }} aria-label={label}
        value={Number.isFinite(inp[k]) ? +(inp[k] * scale).toFixed(2) : ""}
        onChange={(e) => setInp({ ...inp, [k]: e.target.value === "" ? NaN : Number(e.target.value) / scale })} />
    </label>
  );
  const discounts = [-0.02, -0.01, 0, 0.01, 0.02].map((d) => inp.discount + d);
  const terminals = [0.015, 0.02, 0.025, 0.03, 0.035];
  const grid = shares ? sensitivity(inp, netCash, shares, discounts, terminals) : [];
  return (
    <div>
      <div className="toolbar" style={{ flexWrap: "wrap", gap: 10, alignItems: "end" }}>
        {field("BASE FCF $M", "baseFCF", 1e-6, 100, "Last fiscal year's operating cash flow minus capital spending")}
        {field("GROWTH YRS 1–5 %", "growth", 100, 0.5)}
        {field("TERMINAL GROWTH %", "terminalGrowth", 100, 0.25)}
        {field("DISCOUNT RATE %", "discount", 100, 0.25, `10-year Treasury + beta 1 × ${ERP * 100}% equity risk premium`)}
        <button className="textbtn" onClick={() => setInp(start)}>RESET</button>
        <span className="spacer" />
        {typeof r !== "string" && <ExportCSV name={`${i.ticker}-dcf.csv`} build={() => csv(["Year", "Growth", "Free cash flow", "Discount factor", "Present value"],
          [...r.flows.map((y) => [String(y.year), csvNum(y.growth), csvNum(y.fcf), csvNum(y.factor), csvNum(y.pv)]),
            ["Terminal", csvNum(inp.terminalGrowth), csvNum(r.terminalValue), csvNum(r.flows[9].factor), csvNum(r.pvTerminal)],
            ["Enterprise value", "", "", "", csvNum(r.enterprise)], ["Cash minus long-term debt", "", "", "", csvNum(netCash)],
            ["Equity value", "", "", "", csvNum(r.equity)], ["Value per share", "", "", "", csvNum(r.perShare)]])} />}
      </div>
      {!start.baseKnown && <p className="warn" style={{ fontSize: 12, padding: "0 10px" }}>{f.name}'s latest free cash flow is {compact(last ? freeCashFlow(last) : undefined)}, so there is nothing positive to grow. Enter the base you expect to model a turnaround.</p>}
      {typeof r === "string" ? <Empty title="Check the inputs" detail={r} /> : <>
        <div className="tiles">
          <Tile k="INTRINSIC VALUE / SHARE" v={price(r.perShare)} s={shares ? `${compact(shares)} SHARES (SEC)` : "SHARE COUNT UNAVAILABLE"} />
          <Tile k="PRICE" v={price(px)} s="DELAYED" />
          <Tile k="UPSIDE" v={r.perShare && px ? signed(r.perShare / px - 1) : "—"} s={r.perShare && px ? (r.perShare > px ? "MODEL ABOVE PRICE" : "MODEL BELOW PRICE") : ""} className={r.perShare && px ? (r.perShare > px ? "up" : "down") : ""} />
          <Tile k="TERMINAL SHARE OF VALUE" v={pct(r.terminalShare, 0)} s={r.terminalShare > 0.75 ? "MOST VALUE IS BEYOND YEAR 10" : "OF ENTERPRISE VALUE"} className={r.terminalShare > 0.75 ? "warn" : ""} />
        </div>
        <Section title={`${i.ticker} · FREE CASH FLOW HISTORY (10-K)`} right={f.name.toUpperCase()} />
        <table className="t">
          <thead><tr><th style={{ textAlign: "left" }}>FISCAL YEAR</th><th>REVENUE</th><th>OPERATING CASH FLOW</th><th>CAPEX</th><th>FREE CASH FLOW</th><th>FCF MARGIN</th></tr></thead>
          <tbody>{f.years.map((y) => { const fcf = freeCashFlow(y); return (
            <tr key={y.year}><td style={{ textAlign: "left" }}><b>FY{y.year}</b></td><td>{compact(y.revenue)}</td><td>{compact(y.operatingCashFlow)}</td><td>{compact(y.capex)}</td>
              <td className={fcf != null && fcf < 0 ? "down" : ""}>{compact(fcf)}</td><td>{fcf != null && y.revenue ? pct(fcf / y.revenue) : "—"}</td></tr>); })}</tbody>
        </table>
        <Section title="PROJECTION" right={`DISCOUNTED AT ${pct(inp.discount, 2)}`} />
        <table className="t">
          <thead><tr><th style={{ textAlign: "left" }}>YEAR</th><th>GROWTH</th><th>FREE CASH FLOW</th><th>DISCOUNT FACTOR</th><th>PRESENT VALUE</th></tr></thead>
          <tbody>
            {r.flows.map((y) => <tr key={y.year}><td style={{ textAlign: "left" }}>{y.year}</td><td>{pct(y.growth)}</td><td>{compact(y.fcf)}</td><td>{y.factor.toFixed(3)}</td><td>{compact(y.pv)}</td></tr>)}
            <tr><td style={{ textAlign: "left" }}><b>TERMINAL</b></td><td>{pct(inp.terminalGrowth)}</td><td>{compact(r.terminalValue)}</td><td>{r.flows[9].factor.toFixed(3)}</td><td>{compact(r.pvTerminal)}</td></tr>
          </tbody>
        </table>
        <Section title="FROM ENTERPRISE VALUE TO VALUE PER SHARE" />
        <table className="t"><tbody>
          <tr><td style={{ textAlign: "left" }}>Present value of years 1–10</td><td>{compact(r.pvFlows)}</td></tr>
          <tr><td style={{ textAlign: "left" }}>+ Present value of terminal value</td><td>{compact(r.pvTerminal)}</td></tr>
          <tr><td style={{ textAlign: "left" }}><b>= Enterprise value</b></td><td><b>{compact(r.enterprise)}</b></td></tr>
          <tr><td style={{ textAlign: "left" }}>+ Cash − long-term debt (FY{last.year})</td><td>{compact(netCash)}</td></tr>
          <tr><td style={{ textAlign: "left" }}><b>= Equity value</b></td><td><b>{compact(r.equity)}</b></td></tr>
          <tr><td style={{ textAlign: "left" }}>÷ Shares outstanding</td><td>{compact(shares)}</td></tr>
          <tr><td style={{ textAlign: "left" }}><b>= Value per share</b></td><td><b>{price(r.perShare)}</b></td></tr>
        </tbody></table>
        {grid.length > 0 && <>
          <Section title="SENSITIVITY · VALUE PER SHARE" right="ROWS: DISCOUNT RATE · COLUMNS: TERMINAL GROWTH" />
          <table className="t" aria-label="Value per share by discount rate and terminal growth">
            <thead><tr><th style={{ textAlign: "left" }}>DISCOUNT ↓ / TERMINAL →</th>{terminals.map((t) => <th key={t}>{pct(t)}</th>)}</tr></thead>
            <tbody>{grid.map((row, a) => (
              <tr key={a}><td style={{ textAlign: "left" }}><b>{pct(discounts[a], 2)}</b></td>
                {row.map((v, b) => <td key={b} className={v != null && px ? (v > px ? "up" : "down") : "dim"}
                  style={discounts[a] === inp.discount && terminals[b] === inp.terminalGrowth ? { outline: "1px solid var(--accent)" } : undefined}>{v == null ? "—" : price(v)}</td>)}</tr>))}</tbody>
          </table>
        </>}
        <p className="faint" style={{ fontSize: 10, padding: 8 }}>Free cash flow = operating cash flow − capital expenditures from 10-K filings. Years 1–5 grow at the stage-1 rate, years 6–10 fade to terminal growth, and the terminal value is a growing perpetuity. The discount rate is applied to cash flow to the whole firm, then net cash is added: a teaching model, not advice. Banks and insurers are poorly suited to free-cash-flow DCF.</p>
      </>}
    </div>
  );
}
