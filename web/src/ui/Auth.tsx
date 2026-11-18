import { useEffect, useState, type FormEvent } from "react";
import { passwordProblem } from "../core/auth";
import { changePercent } from "../core/market";
import { price } from "../core/format";
import { resolve } from "../core/universe";
import { auth } from "../data/auth";
import { market } from "../data/market";
import { useStore } from "../data/store";
import { Change, KestrelMark } from "./components";

const TILES = ["BTC", "ETH", "SOL", "SPX", "CCMP", "EURUSD"];

export function AuthView() {
  useStore(auth); useStore(market);
  const [mode, setMode] = useState<"signin" | "create">(auth.directory.accounts.length ? "signin" : "create");
  const [name, setName] = useState(""), [email, setEmail] = useState(""), [password, setPassword] = useState(""), [confirm, setConfirm] = useState("");
  const [show, setShow] = useState(false);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => { market.start(); }, []);
  useEffect(() => { setError(null); setPassword(""); setConfirm(""); }, [mode]);
  const problem = mode === "create" && password ? passwordProblem(password, email) : null;
  const can = !auth.busy && !!email && !!password && (mode === "signin" || (!!name && !problem && password === confirm));
  const submit = async (e: FormEvent) => {
    e.preventDefault();
    if (!can) return;
    const err = mode === "signin" ? await auth.signIn(email, password) : await auth.register(name, email, password, confirm);
    setError(err);
    if (err) setPassword(""), setConfirm("");
  };
  return (
    <div className="auth">
      <section className="auth-brand">
        <div className="wordmark" style={{ fontSize: 20 }}><KestrelMark size={28} /> KESTREL</div>
        <h1>Command-line market terminal</h1>
        <p className="dim">Live crypto depth and tape, delayed equities, FX, rates and futures on every exchange, filings, macro, research tools, and a paper book to trade it all.</p>
        <div className="auth-tiles">
          {TILES.map((t) => { const i = resolve(t)!; const q = market.quotes.get(i.symbol); return (
            <div className="tile" key={t}><div className="k">{t}</div><div className="v mono">{price(q?.last, i.assetClass)}</div><div className="s"><Change value={changePercent(q)} percent /></div></div>
          ); })}
        </div>
        <div className="mono accent" style={{ fontSize: 12, display: "flex", gap: 22, flexWrap: "wrap" }}><span>BTC GP &lt;GO&gt;</span><span>AAPL DES &lt;GO&gt;</span><span>SECF TOYOTA &lt;GO&gt;</span><span>WEI &lt;GO&gt;</span></div>
        <p className="faint" style={{ fontSize: 11, marginTop: "auto" }}>Paper trading only. No real money moves, and no brokerage is connected.</p>
      </section>
      <section className="auth-form">
        <div className="tabs" role="tablist">
          <button role="tab" aria-selected={mode === "signin"} className={mode === "signin" ? "on" : ""} onClick={() => setMode("signin")}>Sign in</button>
          <button role="tab" aria-selected={mode === "create"} className={mode === "create" ? "on" : ""} onClick={() => setMode("create")}>Create account</button>
        </div>
        <h2>{mode === "signin" ? "Sign in" : "Create an account"}</h2>
        <form onSubmit={submit}>
          {mode === "create" && <label>Name<input value={name} onChange={(e) => setName(e.target.value)} autoComplete="name" placeholder="Ada Lovelace" maxLength={60} /></label>}
          <label>Email<input type="email" value={email} onChange={(e) => setEmail(e.target.value)} autoComplete="email" placeholder="you@firm.com" maxLength={254} /></label>
          {/* The Show button sits outside the label, so the field is announced as "Password", not "Password Show". */}
          <div className="pw">
            <span><label htmlFor="auth-password">Password</label>
              <button type="button" className="dim" aria-pressed={show} aria-controls="auth-password" aria-label={show ? "Hide password" : "Show password"} onClick={() => setShow(!show)}>{show ? "Hide" : "Show"}</button></span>
            <input id="auth-password" type={show ? "text" : "password"} value={password} onChange={(e) => setPassword(e.target.value)} autoComplete={mode === "signin" ? "current-password" : "new-password"} maxLength={128} aria-describedby={mode === "create" ? "auth-hint" : undefined} />
          </div>
          {mode === "create" && <label>Confirm password<input type={show ? "text" : "password"} value={confirm} onChange={(e) => setConfirm(e.target.value)} autoComplete="new-password" maxLength={128} /></label>}
          {mode === "create" && <div id="auth-hint" aria-live="polite" className={`hint ${password && !problem ? "ok" : ""}`}>{!password ? "At least 10 characters. A phrase works well." : problem ?? (confirm && confirm !== password ? "Passwords don't match" : "Strong enough")}</div>}
          {error && <div className="error" role="alert">{error}</div>}
          <button className="primary" disabled={!can}>{auth.busy ? (mode === "signin" ? "Signing in…" : "Creating account…") : mode === "signin" ? "Sign in" : "Create account"}</button>
        </form>
        <p className="faint" style={{ fontSize: 11 }}>{mode === "signin" ? "Accounts are stored in this browser. Forgotten passwords can't be recovered yet; create a new account." : "Your account lives in this browser: a salted PBKDF2 hash, never the password, and your data encrypted with your own key."}</p>
      </section>
    </div>
  );
}
