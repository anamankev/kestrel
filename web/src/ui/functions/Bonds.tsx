import { useEffect, useMemo, useState } from "react";
import { bondRisk, curveOn, interpolate, schedule, TENORS, yieldFromPrice, type CurveDay } from "../../core/bonds";
import { csv, csvNum } from "../../core/quant";
import { treasuryCurves } from "../../data/research";
import { Empty, Section, Seg, Tile } from "../components";
import { ExportCSV, LineChart } from "../charts";
import { useAsync } from "../useAsync";

const DAY = 86_400_000;
const date = (t: number) => new Date(t).toISOString().slice(0, 10);
const bp = (v?: number) => (v == null || !Number.isFinite(v) ? "—" : `${v > 0 ? "+" : ""}${Math.round(v)} bp`);
const pctY = (v?: number) => (v == null ? "—" : `${v.toFixed(2)}%`);
const tint = (v?: number) => (v == null || Math.round(v) === 0 ? "" : v > 0 ? "up" : "down");

/** GC: today's Treasury par curve against 1 month, 1 year and 5 years ago, and the 10Y–2Y spread history. */
export function YieldCurve() {
  const s = useAsync(() => treasuryCurves(5), []);
  if (s.loading) return <Empty title="Loading Treasury yield curves…" />;
  if (s.error || !s.data) return <Empty title="Treasury data unavailable" detail={s.error ?? undefined} />;
  return <CurveReport days={s.data} />;
}

function CurveReport({ days }: { days: CurveDay[] }) {
  const today = days[days.length - 1];
  const back = (d: number) => curveOn(days, today.date - d * DAY);
  const curves = [
    { name: "TODAY", day: today, color: "var(--accent)", width: 2.2 },
    { name: "1M AGO", day: back(30), color: "var(--text)", dash: "4 3" },
    { name: "1Y AGO", day: back(365), color: "var(--warn)", dash: "4 3" },
    { name: "5Y AGO", day: back(5 * 365 + 1), color: "var(--dim)", dash: "2 3" },
  ].filter((c) => c.day);
  const tenors = TENORS.filter((t) => today.yields[t.label] != null);
  const spread = (d: CurveDay) => (d.yields["10Y"] != null && d.yields["2Y"] != null ? (d.yields["10Y"] - d.yields["2Y"]) * 100 : null);
  const hist = days.filter((_, k) => k % 3 === 0 || k === days.length - 1);
  const s10 = spread(today), y1 = back(365);
  const inverted = days.filter((d) => (spread(d) ?? 0) < 0).length / days.length;
  return (
    <div>
      <div className="tiles">
        {["2Y", "10Y", "30Y"].map((t) => <Tile key={t} k={`${t} TREASURY`} v={pctY(today.yields[t])} s={`1Y CHANGE ${bp(y1?.yields[t] != null && today.yields[t] != null ? (today.yields[t] - y1.yields[t]) * 100 : undefined)}`} />)}
        <Tile k="10Y – 2Y SPREAD" v={bp(s10 ?? undefined)} s={s10 == null ? "" : s10 < 0 ? "INVERTED: SHORT RATES ABOVE LONG" : "UPWARD SLOPING"} className={s10 != null && s10 < 0 ? "down" : "up"} />
      </div>
      <Section title="U.S. TREASURY PAR YIELD CURVE" right={`AS OF ${date(today.date)} · TREASURY.GOV`} />
      <div style={{ padding: 8 }}>
        <LineChart x={tenors.map((_, k) => k)} xFormat={(k) => tenors[Math.round(k)]?.label ?? ""} yLabel="Par yield by maturity"
          series={curves.map((c) => ({ name: c.name, values: tenors.map((t) => c.day!.yields[t.label] ?? null), color: c.color, width: c.width, dash: c.dash }))} />
        <div className="legend" style={{ display: "flex", gap: 14, fontSize: 10, flexWrap: "wrap" }}>
          {curves.map((c) => <span key={c.name}><span style={{ display: "inline-block", width: 14, height: 2, background: c.color, verticalAlign: "middle", marginRight: 4 }} />{c.name} {date(c.day!.date)}</span>)}
        </div>
      </div>
      <Section title="10Y – 2Y SPREAD (BP)" right={`${date(days[0].date)} – ${date(today.date)} · INVERTED ${(inverted * 100).toFixed(0)}% OF DAYS`} />
      <div style={{ padding: 8 }}>
        <LineChart x={hist.map((d) => d.date)} xFormat={(t) => date(t).slice(0, 7)} zero={0} yLabel="10-year minus 2-year Treasury yield, basis points"
          series={[{ name: "10Y-2Y", values: hist.map(spread), color: "var(--accent)" }]} />
      </div>
      <div className="toolbar"><span className="spacer" />
        <ExportCSV name={`treasury-curve-${date(today.date)}.csv`} build={() => csv(["Tenor", ...curves.map((c) => `${c.name} (${date(c.day!.date)})`)],
          tenors.map((t) => [t.label, ...curves.map((c) => csvNum(c.day!.yields[t.label]))]))} />
      </div>
      <table className="t">
        <thead><tr><th style={{ textAlign: "left" }}>TENOR</th>{curves.map((c) => <th key={c.name}>{c.name}</th>)}<th>1Y CHG</th><th>5Y CHG</th></tr></thead>
        <tbody>{tenors.map((t) => {
          const now = today.yields[t.label];
          const chg = (c?: CurveDay) => (c?.yields[t.label] != null ? (now - c.yields[t.label]) * 100 : undefined);
          return <tr key={t.label}><td style={{ textAlign: "left" }}><b>{t.label}</b></td>{curves.map((c) => <td key={c.name}>{pctY(c.day!.yields[t.label])}</td>)}
            <td className={tint(chg(y1))}>{bp(chg(y1))}</td><td className={tint(chg(back(5 * 365 + 1)))}>{bp(chg(back(5 * 365 + 1)))}</td></tr>;
        })}</tbody>
      </table>
      <p className="faint" style={{ fontSize: 10, padding: 8 }}>Par yields from the U.S. Treasury's daily yield curve (bond-equivalent, percent). A negative 10Y–2Y spread (an inverted curve) has preceded most U.S. recessions, with long and variable lags.</p>
    </div>
  );
}

