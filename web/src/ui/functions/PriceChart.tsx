import { useEffect, useRef, useState } from "react";
import type { Instrument } from "../../core/instrument";
import type { Candle } from "../../core/market";
import { bollinger, rebase, rsi, sma, vwap } from "../../core/indicators";
import { price, clock } from "../../core/format";
import { isStreaming, resolve } from "../../core/universe";
import { chart } from "../../data/relay";
import { market } from "../../data/market";
import { useStore } from "../../data/store";
import { Empty, Seg } from "../components";

const RANGES = ["1D", "5D", "1M", "6M", "1Y", "5Y"] as const;
type Range = (typeof RANGES)[number];
const YAHOO: Record<Range, [string, string]> = { "1D": ["1d", "5m"], "5D": ["5d", "15m"], "1M": ["1mo", "60m"], "6M": ["6mo", "1d"], "1Y": ["1y", "1d"], "5Y": ["5y", "1wk"] };
const COINBASE: Record<Range, [number, number]> = { "1D": [300, 288], "5D": [3600, 120], "1M": [21600, 124], "6M": [86400, 182], "1Y": [86400, 300], "5Y": [86400, 300] };
const COMPARE = ["SPX", "CCMP", "QQQ", "BTC", "ETH", "GC1", "CL1"];

/** A trendline anchored in time and price, so it survives range changes. */
interface TrendLine { t1: number; p1: number; t2: number; p2: number }

async function load(i: Instrument, r: Range, signal: AbortSignal): Promise<Candle[]> {
  if (isStreaming(i)) {
    const [g, n] = COINBASE[r];
    const rows = (await (await fetch(`https://api.exchange.coinbase.com/products/${i.symbol}/candles?granularity=${g}`, { signal })).json()) as number[][];
    return rows.slice(0, n).reverse().map((k) => ({ time: k[0] * 1000, low: k[1], high: k[2], open: k[3], close: k[4], volume: k[5] }));
  }
  return (await chart(i.symbol, ...YAHOO[r], { signal })).candles;
}

const stored = <T,>(key: string, fallback: T): T => { try { const v = localStorage.getItem(key); return v ? (JSON.parse(v) as T) : fallback; } catch { return fallback; } };
const store = (key: string, v: unknown) => { try { localStorage.setItem(key, JSON.stringify(v)); } catch { /* private mode */ } };
const linesKey = (i: Instrument) => `gp.lines.${i.symbol}`;
const validLines = (v: unknown): TrendLine[] => (Array.isArray(v) ? v.filter((l) => l && [l.t1, l.p1, l.t2, l.p2].every(Number.isFinite)).slice(-50) : []);

