import { useEffect, useMemo, useRef, useState, type KeyboardEvent } from "react";
import { suggestions as localSuggestions, functionFrom, fn, type Suggestion } from "../core/command";
import { clock } from "../core/format";
import { changePercent } from "../core/market";
import { indices, crypto, commodities, currencies, rates, equities } from "../core/universe";
import { market } from "../data/market";
import { searchSecurities } from "../data/relay";
import { useStore } from "../data/store";
import { workspace, type Layout } from "../data/workspace";
import { auth } from "../data/auth";
import { initials } from "../core/auth";
import { Change, KestrelMark, PanelBoundary } from "./components";
import { FunctionView } from "./functions";

export function Terminal() {
  useStore(workspace);
  const [text, setText] = useState("");
  const input = useRef<HTMLInputElement>(null);
  useEffect(() => { market.start(); input.current?.focus(); }, []);
  useEffect(() => { market.focus = new Set(workspace.symbolsOnScreen); for (const p of workspace.visible) if (p.cmd.instrument) market.touch(p.cmd.instrument); });
  return (
    <div className="terminal">
      <header className="topbar">
        <div className="wordmark"><KestrelMark /> KESTREL</div>
        <CommandBar text={text} setText={setText} inputRef={input} />
        <div className="spacer" />
        <Live />
        <Clocks />
        <AccountChip />
      </header>
      <Tape />
      <main className={`grid l${workspace.maximized !== null ? 1 : workspace.layout}`}>
        {workspace.visible.map((p) => <PanelView key={p.id} id={p.id} />)}
      </main>
      <FunctionKeys setText={setText} focusInput={() => input.current?.focus()} />
    </div>
  );
}

function CommandBar({ text, setText, inputRef }: { text: string; setText: (s: string) => void; inputRef: React.RefObject<HTMLInputElement> }) {
  useStore(workspace);
  const [focused, setFocused] = useState(false);
  const [sel, setSel] = useState(0);
  const [remote, setRemote] = useState<Suggestion[]>([]);
  const local = useMemo(() => (focused ? localSuggestions(text) : []), [text, focused]);
  const list = useMemo(() => {
    const seen = new Set(local.map((s) => s.completion));
    return [...local, ...remote.filter((r) => !seen.has(r.completion))].slice(0, 8);
  }, [local, remote]);

  // Live search across every exchange for a single word that isn't a function.
  useEffect(() => {
    setRemote([]); setSel(0);
    const t = text.trim();
    if (t.length < 2 || t.includes(" ") || functionFrom(t.toUpperCase())) return;
    const ctl = new AbortController();
    const timer = setTimeout(() => {
      searchSecurities(t, 8, ctl.signal).then((hits) => setRemote(hits.map((h) => ({
        completion: h.token, label: `${h.token} ${h.instrument.assetClass}`, detail: [h.instrument.name, h.exchange].filter(Boolean).join(" · "),
      })))).catch(() => {});
    }, 300);
    return () => { clearTimeout(timer); ctl.abort(); };
  }, [text]);

  const submit = (value = text) => {
    const v = sel > 0 && list[sel] ? list[sel].completion : value;
    if (workspace.run(v)) setText("");
    inputRef.current?.focus();
  };
  const onKey = (e: KeyboardEvent) => {
    if (e.key === "ArrowDown" && list.length) { e.preventDefault(); setSel((sel + 1) % list.length); }
    else if (e.key === "ArrowUp" && list.length) { e.preventDefault(); setSel((sel - 1 + list.length) % list.length); }
    else if (e.key === "Tab" && list[sel]) { e.preventDefault(); setText(list[sel].completion + " "); }
    else if (e.key === "Escape") { setText(""); workspace.clear(); }
    else if (e.key === "Enter") { e.preventDefault(); submit(); }
  };
  return (
    <div className={`cmd ${focused ? "focused" : ""}`}>
      <span className="num">{workspace.focused + 1}</span>
      <span className="prompt">&gt;</span>
      <input ref={inputRef} value={text} onChange={(e) => setText(e.target.value.slice(0, 64))} onKeyDown={onKey}
        onFocus={() => setFocused(true)} onBlur={() => setTimeout(() => setFocused(false), 150)}
        placeholder="AAPL GP · BTC DEPTH · WEI · HELP" aria-label="Command line" spellCheck={false} autoCapitalize="characters" autoComplete="off" />
      <button className="go" onClick={() => submit()} aria-label="Run command">GO</button>
      {focused && list.length > 0 && (
        <div className="dropdown" role="listbox">
          {list.map((s, i) => (
            <button key={s.completion} role="option" aria-selected={i === sel} className={i === sel ? "sel" : ""} onMouseDown={(e) => { e.preventDefault(); setText(""); if (workspace.run(s.completion)) setText(""); }}>
              <span className="l">{s.label}</span><span className="d">{s.detail}</span>
            </button>
          ))}
        </div>
      )}
      {!list.length && workspace.error && <div className="cmd-error" role="alert">{workspace.error}</div>}
    </div>
  );
}

