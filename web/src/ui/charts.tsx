import { useMemo, useState, type ReactNode } from "react";

/** Small SVG charts for the research screens (lines, scatter with fit, bars), sized to their box. */
const COLORS = ["var(--accent)", "var(--warn)", "#B78CFF", "var(--up)", "#FF7AB6", "#FF9F1C", "#7DD3FC", "var(--text)", "#A3E635", "#F87171", "#94A3B8", "#FDE68A"];
export const seriesColor = (i: number) => COLORS[i % COLORS.length];
const nice = (v: number) => (Math.abs(v) >= 1000 ? v.toLocaleString("en-US", { maximumFractionDigits: 0 }) : Math.abs(v) >= 10 ? v.toFixed(0) : v.toFixed(Math.abs(v) >= 1 ? 1 : 2));

interface Box { w?: number; h?: number }
function scale(lo: number, hi: number, a: number, b: number) { const s = hi - lo || 1; return (v: number) => a + ((v - lo) / s) * (b - a); }
function ticks(lo: number, hi: number, n = 4) { return Array.from({ length: n + 1 }, (_, i) => lo + ((hi - lo) * i) / n); }

export function LineChart({ series, x, w = 640, h = 240, zero, band, xFormat, yLabel, markX, children }: Box & {
  series: { name: string; values: (number | null)[]; color?: string; width?: number; dash?: string }[]; x: number[]; zero?: number;
  band?: { lo: number[]; hi: number[] }; xFormat?: (v: number) => string; yLabel?: string; children?: ReactNode;
  /** A labelled vertical marker, e.g. the forward on a payoff chart. */
  markX?: { value: number; label: string };
}) {
  const [hover, setHover] = useState<number | null>(null);
  const all = series.flatMap((s) => s.values.filter((v): v is number => v != null && Number.isFinite(v))).concat(band ? [...band.lo, ...band.hi] : []).concat(zero != null ? [zero] : []);
  if (!all.length || x.length < 2) return <svg width="100%" height={h} />;
  let lo = Math.min(...all), hi = Math.max(...all);
  const pad = (hi - lo) * 0.06 || Math.abs(hi) * 0.05 || 1; lo -= pad; hi += pad;
  const L = 8, R = w - 56, T = 8, B = h - 22;
  const sx = scale(x[0], x[x.length - 1], L, R), sy = scale(lo, hi, B, T);
  const path = (v: (number | null)[]) => v.map((y, i) => (y == null ? "" : `${i && v[i - 1] != null ? "L" : "M"}${sx(x[i]).toFixed(1)},${sy(y).toFixed(1)}`)).join("");
  return (
    <svg viewBox={`0 0 ${w} ${h}`} width="100%" height={h} role="img" aria-label={yLabel ?? "chart"} style={{ display: "block" }}
      onMouseMove={(e) => { const r = e.currentTarget.getBoundingClientRect(); const px = ((e.clientX - r.left) / r.width) * w; let best = 0; x.forEach((v, i) => { if (Math.abs(sx(v) - px) < Math.abs(sx(x[best]) - px)) best = i; }); setHover(best); }}
      onMouseLeave={() => setHover(null)}>
      {ticks(lo, hi).map((t) => <g key={t}><line x1={L} x2={R} y1={sy(t)} y2={sy(t)} stroke="var(--rule)" /><text x={R + 6} y={sy(t) + 3} fill="var(--dim)" fontSize="10" fontFamily="var(--mono)">{nice(t)}</text></g>)}
      {xFormat && [0, 0.25, 0.5, 0.75, 1].map((f) => { const i = Math.round(f * (x.length - 1)); return <text key={f} x={sx(x[i])} y={h - 6} fill="var(--dim)" fontSize="10" textAnchor={f === 0 ? "start" : f === 1 ? "end" : "middle"} fontFamily="var(--mono)">{xFormat(x[i])}</text>; })}
      {zero != null && <line x1={L} x2={R} y1={sy(zero)} y2={sy(zero)} stroke="var(--faint)" strokeDasharray="3 3" />}
      {band && <path d={`${band.hi.map((v, i) => `${i ? "L" : "M"}${sx(x[i])},${sy(v)}`).join("")}${[...band.lo].reverse().map((v, k) => `L${sx(x[band.lo.length - 1 - k])},${sy(v)}`).join("")}Z`} fill="var(--accent)" opacity="0.12" />}
      {series.map((s, k) => <path key={s.name} d={path(s.values)} fill="none" stroke={s.color ?? seriesColor(k)} strokeWidth={s.width ?? 1.5} strokeDasharray={s.dash} />)}
      {markX && markX.value >= x[0] && markX.value <= x[x.length - 1] && <g><line x1={sx(markX.value)} x2={sx(markX.value)} y1={T} y2={B} stroke="var(--text)" strokeWidth="1" opacity="0.6" /><text x={sx(markX.value) + 4} y={B - 4} fill="var(--warn)" fontSize="9" fontWeight="700" fontFamily="var(--mono)">{markX.label}</text></g>}
      {children}
      {hover != null && <g><line x1={sx(x[hover])} x2={sx(x[hover])} y1={T} y2={B} stroke="var(--dim)" strokeDasharray="3 3" />
        <text x={Math.min(sx(x[hover]) + 6, R - 140)} y={T + 12} fill="var(--text)" fontSize="10" fontFamily="var(--mono)">{xFormat?.(x[hover]) ?? ""} {series.slice(0, 4).map((s) => { const v = s.values[hover]; return v == null ? "" : `${s.name} ${nice(v)}`; }).join("  ")}</text></g>}
    </svg>
  );
}

