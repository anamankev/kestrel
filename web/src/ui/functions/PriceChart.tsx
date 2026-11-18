import { useEffect, useRef, useState } from "react";
import type { Instrument } from "../../core/instrument";
import type { Candle } from "../../core/market";
import { bollinger, rsi, sma, vwap } from "../../core/indicators";
import { price, clock } from "../../core/format";
import { isStreaming } from "../../core/universe";
import { chart } from "../../data/relay";
import { market } from "../../data/market";
import { useStore } from "../../data/store";
import { Empty, Seg } from "../components";

const RANGES = ["1D", "5D", "1M", "6M", "1Y", "5Y"] as const;
type Range = (typeof RANGES)[number];
const YAHOO: Record<Range, [string, string]> = { "1D": ["1d", "5m"], "5D": ["5d", "15m"], "1M": ["1mo", "60m"], "6M": ["6mo", "1d"], "1Y": ["1y", "1d"], "5Y": ["5y", "1wk"] };
const COINBASE: Record<Range, [number, number]> = { "1D": [300, 288], "5D": [3600, 120], "1M": [21600, 124], "6M": [86400, 182], "1Y": [86400, 300], "5Y": [86400, 300] };

async function load(i: Instrument, r: Range, signal: AbortSignal): Promise<Candle[]> {
  if (isStreaming(i)) {
    const [g, n] = COINBASE[r];
    const rows = (await (await fetch(`https://api.exchange.coinbase.com/products/${i.symbol}/candles?granularity=${g}`, { signal })).json()) as number[][];
    return rows.slice(0, n).reverse().map((k) => ({ time: k[0] * 1000, low: k[1], high: k[2], open: k[3], close: k[4], volume: k[5] }));
  }
  return (await chart(i.symbol, ...YAHOO[r], { signal })).candles;
}

export function PriceChart({ i }: { i: Instrument }) {
  useStore(market);
  const [range, setRange] = useState<Range>(() => (localStorage.getItem("gp.range") as Range) ?? "1D");
  const [studies, setStudies] = useState<Record<string, boolean>>(() => { try { return JSON.parse(localStorage.getItem("gp.studies") ?? "") ?? {}; } catch { return { SMA: true }; } });
  const [data, setData] = useState<Candle[] | null>(null);
  const [failed, setFailed] = useState(false);
  const [hover, setHover] = useState<number | null>(null);
  const canvas = useRef<HTMLCanvasElement>(null);
  const box = useRef<HTMLDivElement>(null);
  const [size, setSize] = useState({ w: 600, h: 300 });

  useEffect(() => { localStorage.setItem("gp.range", range); localStorage.setItem("gp.studies", JSON.stringify(studies)); }, [range, studies]);
  useEffect(() => {
    const ctl = new AbortController();
    setData(null); setFailed(false);
    const run = () => load(i, range, ctl.signal).then(setData).catch((e) => { if (!ctl.signal.aborted) { setFailed(true); console.warn(e); } });
    run();
    const t = setInterval(run, isStreaming(i) ? 120_000 : 60_000);
    return () => { ctl.abort(); clearInterval(t); };
  }, [i.symbol, range]);
  useEffect(() => {
    const ro = new ResizeObserver(([e]) => setSize({ w: e.contentRect.width, h: e.contentRect.height }));
    if (box.current) ro.observe(box.current);
    return () => ro.disconnect();
  }, []);

  // Live crypto: fold the streaming price into the latest candle.
  const q = market.quotes.get(i.symbol);
  const candles = data && isStreaming(i) && q && data.length ? [...data.slice(0, -1), { ...data[data.length - 1], close: q.last, high: Math.max(data[data.length - 1].high, q.last), low: Math.min(data[data.length - 1].low, q.last) }] : data;

  useEffect(() => draw(canvas.current, candles ?? [], size, studies, hover, i), [candles, size, studies, hover, i]);

  const h = hover !== null && candles ? candles[hover] : candles?.[candles.length - 1];
  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100%" }}>
      <div className="toolbar">
        <Seg label="Range" value={range} options={RANGES} onChange={setRange} />
        <div className="seg" role="group" aria-label="Studies">
          {["SMA", "BOLL", "VWAP", "RSI"].map((s) => <button key={s} aria-pressed={!!studies[s]} className={studies[s] ? "on" : ""} onClick={() => setStudies({ ...studies, [s]: !studies[s] })}>{s === "SMA" ? "SMA 20/50" : s}</button>)}
        </div>
        <span className="spacer" />
        {h && <span className="mono dim" style={{ fontSize: 11 }}>{new Date(h.time).toLocaleDateString("en-US", { month: "short", day: "numeric", year: range === "5Y" || range === "1Y" ? "numeric" : undefined })} {["1D", "5D", "1M"].includes(range) ? clock(h.time).slice(0, 5) : ""} · O {price(h.open, i.assetClass)} H {price(h.high, i.assetClass)} L {price(h.low, i.assetClass)} C <b style={{ color: "var(--text)" }}>{price(h.close, i.assetClass)}</b></span>}
      </div>
      <div ref={box} style={{ flex: 1, minHeight: 160, position: "relative" }}>
        {failed ? <Empty title="Chart unavailable" detail="The data source didn't respond. It retries every minute." /> : !candles ? <Empty title="Loading chart…" /> :
          <canvas ref={canvas} role="img" aria-label={`${i.ticker} price chart, ${range}`} style={{ width: "100%", height: "100%", display: "block", cursor: "crosshair" }}
            onMouseMove={(e) => { const r = e.currentTarget.getBoundingClientRect(); const n = candles.length; const k = Math.round(((e.clientX - r.left) / (r.width - 64)) * (n - 1)); setHover(k >= 0 && k < n ? k : null); }}
            onMouseLeave={() => setHover(null)} />}
      </div>
    </div>
  );
}

