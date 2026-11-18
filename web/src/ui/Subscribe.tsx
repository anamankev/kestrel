import { useState } from "react";
import { INCLUDED, PLANS, perMonth, reference, saving, type Plan } from "../core/plans";
import { auth } from "../data/auth";
import { KestrelMark } from "./components";

const usd = (v: number) => `$${v.toFixed(2)}`;
/** Until web payments are wired, the subscribe page lets people into a preview. VITE_WEB_PREVIEW=0 turns that off. */
export const PREVIEW = import.meta.env.VITE_WEB_PREVIEW !== "0";

export function SubscribeView({ onPreview }: { onPreview: () => void }) {
  const [sel, setSel] = useState<Plan["id"]>("annual");
  const plan = PLANS.find((p) => p.id === sel)!;
  return (
    <div className="subscribe">
      <header><div className="wordmark"><KestrelMark /> KESTREL</div><span className="spacer" /><button className="dim" onClick={() => void auth.signOut()}>Sign out</button></header>
      <main>
        <div className="mono accent" style={{ fontSize: 12, fontWeight: 600, letterSpacing: 1.5 }}>KESTREL PRO</div>
        <h1>Subscribe to Kestrel</h1>
        <p className="dim">Kestrel is a subscription. Choose a plan to start; everything below is included.</p>
        <div className="plans" role="radiogroup" aria-label="Plans">
          {PLANS.map((p) => { const r = reference(p), s = saving(p); return (
            <button key={p.id} role="radio" aria-checked={p.id === sel} className={`plan ${p.id === sel ? "on" : ""}`} onClick={() => setSel(p.id)}>
              <span className="row"><b>{p.title}</b>{s && <span className="save">Save {Math.round(s * 100)}%</span>}</span>
              <span className="ref">{r ? <s>{usd(r)}</s> : " "}</span>
              <span className="pr">{usd(p.price)}</span>
              <span className="per">per {p.period}</span>
              <span className="pm">{p.months > 1 ? `${usd(perMonth(p))} / month` : " "}</span>
            </button>
          ); })}
        </div>
        <p className="faint" style={{ fontSize: 11 }}>Crossed-out prices are what the same period costs on the monthly plan.</p>
        <button className="primary" disabled title="Web checkout isn't available yet">Subscribe · {usd(plan.price)} / {plan.period}</button>
        <p className="warn" style={{ fontSize: 12 }}>Web checkout opens soon. Subscriptions are available now in the Kestrel app for iPad and Mac.</p>
        {PREVIEW && <button className="link" onClick={onPreview}>Continue to the web preview →</button>}
        <h3 className="mono label">INCLUDED</h3>
        <ul>{INCLUDED.map((x) => <li key={x}>✓ {x}</li>)}</ul>
        <p className="faint" style={{ fontSize: 10 }}>Paper trading only: Kestrel does not connect a brokerage or move real money.</p>
      </main>
    </div>
  );
}