export function Scatter({ x, y, fit, w = 640, h = 240, xLabel, yLabel }: Box & { x: number[]; y: number[]; fit?: { alpha: number; beta: number }; xLabel: string; yLabel: string }) {
  const pts = useMemo(() => x.map((v, i) => [v, y[i]] as const).filter(([a, b]) => Number.isFinite(a) && Number.isFinite(b)), [x, y]);
  if (pts.length < 3) return <svg width="100%" height={h} />;
  const xs = pts.map((p) => p[0]), ys = pts.map((p) => p[1]);
  const L = 8, R = w - 56, T = 8, B = h - 30;
  const xlo = Math.min(...xs), xhi = Math.max(...xs), ylo = Math.min(...ys), yhi = Math.max(...ys);
  const sx = scale(xlo, xhi, L, R), sy = scale(ylo, yhi, B, T);
  return (
    <svg viewBox={`0 0 ${w} ${h}`} width="100%" height={h} role="img" aria-label={`${yLabel} against ${xLabel}`} style={{ display: "block" }}>
      {ticks(ylo, yhi).map((t) => <g key={t}><line x1={L} x2={R} y1={sy(t)} y2={sy(t)} stroke="var(--rule)" /><text x={R + 6} y={sy(t) + 3} fill="var(--dim)" fontSize="10" fontFamily="var(--mono)">{nice(t)}</text></g>)}
      {pts.map(([a, b], i) => <circle key={i} cx={sx(a)} cy={sy(b)} r="2" fill="var(--accent)" opacity="0.55" />)}
      {fit && <line x1={sx(xlo)} y1={sy(fit.alpha + fit.beta * xlo)} x2={sx(xhi)} y2={sy(fit.alpha + fit.beta * xhi)} stroke="var(--warn)" strokeWidth="1.5" />}
      <text x={(L + R) / 2} y={h - 6} fill="var(--dim)" fontSize="10" textAnchor="middle" fontFamily="var(--mono)">{xLabel}</text>
      <text x={L} y={T + 10} fill="var(--dim)" fontSize="10" fontFamily="var(--mono)">{yLabel}</text>
    </svg>
  );
}

export function Bars({ items, w = 640, h = 180, format = nice, errors }: Box & { items: { label: string; value: number; dim?: boolean }[]; format?: (v: number) => string; errors?: number[] }) {
  if (!items.length) return <svg width="100%" height={h} />;
  const vals = items.flatMap((it, i) => [it.value, ...(errors ? [it.value - errors[i], it.value + errors[i]] : [])]);
  const lo = Math.min(0, ...vals), hi = Math.max(0, ...vals);
  const L = 8, R = w - 8, T = 16, B = h - 20, bw = ((R - L) / items.length) * 0.6;
  const sy = scale(lo, hi, B, T);
  return (
    <svg viewBox={`0 0 ${w} ${h}`} width="100%" height={h} role="img" aria-label="bar chart" style={{ display: "block" }}>
      <line x1={L} x2={R} y1={sy(0)} y2={sy(0)} stroke="var(--faint)" />
      {items.map((it, i) => {
        const cx = L + ((R - L) / items.length) * (i + 0.5), y0 = sy(0), y1 = sy(it.value);
        return <g key={it.label}>
          <rect x={cx - bw / 2} y={Math.min(y0, y1)} width={bw} height={Math.max(1, Math.abs(y1 - y0))} fill={it.value >= 0 ? "var(--accent)" : "var(--warn)"} opacity={it.dim ? 0.35 : 0.8} />
          {errors && <line x1={cx} x2={cx} y1={sy(it.value - errors[i])} y2={sy(it.value + errors[i])} stroke="var(--text)" />}
          <text x={cx} y={Math.min(y0, y1) - 4} fill="var(--dim)" fontSize="9" textAnchor="middle" fontFamily="var(--mono)">{format(it.value)}</text>
          <text x={cx} y={h - 6} fill="var(--dim)" fontSize="10" textAnchor="middle" fontFamily="var(--mono)">{it.label}</text>
        </g>;
      })}
    </svg>
  );
}

/** Triggers a CSV download (Excel, Numbers, Python). */
export function ExportCSV({ name, build }: { name: string; build: () => string }) {
  return <button className="key fn" onClick={() => {
    const url = URL.createObjectURL(new Blob([build()], { type: "text/csv;charset=utf-8" }));
    const a = Object.assign(document.createElement("a"), { href: url, download: name });
    a.click(); setTimeout(() => URL.revokeObjectURL(url), 1000);
  }}>EXPORT CSV</button>;
}