export function PriceChart({ i }: { i: Instrument }) {
  useStore(market);
  const [range, setRange] = useState<Range>(() => (localStorage.getItem("gp.range") as Range) ?? "1D");
  const [studies, setStudies] = useState<Record<string, boolean>>(() => stored("gp.studies", { SMA: true }));
  const [lineStyle, setLineStyle] = useState<boolean>(() => stored("gp.line", false));
  const [mode, setMode] = useState<"CROSS" | "DRAW">("CROSS");
  const [lines, setLines] = useState<TrendLine[]>(() => validLines(stored(linesKey(i), [])));
  const [draft, setDraft] = useState<TrendLine | null>(null);
  const [compare, setCompare] = useState<Instrument | null>(null);
  const [compareData, setCompareData] = useState<Candle[]>([]);
  const [data, setData] = useState<Candle[] | null>(null);
  const [failed, setFailed] = useState(false);
  const [hover, setHover] = useState<number | null>(null);
  const canvas = useRef<HTMLCanvasElement>(null);
  const box = useRef<HTMLDivElement>(null);
  const start = useRef<{ x: number; y: number } | null>(null);
  const [size, setSize] = useState({ w: 600, h: 300 });

  useEffect(() => { localStorage.setItem("gp.range", range); store("gp.studies", studies); store("gp.line", lineStyle); }, [range, studies, lineStyle]);
  useEffect(() => {
    const ctl = new AbortController();
    setData(null); setFailed(false);
    const run = () => load(i, range, ctl.signal).then(setData).catch((e) => { if (!ctl.signal.aborted) { setFailed(true); console.warn(e); } });
    run();
    const t = setInterval(run, isStreaming(i) ? 120_000 : 60_000);
    return () => { ctl.abort(); clearInterval(t); };
  }, [i.symbol, range]);
  useEffect(() => {
    setCompareData([]);
    if (!compare) return;
    const ctl = new AbortController();
    load(compare, range, ctl.signal).then(setCompareData).catch(() => {});
    return () => ctl.abort();
  }, [compare?.symbol, range]);
  useEffect(() => {
    const ro = new ResizeObserver(([e]) => setSize({ w: e.contentRect.width, h: e.contentRect.height }));
    if (box.current) ro.observe(box.current);
    return () => ro.disconnect();
  }, []);
  const saveLines = (l: TrendLine[]) => { setLines(l); store(linesKey(i), l.slice(-50)); };

  // Live crypto: fold the streaming price into the latest candle.
  const q = market.quotes.get(i.symbol);
  const candles = data && isStreaming(i) && q && data.length ? [...data.slice(0, -1), { ...data[data.length - 1], close: q.last, high: Math.max(data[data.length - 1].high, q.last), low: Math.min(data[data.length - 1].low, q.last) }] : data;
  const comparing = !!compare && compareData.length > 0 && !!candles?.length;
  const view = comparing ? rebase(candles!, compareData) : null;
  const shown = view?.main ?? candles ?? [];
  const opts: DrawOptions = { studies, hover, i, lineStyle: lineStyle || comparing, compare: view?.other ?? [], compareLabel: compare?.ticker, percent: comparing, lines: comparing ? [] : lines, draft: comparing ? null : draft };

  useEffect(() => draw(canvas.current, shown, size, opts), [shown, size, studies, hover, i, lineStyle, lines, draft, comparing]);

  const at = (e: React.MouseEvent<HTMLCanvasElement>) => { const r = e.currentTarget.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top }; };
  const point = (p: { x: number; y: number }) => { const s = scaleOf(shown, size, studies); return { t: s.timeAt(p.x), p: s.priceAt(p.y) }; };
  const h = hover !== null && candles ? candles[hover] : candles?.[candles.length - 1];
  /** The chart as drawn, under a title bar, downloaded as a PNG at screen resolution. */
  const savePNG = () => {
    const src = canvas.current;
    if (!src || !src.width) return;
    const dpr = src.width / Math.max(1, size.w), head = Math.round(28 * dpr);
    const out = document.createElement("canvas");
    out.width = src.width; out.height = src.height + head;
    const g = out.getContext("2d")!;
    g.fillStyle = css("--panel"); g.fillRect(0, 0, out.width, out.height);
    g.drawImage(src, 0, head);
    g.font = `700 ${12 * dpr}px ${css("--mono")}`; g.textBaseline = "middle";
    g.fillStyle = css("--accent"); g.fillText(`KESTREL · ${i.ticker} GP · ${range}${comparing ? ` VS ${compare!.ticker}` : ""}`, 10 * dpr, head / 2);
    g.textAlign = "right"; g.fillStyle = css("--dim"); g.fillText(new Date().toLocaleString("en-US", { dateStyle: "medium", timeStyle: "short" }), out.width - 10 * dpr, head / 2);
    const now = new Date(), day = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;
    out.toBlob((b) => {
      if (!b) return;
      const a = document.createElement("a");
      a.href = URL.createObjectURL(b); a.download = `${i.ticker.replace(/[^A-Za-z0-9.-]/g, "-")}-${range}-${day}.png`;
      a.click(); setTimeout(() => URL.revokeObjectURL(a.href), 2000);
    }, "image/png");
  };
  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100%" }}>
      <div className="toolbar">
        <Seg label="Range" value={range} options={RANGES} onChange={setRange} />
        <div className="seg" role="group" aria-label="Chart style and studies">
          <button className="on" onClick={() => setLineStyle(!lineStyle)} title="Switch between candles and a line">{lineStyle ? "LINE" : "OHLC"}</button>
          {["SMA", "BOLL", "VWAP", "RSI"].map((s) => <button key={s} aria-pressed={!!studies[s]} className={studies[s] ? "on" : ""} onClick={() => setStudies({ ...studies, [s]: !studies[s] })}>{s === "SMA" ? "SMA 20/50" : s}</button>)}
        </div>
        <div className="seg" role="group" aria-label="Tools">
          {(["CROSS", "DRAW"] as const).map((m) => <button key={m} aria-pressed={mode === m} className={mode === m ? "on" : ""} disabled={m === "DRAW" && comparing} onClick={() => { setMode(m); setHover(null); }} title={m === "DRAW" ? "Drag on the chart to draw a trendline" : "Crosshair"}>{m}</button>)}
          {lines.length > 0 && <button onClick={() => saveLines([])} title="Remove this security's trendlines">CLR {lines.length}</button>}
        </div>
        <select className="field" value={compare?.ticker ?? ""} onChange={(e) => setCompare(e.target.value ? resolve(e.target.value) ?? null : null)} aria-label="Compare with"
          style={compare ? { background: "var(--warn)", color: "var(--canvas)", fontWeight: 700 } : undefined}>
          <option value="">VS…</option>
          {COMPARE.filter((t) => t !== i.ticker).map((t) => <option key={t} value={t}>VS {t}</option>)}
        </select>
        <button className="key fn" onClick={savePNG} disabled={!candles || failed} aria-label="Save chart as image">PNG</button>
        <span className="spacer" />
        {h && <span className="mono dim" style={{ fontSize: 11 }}>{new Date(h.time).toLocaleDateString("en-US", { month: "short", day: "numeric", year: range === "5Y" || range === "1Y" ? "numeric" : undefined })} {["1D", "5D", "1M"].includes(range) ? clock(h.time).slice(0, 5) : ""} · O {price(h.open, i.assetClass)} H {price(h.high, i.assetClass)} L {price(h.low, i.assetClass)} C <b style={{ color: "var(--text)" }}>{price(h.close, i.assetClass)}</b></span>}
      </div>
      <div ref={box} style={{ flex: 1, minHeight: 160, position: "relative" }}>
        {failed ? <Empty title="Chart unavailable" detail="The data source didn't respond. It retries every minute." /> : !candles ? <Empty title="Loading chart…" /> :
          <canvas ref={canvas} role="img" aria-label={`${i.ticker} price chart, ${range}${comparing ? `, compared with ${compare!.ticker}` : ""}`} style={{ width: "100%", height: "100%", display: "block", cursor: mode === "DRAW" ? "copy" : "crosshair", touchAction: mode === "DRAW" ? "none" : "pan-y" }}
            onPointerDown={(e) => { if (mode !== "DRAW" || comparing) return; e.currentTarget.setPointerCapture(e.pointerId); const p = at(e); start.current = p; const a = point(p); setDraft({ t1: a.t, p1: a.p, t2: a.t, p2: a.p }); }}
            onPointerMove={(e) => {
              const p = at(e);
              if (mode === "DRAW" && start.current && draft) { const b = point(p); setDraft({ ...draft, t2: b.t, p2: b.p }); return; }
              const n = candles.length, k = Math.round(((p.x - 4) / (e.currentTarget.getBoundingClientRect().width - 64 - 8)) * (n - 1));
              setHover(mode === "CROSS" && k >= 0 && k < n ? k : null);
            }}
            onPointerUp={(e) => {
              const s = start.current, p = at(e);
              if (mode === "DRAW" && s && draft && Math.hypot(p.x - s.x, p.y - s.y) > 12) saveLines([...lines, draft]);
              start.current = null; setDraft(null);
            }}
            onPointerLeave={(e) => { if (e.pointerType === "mouse") { setHover(null); start.current = null; setDraft(null); } }}
            onPointerCancel={() => { start.current = null; setDraft(null); }} />}
      </div>
    </div>
  );
}