function css(name: string) { return getComputedStyle(document.documentElement).getPropertyValue(name).trim(); }

function draw(c: HTMLCanvasElement | null, k: Candle[], size: { w: number; h: number }, studies: Record<string, boolean>, hover: number | null, i: Instrument) {
  if (!c || k.length < 2) return;
  const dpr = window.devicePixelRatio || 1;
  c.width = size.w * dpr; c.height = size.h * dpr;
  const g = c.getContext("2d")!;
  g.scale(dpr, dpr);
  g.clearRect(0, 0, size.w, size.h);
  const axis = 64, rsiH = studies.RSI ? 70 : 0, padT = 8, padB = 18;
  const W = size.w - axis, H = size.h - padT - padB - rsiH;
  const closes = k.map((x) => x.close);
  const bb = studies.BOLL ? bollinger(closes) : [];
  let lo = Math.min(...k.map((x) => x.low)), hi = Math.max(...k.map((x) => x.high));
  for (const b of bb) if (b) { lo = Math.min(lo, b.lower); hi = Math.max(hi, b.upper); }
  const pad = (hi - lo) * 0.06 || hi * 0.01; lo -= pad; hi += pad;
  const x = (n: number) => (n / (k.length - 1)) * (W - 8) + 4;
  const y = (v: number) => padT + (1 - (v - lo) / (hi - lo)) * H;
  const up = css("--up"), down = css("--down"), rule = css("--rule"), dim = css("--dim"), accent = css("--accent"), warn = css("--warn");
  g.font = `10px ${css("--mono")}`;
  // grid + axis labels
  g.strokeStyle = rule; g.fillStyle = dim; g.lineWidth = 1;
  for (let t = 0; t <= 4; t++) {
    const v = lo + ((hi - lo) * t) / 4, yy = y(v);
    g.beginPath(); g.moveTo(0, yy); g.lineTo(W, yy); g.stroke();
    g.fillText(price(v, i.assetClass), W + 6, yy + 3);
  }
  // candles
  const bw = Math.max(1, Math.min(8, (W / k.length) * 0.65));
  k.forEach((c2, n) => {
    const col = c2.close >= c2.open ? up : down;
    g.strokeStyle = col; g.fillStyle = col;
    g.beginPath(); g.moveTo(x(n), y(c2.high)); g.lineTo(x(n), y(c2.low)); g.stroke();
    const top = y(Math.max(c2.open, c2.close)), hgt = Math.max(1, Math.abs(y(c2.open) - y(c2.close)));
    g.fillRect(x(n) - bw / 2, top, bw, hgt);
  });
  const line = (vals: (number | null)[], color: string, width = 1.2) => {
    g.strokeStyle = color; g.lineWidth = width; g.beginPath();
    let started = false;
    vals.forEach((v, n) => { if (v == null) return; if (!started) { g.moveTo(x(n), y(v)); started = true; } else g.lineTo(x(n), y(v)); });
    g.stroke(); g.lineWidth = 1;
  };
  if (studies.SMA) { line(sma(closes, 20), accent); line(sma(closes, 50), warn); }
  if (studies.BOLL) { line(bb.map((b) => b?.upper ?? null), dim); line(bb.map((b) => b?.lower ?? null), dim); }
  if (studies.VWAP) line(vwap(k), "#B78CFF");
  // last price tag
  const last = closes[closes.length - 1];
  g.fillStyle = last >= k[0].open ? up : down;
  g.fillRect(W + 2, y(last) - 8, axis - 4, 16);
  g.fillStyle = css("--canvas"); g.fillText(price(last, i.assetClass), W + 6, y(last) + 3);
  // RSI pane
  if (studies.RSI) {
    const r = rsi(closes), top = padT + H + 10, rh = rsiH - 14;
    const ry = (v: number) => top + (1 - v / 100) * rh;
    g.strokeStyle = rule; for (const v of [30, 70]) { g.beginPath(); g.moveTo(0, ry(v)); g.lineTo(W, ry(v)); g.stroke(); }
    g.strokeStyle = accent; g.beginPath(); let s = false;
    r.forEach((v, n) => { if (v == null) return; if (!s) { g.moveTo(x(n), ry(v)); s = true; } else g.lineTo(x(n), ry(v)); }); g.stroke();
    const lv = r[r.length - 1]; g.fillStyle = dim; g.fillText(`RSI 14  ${lv != null ? lv.toFixed(1) : ""}`, 4, top + 9);
  }
  // crosshair
  if (hover !== null && k[hover]) {
    g.strokeStyle = dim; g.setLineDash([3, 3]);
    g.beginPath(); g.moveTo(x(hover), padT); g.lineTo(x(hover), size.h - padB); g.stroke(); g.setLineDash([]);
  }
}