function Clocks() {
  const [now, setNow] = useState(Date.now());
  useEffect(() => { const t = setInterval(() => setNow(Date.now()), 1000); return () => clearInterval(t); }, []);
  return (
    <div className="clocks" aria-label="Market clocks">
      {([["NY", "America/New_York"], ["LDN", "Europe/London"], ["TYO", "Asia/Tokyo"]] as const).map(([z, tz]) => (
        <div className="c" key={z}><span className="z">{z}</span><span>{clock(now, tz)}</span></div>
      ))}
    </div>
  );
}

function Live() {
  useStore(market);
  return <div className="live" title="Coinbase live feed"><span className={`dot ${market.live ? "on" : ""}`} /><span className={market.live ? "" : "dim"}>{market.live ? "LIVE" : "OFFLINE"}</span><span className="faint">{market.messagesPerSecond} msg/s</span></div>;
}

const TAPE = [...indices.slice(0, 9), ...equities.slice(0, 6), ...crypto.slice(0, 3), currencies[0], currencies[2], commodities[0], commodities[3], rates[2]];
function Tape() {
  useStore(market);
  const items = TAPE.map((i) => {
    const q = market.quotes.get(i.symbol);
    return <span key={i.symbol}><span className="t">{i.ticker}</span>{q ? q.last.toLocaleString("en-US", { maximumFractionDigits: i.assetClass === "CURNCY" ? 4 : 2, minimumFractionDigits: 2 }) : "—"} <Change value={changePercent(q)} percent /></span>;
  });
  return <div className="tape" aria-hidden="true"><div className="track">{items}{items.map((x, k) => <span key={`b${k}`}>{x}</span>)}</div></div>;
}

function PanelView({ id }: { id: number }) {
  useStore(workspace); useStore(market); // header shows the security's name once details load
  const p = workspace.panels[id];
  const f = fn(p.cmd.fn);
  const i = p.cmd.instrument;
  return (
    <section className={`panel ${workspace.focused === id ? "focused" : ""}`} onMouseDown={() => workspace.focus(id)} aria-label={`Panel ${id + 1}: ${f.title}`}>
      <div className="ph">
        <span className="n">{id + 1}</span>
        {p.history.length > 0 && <button className="icon" onClick={() => workspace.back(id)} aria-label="Back">‹</button>}
        <span className="code">{f.code}</span>
        {i && f.needsSecurity && <><span className="tk">{i.ticker}</span><span className="cls">{i.assetClass}</span></>}
        <span className="title">{i && f.needsSecurity ? market.displayName(i) : f.title}</span>
        <span className="spacer" />
        <button className="icon" onClick={() => workspace.toggleMaximize(id)} aria-label={workspace.maximized === id ? "Restore panel" : "Maximize panel"}>{workspace.maximized === id ? "⤡" : "⤢"}</button>
      </div>
      <div className="pb"><PanelBoundary resetKey={`${p.cmd.fn}|${i?.symbol ?? ""}|${p.cmd.query ?? ""}`}><FunctionView panel={id} cmd={p.cmd} /></PanelBoundary></div>
    </section>
  );
}

const KEYS = ["W", "WEI", "MOST", "HMAP", "FX", "COMD", "RATES", "TOP", "SECF", "HELP"];
function FunctionKeys({ setText, focusInput }: { setText: (s: string) => void; focusInput: () => void }) {
  useStore(workspace);
  return (
    <nav className="keys" aria-label="Function keys">
      <button className="key" onClick={() => workspace.back()}>MENU</button>
      <button className="key help" onClick={() => workspace.run("HELP")}>HELP</button>
      <button className="key cancel" onClick={() => { setText(""); workspace.clear(); focusInput(); }}>CANCEL</button>
      <span style={{ width: 8 }} />
      {KEYS.map((k) => <button key={k} className="key fn" title={fn(k).title} onClick={() => workspace.run(k)}>{k}</button>)}
      <span className="spacer" />
      <div className="layouts" role="radiogroup" aria-label="Panel layout">
        {([1, 2, 4, 6] as Layout[]).map((l) => <button key={l} role="radio" aria-checked={workspace.layout === l} className={workspace.layout === l && workspace.maximized === null ? "on" : ""} onClick={() => workspace.setLayout(l)}>{l}</button>)}
      </div>
    </nav>
  );
}


function AccountChip() {
  useStore(auth);
  const [open, setOpen] = useState(false);
  const me = auth.current;
  if (!me) return null;
  return (
    <div style={{ position: "relative" }}>
      <button className="chip" onClick={() => setOpen(!open)} aria-label={`Account: ${me.displayName}`} aria-expanded={open}>{initials(me)}</button>
      {open && (
        <div className="menu" role="menu">
          <div style={{ padding: "8px 10px" }}><div style={{ fontWeight: 600 }}>{me.displayName}</div><div className="dim" style={{ fontSize: 11 }}>{me.email}</div></div>
          <button role="menuitem" onClick={() => void auth.signOut()}>Sign out</button>
        </div>
      )}
    </div>
  );
}