interface DrawOptions { studies: Record<string, boolean>; hover: number | null; i: Instrument; lineStyle: boolean; compare: (number | null)[]; compareLabel?: string; percent: boolean; lines: TrendLine[]; draft: TrendLine | null }

function css(name: string) { return getComputedStyle(document.documentElement).getPropertyValue(name).trim(); }

/** Plot geometry, shared by drawing and by turning mouse positions into time and price. */
function scaleOf(k: Candle[], size: { w: number; h: number }, studies: Record<string, boolean>, extra: (number | null)[] = []) {
  const axis = 64, rsiH = studies.RSI ? 70 : 0, padT = 8, padB = 18;
  const W = size.w - axis, H = size.h - padT - padB - rsiH;
  const bb = studies.BOLL ? bollinger(k.map((x) => x.close)) : [];
  let lo = Math.min(...k.map((x) => x.low)), hi = Math.max(...k.map((x) => x.high));
  for (const b of bb) if (b) { lo = Math.min(lo, b.lower); hi = Math.max(hi, b.upper); }
  for (const v of extra) if (v != null) { lo = Math.min(lo, v); hi = Math.max(hi, v); }
  const pad = (hi - lo) * 0.06 || Math.abs(hi) * 0.01 || 1; lo -= pad; hi += pad;
  const n = Math.max(k.length - 1, 1);
  const x = (idx: number) => (idx / n) * (W - 8) + 4;
  const y = (v: number) => padT + (1 - (v - lo) / (hi - lo)) * H;
  const step = k.length > 1 ? (k[k.length - 1].time - k[0].time) / n : 60_000;
  /** Fractional bar index of a time (interpolated between bars, extrapolated outside them). */
  const indexOf = (t: number) => {
    if (!k.length) return 0;
    if (t <= k[0].time) return (t - k[0].time) / step;
    if (t >= k[k.length - 1].time) return n + (t - k[k.length - 1].time) / step;
    let lo2 = 0, hi2 = k.length - 1;
    while (hi2 - lo2 > 1) { const m = (lo2 + hi2) >> 1; if (k[m].time <= t) lo2 = m; else hi2 = m; }
    return lo2 + (t - k[lo2].time) / Math.max(k[hi2].time - k[lo2].time, 1);
  };
  const timeAt = (px: number) => {
    const f = ((px - 4) / (W - 8)) * n;
    if (!k.length) return 0;
    if (f <= 0) return k[0].time + f * step;
    if (f >= n) return k[k.length - 1].time + (f - n) * step;
    const a = Math.floor(f);
    return k[a].time + (f - a) * (k[a + 1].time - k[a].time);
  };
  const priceAt = (py: number) => lo + (1 - (py - padT) / H) * (hi - lo);
  return { axis, rsiH, padT, padB, W, H, lo, hi, x, y, bb, indexOf, timeAt, priceAt };
}

