import { useState, type CSSProperties } from "react";
import { INCLUDED, PLANS, perMonth, reference, saving } from "../../core/plans";
import { auth } from "../../data/auth";
import { prefs } from "../../data/prefs";
import { broker } from "../../data/broker";
import { useStore } from "../../data/store";
import { workspace } from "../../data/workspace";
import { Section } from "../components";

const usd = (v: number) => `$${v.toFixed(2)}`;
const row: CSSProperties = { display: "flex", alignItems: "center", gap: 12, padding: "8px 10px", fontSize: 12 };

/** PREF: display, data, subscription, paper account and account settings. */
export function Settings() {
  useStore(prefs); useStore(auth); useStore(broker);
  const me = auth.current;
  const [del, setDel] = useState(false), [pw, setPw] = useState(""), [err, setErr] = useState<string | null>(null), [reset, setReset] = useState(false);
  return (
    <div style={{ maxWidth: 720 }}>
      <Section title="DISPLAY" />
      <label style={row}>
        <input type="checkbox" checked={prefs.cvd} onChange={(e) => prefs.setCVD(e.target.checked)} />
        <span><b>Colour-vision-safe colours</b><br /><span className="dim">Up is blue and down is orange instead of green and red.</span></span>
        <span className="spacer" /><span className="mono"><span className="up">▲ +1.23%</span>{"  "}<span className="down">▼ −0.45%</span></span>
      </label>
      <Section title="DATA" />
      <div style={row}><span className="dim">Crypto streams live from Coinbase. Stocks, ETFs, indices, FX and futures are delayed about 15 minutes and refresh every 45 seconds (every 15 seconds on screen). SEC, BLS, World Bank and Fama-French data load through Kestrel's relay, which identifies itself to the SEC for you: there's nothing to set up.</span></div>
      <Section title="SUBSCRIPTION" />
      <div style={row}>
        <span><b>Web preview</b><br /><span className="dim">Web checkout opens soon. Kestrel Pro is available now in the app for iPad and Mac.</span></span>
        <span className="spacer" /><button className="textbtn" onClick={() => workspace.run("PRO")}>PLANS →</button>
      </div>
      <Section title="PAPER ACCOUNT" />
      <div style={row}>
        <span>{broker.account.openPositions.length} open positions · {broker.account.orders.length} orders</span><span className="spacer" />
        {reset
          ? <><span className="warn mono" style={{ fontSize: 10 }}>Erase all paper orders and reset to $1,000,000?</span><button className="textbtn danger" onClick={() => { broker.reset(); setReset(false); }}>RESET</button><button className="textbtn" onClick={() => setReset(false)}>KEEP</button></>
          : <button className="textbtn danger" onClick={() => setReset(true)}>Reset paper account</button>}
      </div>
      <Section title="ACCOUNT" />
      {me && <div style={row}><span><b>{me.displayName}</b><br /><span className="dim">{me.email}</span></span><span className="spacer" /><button className="textbtn" onClick={() => void auth.signOut()}>Sign out</button></div>}
      <div style={{ ...row, flexWrap: "wrap" }}>
        <span className="dim" style={{ flex: "1 1 300px" }}>Your account lives only in this browser, encrypted with a key your password unlocks. Kestrel has no copy and can't recover it.</span>
        {!del ? <button className="textbtn danger" onClick={() => setDel(true)}>Delete account…</button> : (
          <form style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }} onSubmit={async (e) => { e.preventDefault(); const r = await auth.deleteAccount(pw); setErr(r ?? null); setPw(""); }}>
            <span className="warn" style={{ fontSize: 11 }}>This permanently deletes the account and its data from this browser. It can't be undone.</span>
            <input className="field" type="password" autoComplete="current-password" placeholder="Password to confirm" value={pw} onChange={(e) => setPw(e.target.value)} aria-label="Password" />
            <button className="textbtn danger" type="submit" disabled={!pw || auth.busy}>DELETE</button>
            <button className="textbtn" type="button" onClick={() => { setDel(false); setPw(""); setErr(null); }}>CANCEL</button>
            {err && <span style={{ color: "var(--cancel)", fontSize: 11 }}>{err}</span>}
          </form>
        )}
      </div>
      <p className="faint" style={{ fontSize: 10, padding: 10 }}>No analytics, advertising or tracking. The guide runs in your browser; your questions are never sent anywhere.</p>
    </div>
  );
}

/** PRO: plans and what's included. */
export function Pro() {
  return (
    <div style={{ padding: 10, maxWidth: 720 }}>
      <div className="mono accent" style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1.5 }}>KESTREL PRO</div>
      <p className="dim" style={{ fontSize: 12 }}>You're using the web preview. Web checkout opens soon; subscriptions are available now in the Kestrel app for iPad and Mac.</p>
      <div className="tiles" style={{ margin: "10px 0" }}>
        {PLANS.map((p) => {
          const r = reference(p), s = saving(p);
          return (
            <div key={p.id} className="tile">
              <div className="k">{p.title.toUpperCase()}{s ? ` · SAVE ${Math.round(s * 100)}%` : ""}</div>
              <div className="v">{usd(p.price)} <span className="dim" style={{ fontSize: 11 }}>/ {p.period}</span></div>
              <div className="s">{r ? <><s>{usd(r)}</s> · {usd(perMonth(p))} / MONTH</> : "BILLED MONTHLY"}</div>
            </div>
          );
        })}
      </div>
      <Section title="INCLUDED" />
      <ul style={{ fontSize: 12, lineHeight: 1.8, paddingLeft: 18 }}>{INCLUDED.map((x) => <li key={x}>{x}</li>)}</ul>
      <p className="faint" style={{ fontSize: 10 }}>Paper trading only: Kestrel does not connect a brokerage or move real money.</p>
    </div>
  );
}