interface Inputs { coupon: string; maturity: string; mode: "PRICE→YIELD" | "YIELD→PRICE"; price: string; yld: string; face: string }
const KEY = "yas.inputs";
const SHOCKS = [-100, -50, -25, 0, 25, 50, 100];
const money = (v: number) => v.toLocaleString("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 0 });

/** Saved inputs come from plain browser storage, so they are checked before use: short strings and a known mode. */
export function validInputs(v: unknown): Inputs | null {
  if (!v || typeof v !== "object") return null;
  const o = v as Record<string, unknown>;
  const str = (k: string) => (typeof o[k] === "string" && (o[k] as string).length <= 24 ? (o[k] as string) : null);
  const [coupon, maturity, price, yld, face] = ["coupon", "maturity", "price", "yld", "face"].map(str);
  if (coupon == null || maturity == null || price == null || yld == null || face == null || !/^\d{4}-\d{2}-\d{2}$/.test(maturity)) return null;
  if (o.mode !== "PRICE→YIELD" && o.mode !== "YIELD→PRICE") return null;
  return { coupon, maturity, mode: o.mode, price, yld, face };
}

/** YAS: price ↔ yield for a fixed-coupon bond, with duration, convexity, DV01 and the spread to Treasuries. */
export function BondCalculator() {
  const curves = useAsync(() => treasuryCurves(0), []);
  const latest = curves.data?.[curves.data.length - 1];
  const [inp, setInp] = useState<Inputs | null>(() => { try { return validInputs(JSON.parse(localStorage.getItem(KEY) ?? "null")); } catch { return null; } });
  // First visit: a 10-year bond with a coupon near today's 10Y yield.
  useEffect(() => {
    if (inp || !latest) return;
    const y10 = latest.yields["10Y"] ?? 4;
    const t = new Date();
    setInp({ coupon: (Math.round(y10 * 8) / 8).toFixed(3), maturity: date(Date.UTC(t.getFullYear() + 10, t.getMonth(), t.getDate())), mode: "YIELD→PRICE", price: "100", yld: y10.toFixed(3), face: "1000000" });
  }, [inp, latest]);
  useEffect(() => { if (inp) try { localStorage.setItem(KEY, JSON.stringify(inp)); } catch { /* private mode */ } }, [inp]);
  const set = (k: keyof Inputs) => (v: string) => setInp((p) => (p ? { ...p, [k]: v } : p));

  const out = useMemo(() => {
    if (!inp) return null;
    const now = new Date(), settle = Date.UTC(now.getFullYear(), now.getMonth(), now.getDate());
    const c = Number(inp.coupon) / 100, sch = schedule(settle, Date.parse(inp.maturity)), face = Number(inp.face);
    if (!(c >= 0 && c < 1) || !sch || sch.years > 100 || !(face > 0)) return { error: "Enter a coupon from 0 to 100%, a maturity in the future (up to 100 years) and a face amount." };
    const y = inp.mode === "YIELD→PRICE" ? Number(inp.yld) / 100 : yieldFromPrice(c, sch, Number(inp.price));
    if (y == null || !Number.isFinite(y) || y <= -0.05 || y >= 1) return { error: inp.mode === "PRICE→YIELD" ? "No yield between −5% and 100% gives that price." : "Enter a yield between −5% and 100%." };
    const r = bondRisk(c, sch, y);
    const tsy = latest ? interpolate(latest, sch.years) : undefined;
    return { years: sch.years, sch, y, r, face, spread: tsy != null ? (y * 100 - tsy) * 100 : undefined, tsy };
  }, [inp, latest]);

  if (!inp) return curves.error ? <Empty title="Treasury data unavailable" detail={curves.error} /> : <Empty title="Loading today's Treasury curve…" />;
  const field = (label: string, k: keyof Inputs, props: Record<string, unknown> = {}) => (
    <label style={{ display: "grid", gap: 3, fontSize: 9, color: "var(--label)", fontWeight: 700 }}>{label}
      <input className="field" value={inp[k]} onChange={(e) => set(k)(e.target.value)} aria-label={label} style={{ width: 130 }} inputMode="decimal" {...props} />
    </label>
  );
  return (
    <div>
      <div className="toolbar" style={{ flexWrap: "wrap", gap: 10, alignItems: "end" }}>
        {field("COUPON %", "coupon")}
        {field("MATURITY", "maturity", { type: "date", inputMode: undefined })}
        <Seg label="Solve" value={inp.mode} options={["YIELD→PRICE", "PRICE→YIELD"] as const} onChange={(v) => set("mode")(v)} />
        {inp.mode === "YIELD→PRICE" ? field("YIELD %", "yld") : field("CLEAN PRICE", "price")}
        {field("FACE $", "face")}
      </div>
      {!out || "error" in out ? <Empty title="Check the inputs" detail={out?.error} /> : <>
        <div className="tiles">
          <Tile k="CLEAN PRICE" v={out.r.clean.toFixed(4)} s={`DIRTY ${out.r.dirty.toFixed(4)} · ACCRUED ${out.r.accrued.toFixed(4)}`} />
          <Tile k="YIELD TO MATURITY" v={`${(out.y * 100).toFixed(4)}%`} s={`SEMI-ANNUAL · ${out.years.toFixed(2)} YEARS · ${out.sch.n} COUPONS LEFT`} />
          <Tile k="SPREAD TO TREASURIES" v={bp(out.spread)} s={out.tsy != null ? `CURVE AT MATURITY ${out.tsy.toFixed(3)}% · ${date(latest!.date)}` : "CURVE LOADING"} className={tint(out.spread)} />
          <Tile k="MODIFIED DURATION" v={out.r.modified.toFixed(3)} s={`MACAULAY ${out.r.macaulay.toFixed(3)} YEARS`} />
          <Tile k="CONVEXITY" v={out.r.convexity.toFixed(2)} s="PRICE CURVATURE PER 1% MOVE²" />
          <Tile k="DV01" v={money((out.r.dv01 * out.face) / 100)} s={`${out.r.dv01.toFixed(5)} PER 100 · VALUE ${money((out.r.dirty * out.face) / 100)}`} />
        </div>
        <Section title="YIELD SCENARIOS" right="FULL REPRICE VS DURATION + CONVEXITY ESTIMATE" />
        <table className="t">
          <thead><tr><th style={{ textAlign: "left" }}>SHIFT</th><th>YIELD</th><th>CLEAN PRICE</th><th>P&L ON FACE</th><th>% CHANGE</th><th>ESTIMATE</th></tr></thead>
          <tbody>{SHOCKS.map((s) => {
            const p = bondRisk(Number(inp.coupon) / 100, out.sch, out.y + s / 10_000).dirty, dy = s / 10_000;
            const pct = p / out.r.dirty - 1, est = -out.r.modified * dy + 0.5 * out.r.convexity * dy * dy;
            return <tr key={s} style={s === 0 ? { outline: "1px solid var(--accent-dim)" } : undefined}><td style={{ textAlign: "left" }}><b>{s > 0 ? "+" : ""}{s} bp</b></td><td>{((out.y + dy) * 100).toFixed(3)}%</td>
              <td>{(p - out.r.accrued).toFixed(4)}</td><td className={tint(pct)}>{money(((p - out.r.dirty) * out.face) / 100)}</td><td className={tint(pct)}>{(pct * 100).toFixed(2)}%</td><td className="dim">{(est * 100).toFixed(2)}%</td></tr>;
          })}</tbody>
        </table>
        <div className="toolbar"><span className="spacer" />
          <ExportCSV name="bond-scenarios.csv" build={() => csv(["Shift (bp)", "Yield", "Clean price", "Dirty price", "Change"],
            SHOCKS.map((s) => { const p = bondRisk(Number(inp.coupon) / 100, out.sch, out.y + s / 10_000); return [String(s), csvNum(out.y + s / 10_000), csvNum(p.clean), csvNum(p.dirty), csvNum(p.dirty / out.r.dirty - 1)]; }))} />
        </div>
        <p className="faint" style={{ fontSize: 10, padding: 8 }}>Semi-annual coupons, settlement today, accrued interest for the elapsed part of the coupon period, actual/actual day count. Spread is the yield over the Treasury par curve interpolated at the bond's maturity. A teaching calculator, not a pricing source.</p>
      </>}
    </div>
  );
}
