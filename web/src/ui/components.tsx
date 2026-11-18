import type { ReactNode } from "react";
import type { AssetClass } from "../core/instrument";
import { pct, signed } from "../core/format";

export const KestrelMark = ({ size = 22 }: { size?: number }) => (
  <svg width={size} height={size * 0.84} viewBox="0 0 64 54" aria-hidden="true">
    <defs><linearGradient id="km" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stopColor="#3CD6FF" /><stop offset="1" stopColor="#1E6F88" /></linearGradient></defs>
    <path d="M0 8 L35 30 L64 3 L35 51 Z" fill="url(#km)" />
  </svg>
);

export const Section = ({ title, right }: { title: string; right?: ReactNode }) => (
  <div className="section"><span>{title}</span>{right != null && <span className="r">{right}</span>}</div>
);

export const Empty = ({ title, detail, children }: { title: string; detail?: string; children?: ReactNode }) => (
  <div className="empty"><div className="t">{title}</div>{detail && <div className="s">{detail}</div>}{children}</div>
);

const tint = (v?: number) => (v == null || v === 0 ? "" : v > 0 ? "up" : "down");
export const Change = ({ value, like, cls, percent }: { value?: number; like?: number; cls?: AssetClass; percent?: boolean }) => (
  <span className={`mono ${tint(value)}`}>{percent ? pct(value) : signed(value, like, cls)}</span>
);

export function Sparkline({ values, w = 90, h = 20 }: { values?: number[]; w?: number; h?: number }) {
  if (!values || values.length < 2) return <svg width={w} height={h} />;
  const lo = Math.min(...values), hi = Math.max(...values), span = Math.max(hi - lo, hi * 1e-9, 1e-12);
  const pts = values.map((v, i) => `${((i / (values.length - 1)) * w).toFixed(1)},${(h - ((v - lo) / span) * (h - 2) - 1).toFixed(1)}`).join(" ");
  const up = values[values.length - 1] >= values[0];
  // Shrinks with its container (narrow panels, phones) without distorting the stroke.
  return <svg width={w} height={h} viewBox={`0 0 ${w} ${h}`} preserveAspectRatio="none" style={{ maxWidth: "100%", display: "block" }} aria-hidden="true"><polyline points={pts} fill="none" stroke={up ? "var(--up)" : "var(--down)"} strokeWidth="1.2" vectorEffect="non-scaling-stroke" /></svg>;
}

export const Tile = ({ k, v, s, className }: { k: string; v: ReactNode; s?: string; className?: string }) => (
  <div className="tile"><div className="k">{k}</div><div className={`v ${className ?? ""}`}>{v}</div><div className="s">{s ?? " "}</div></div>
);

export function Seg<T extends string | number>({ value, options, onChange, label }: { value: T; options: readonly T[]; onChange: (v: T) => void; label: string }) {
  return (
    <div className="seg" role="radiogroup" aria-label={label}>
      {options.map((o) => <button key={String(o)} role="radio" aria-checked={o === value} className={o === value ? "on" : ""} onClick={() => onChange(o)}>{o}</button>)}
    </div>
  );
}

import { Component, type ErrorInfo } from "react";

/** Keeps a fault in one panel from blanking the whole terminal. */
export class PanelBoundary extends Component<{ children: ReactNode; resetKey: string }, { failed: boolean }> {
  state = { failed: false };
  static getDerivedStateFromError() { return { failed: true }; }
  componentDidCatch(e: Error, info: ErrorInfo) { console.error("Panel error", e, info.componentStack); }
  componentDidUpdate(prev: { resetKey: string }) { if (prev.resetKey !== this.props.resetKey && this.state.failed) this.setState({ failed: false }); }
  render() {
    return this.state.failed ? <Empty title="This panel hit a problem" detail="Run another command here, or press MENU to go back." /> : this.props.children;
  }
}