function draw(c: HTMLCanvasElement | null, k: Candle[], size: { w: number; h: number }, o: DrawOptions) {
  if (!c || k.length < 2) return;
  const dpr = window.devicePixelRatio || 1;
  c.width = size.w * dpr; c.height = size.h * dpr;
  const g = c.getContext("2d")!;
  g.scale(dpr, dpr);
  g.clearRect(0, 0, size.w, size.h);
  const { axis, rsiH, padT, padB, W, H, lo, hi, x, y, bb, indexOf } = scaleOf(k, size, o.studies, o.compare);
  const closes = k.map((v) => v.close);
  const label = (v: number) => (o.percent ? `${v >= 0 ? "+" : ""}${v.toFixed(2)}%` : price(v, o.i.assetClass));
  const up = css("--up"), down = css("--down"), rule = css("--rule"), dim = css("--dim"), accent = css("--accent"), warn = css("--warn"), text = css("--text");
  g.font = `10px ${css("--mono")}`;
  g.strokeStyle = rule; g.fillStyle = dim; g.lineWidth = 1;
  for (let t = 0; t <= 4; t++) {
    const v = lo + ((hi - lo) * t) / 4, yy = y(v);
    g.beginPath(); g.moveTo(0, yy); g.lineTo(W, yy); g.stroke();
    g.fillText(label(v), W + 6, yy + 3);
  }
  const line = (vals: (number | null)[], color: string, width = 1.2) => {
    g.strokeStyle = color; g.lineWidth = width; g.beginPath();
    let pen = false;
    vals.forEach((v, n) => { if (v == null) { pen = false; return; } if (!pen) { g.moveTo(x(n), y(v)); pen = true; } else g.lineTo(x(n), y(v)); });
    g.stroke(); g.lineWidth = 1;
  };
  if (o.lineStyle) line(closes, accent, 1.6);
  else {
    const bw = Math.max(1, Math.min(8, (W / k.length) * 0.65));
    k.forEach((c2, n) => {
      const col = c2.close >= c2.open ? up : down;
      g.strokeStyle = col; g.fillStyle = col;
      g.beginPath(); g.moveTo(x(n), y(c2.high)); g.lineTo(x(n), y(c2.low)); g.stroke();
      const top = y(Math.max(c2.open, c2.close)), hgt = Math.max(1, Math.abs(y(c2.open) - y(c2.close)));
      g.fillRect(x(n) - bw / 2, top, bw, hgt);
    });
  }
  // While comparing, only the two rebased lines are drawn so the comparison (in the warn colour) is unambiguous.
  if (o.studies.SMA && !o.percent) { line(sma(closes, 20), accent); line(sma(closes, 50), warn); }
  if (o.studies.BOLL && !o.percent) { line(bb.map((b) => b?.upper ?? null), dim); line(bb.map((b) => b?.lower ?? null), dim); }
  if (o.studies.VWAP && !o.percent) line(vwap(k), "#B78CFF");
  const tag = (v: number, bg: string, txt: string) => { g.fillStyle = bg; g.fillRect(W + 2, y(v) - 8, axis - 4, 16); g.fillStyle = css("--canvas"); g.fillText(txt, W + 6, y(v) + 3); };
  // Comparison series, rebased like the main one.
  if (o.compare.length) {
    line(o.compare, warn, 1.4);
    const lastC = [...o.compare].reverse().find((v): v is number => v != null);
    if (lastC != null && o.compareLabel) { g.fillStyle = warn; g.fillText(`${o.compareLabel} ${label(lastC)}`, 6, padT + 12); }
  }
  const last = closes[closes.length - 1];
  tag(last, last >= k[0].open ? up : down, label(last));
  // Trendlines, anchored in time and price.
  [...o.lines, ...(o.draft ? [o.draft] : [])].forEach((l, n) => {
    const isDraft = !!o.draft && n === o.lines.length;
    const a = { x: x(indexOf(l.t1)), y: y(l.p1) }, b = { x: x(indexOf(l.t2)), y: y(l.p2) };
    g.save(); g.beginPath(); g.rect(0, 0, W, padT + H); g.clip();
    g.strokeStyle = text; g.globalAlpha = isDraft ? 0.6 : 0.9; g.lineWidth = 1.3; g.setLineDash(isDraft ? [4, 3] : []);
    g.beginPath(); g.moveTo(a.x, a.y); g.lineTo(b.x, b.y); g.stroke();
    g.globalAlpha = 1; g.fillStyle = accent;
    for (const p of [a, b]) { g.beginPath(); g.arc(p.x, p.y, 2.5, 0, Math.PI * 2); g.fill(); }
    g.restore();
  });
  if (o.studies.RSI) {
    const r = rsi(closes), top = padT + H + 10, rh = rsiH - 14;
    const ry = (v: number) => top + (1 - v / 100) * rh;
    g.strokeStyle = rule; for (const v of [30, 70]) { g.beginPath(); g.moveTo(0, ry(v)); g.lineTo(W, ry(v)); g.stroke(); }
    g.strokeStyle = accent; g.beginPath(); let s = false;
    r.forEach((v, n) => { if (v == null) return; if (!s) { g.moveTo(x(n), ry(v)); s = true; } else g.lineTo(x(n), ry(v)); }); g.stroke();
    const lv = r[r.length - 1]; g.fillStyle = dim; g.fillText(`RSI 14  ${lv != null ? lv.toFixed(1) : ""}`, 4, top + 9);
  }
  if (o.hover !== null && k[o.hover]) {
    g.strokeStyle = dim; g.setLineDash([3, 3]);
    g.beginPath(); g.moveTo(x(o.hover), padT); g.lineTo(x(o.hover), size.h - padB); g.stroke(); g.setLineDash([]);
  }
}
