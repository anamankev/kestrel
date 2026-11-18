import { useEffect, useRef, useState } from "react";
import { answer, type Context } from "../core/guide";
import { workspace } from "../data/workspace";
import { KestrelMark } from "./components";

interface Message { id: number; role: "user" | "guide"; text: string; commands: string[]; followUps: string[] }
const WELCOME: Omit<Message, "id"> = {
  role: "guide",
  text: "Hi, I'm the Kestrel guide. Ask me anything in your own words: how a feature works, how to place a paper trade, or what a term means. I'll explain step by step and give you buttons that open the right screen.",
  commands: ["HELP", "AAPL DES", "W"],
  followUps: ["How do I place a trade?", "What can Kestrel do?", "How do panels work?"],
};

/** Floating guide button and chat panel. Runs entirely in the browser: questions are never sent anywhere. */
export function Guide() {
  const [open, setOpen] = useState(false);
  const [messages, setMessages] = useState<Message[]>([{ ...WELCOME, id: 0 }]);
  const [draft, setDraft] = useState("");
  const ctx = useRef<Context>({}), next = useRef(1), list = useRef<HTMLDivElement>(null), input = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    const key = (e: globalThis.KeyboardEvent) => { if ((e.metaKey || e.ctrlKey) && e.key === "/") { e.preventDefault(); setOpen((o) => !o); } };
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  }, []);
  useEffect(() => { if (open) input.current?.focus(); }, [open]);
  useEffect(() => { list.current?.scrollTo({ top: list.current.scrollHeight, behavior: "smooth" }); }, [messages]);

  const ask = (raw: string) => {
    const q = raw.trim().slice(0, 500);
    if (!q) return;
    const r = answer(q, ctx.current);
    setMessages((m) => [...m, { id: next.current++, role: "user", text: q, commands: [], followUps: [] }, { id: next.current++, role: "guide", ...r }]);
  };
  const send = () => { ask(draft); setDraft(""); };
  const reset = () => { setMessages([{ ...WELCOME, id: next.current++ }]); ctx.current = {}; };
  const last = messages[messages.length - 1]?.id;

  return (
    <div className="guide">
      {open && (
        <section className="guide-panel" aria-label="Kestrel guide">
          <header>
            <KestrelMark size={18} /><b>Kestrel Guide</b>
            <span className="badge" title="The guide runs entirely in your browser; your questions never leave it.">IN BROWSER</span>
            <span className="spacer" />
            <button onClick={reset} aria-label="Start over" title="Start over">↺</button>
          </header>
          <div className="guide-list" ref={list} role="log" aria-live="polite" aria-label="Guide conversation">
            {messages.map((m) => (
              <div key={m.id} className={`gm ${m.role === "user" ? "me" : "bot"}`}>
                <div className="bubble">{m.text}</div>
                {m.commands.length > 0 && <div className="chips">{m.commands.map((c) => <button key={c} className="cmdchip" onClick={() => { workspace.run(c); if (window.matchMedia("(max-width: 760px)").matches) setOpen(false); }} aria-label={`Run ${c}`}>{c} ↗</button>)}</div>}
                {m.id === last && m.followUps.length > 0 && <div className="follow">{m.followUps.map((f) => <button key={f} onClick={() => ask(f)}>{f}</button>)}</div>}
              </div>
            ))}
          </div>
          <form className="guide-input" onSubmit={(e) => { e.preventDefault(); send(); }}>
            <textarea ref={input} rows={1} value={draft} placeholder="Ask anything about Kestrel…" aria-label="Ask the guide"
              onChange={(e) => setDraft(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); send(); } if (e.key === "Escape") setOpen(false); }} />
            <button type="submit" disabled={!draft.trim()} aria-label="Send">↑</button>
          </form>
        </section>
      )}
      <button className={`guide-fab ${open ? "open" : ""}`} onClick={() => setOpen(!open)} aria-label={open ? "Close the guide" : "Ask the Kestrel guide"} title="Kestrel guide (Ctrl+/)">
        {open ? "✕" : <><KestrelMark size={26} /><span className="q">?</span></>}
      </button>
    </div>
  );
}
