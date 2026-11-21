import { useEffect, useRef, useState } from "react";
import type { Instrument } from "../../core/instrument";
import { brief, facts, INSTRUCTIONS, type BriefSection } from "../../core/brief";
import { resolve } from "../../core/universe";
import { cik, fundamentals } from "../../data/research";
import { companyNews } from "../../data/news";
import { market } from "../../data/market";
import { useStore } from "../../data/store";
import { Empty, Section } from "../components";
import { useAsync } from "../useAsync";

/** Chrome's built-in model (Prompt API, Chrome 148+ on desktop). Not in TypeScript's DOM types yet. */
type Availability = "unavailable" | "downloadable" | "downloading" | "available";
interface LMSession { promptStreaming(input: string, opts?: { signal?: AbortSignal }): ReadableStream<string>; destroy(): void }
interface LMStatic {
  availability(): Promise<Availability>;
  create(opts: { initialPrompts: { role: "system"; content: string }[]; monitor?: (m: EventTarget) => void; signal?: AbortSignal }): Promise<LMSession>;
}
const LM = (): LMStatic | undefined => (globalThis as unknown as { LanguageModel?: LMStatic }).LanguageModel;

const TEN_YEAR = resolve("US10Y");
const SUGGESTIONS = ["What's the bull case and the bear case?", "Explain the valuation in simple terms.", "What should I watch in the next report?"];

/** AI: a written brief from the data, and on-device answers to follow-up questions. */
export function AIAnalyst({ i }: { i: Instrument }) {
  useStore(market);
  useEffect(() => { market.touch(i); if (TEN_YEAR) market.touch(TEN_YEAR); }, [i]);
  const s = useAsync(async () => {
    const c = await cik(i);
    if (!c) return null;
    const [f, news] = await Promise.all([fundamentals(c), companyNews(i.symbol).catch(() => [])]);
    return { f, headlines: news.slice(0, 5).map((n) => n.title) };
  }, [i.symbol]);
  if (i.assetClass !== "EQUITY") return <Empty title="The AI analyst covers companies" detail="Load a US-listed stock, e.g. AAPL AI." />;
  if (s.loading) return <Empty title="Reading filings and headlines…" />;
  if (s.error) return <Empty title="SEC request failed" detail={s.error} />;
  if (!s.data || !s.data.f.years.length) return <Empty title={`No SEC filings for ${i.ticker}`} detail="The analyst works from 10-K filings, so it covers US-listed companies." />;
  const q = market.quotes.get(i.symbol), ten = TEN_YEAR ? market.quotes.get(TEN_YEAR.symbol)?.last : undefined;
  const sections = brief({ name: s.data.f.name, ticker: i.ticker, price: q?.last, changePercent: q?.previousClose ? (q.last / q.previousClose - 1) * 100 : undefined, years: s.data.f.years,
    shares: s.data.f.sharesOutstanding, tenYear: ten != null ? ten / 100 : undefined, headlines: s.data.headlines });
  return (
    <div>
      {sections.map((x) => (
        <div key={x.title}>
          <Section title={x.title} right={x.title === "SNAPSHOT" ? `${i.ticker} · WRITTEN FROM SEC FILINGS, PRICE AND HEADLINES` : undefined} />
          <ul style={{ margin: 0, padding: "6px 10px 8px 26px", fontSize: 13, lineHeight: 1.5 }}>{x.lines.map((l, k) => <li key={k}>{l}</li>)}</ul>
        </div>
      ))}
      <Ask key={i.symbol} sections={sections} />
      <p className="faint" style={{ fontSize: 10, padding: 8 }}>Every sentence in the brief is computed from the numbers shown elsewhere in Kestrel (FA, DCF, CN). It is a study aid, not advice.</p>
    </div>
  );
}

function Ask({ sections }: { sections: BriefSection[] }) {
  const [state, setState] = useState<Availability | "checking">("checking");
  const [progress, setProgress] = useState<number | null>(null);
  const [chat, setChat] = useState<{ q: string; a: string; error?: boolean }[]>([]);
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const session = useRef<LMSession | null>(null);
  const abort = useRef<AbortController | null>(null);

  useEffect(() => {
    const lm = LM();
    if (!lm) { setState("unavailable"); return; }
    lm.availability().then(setState).catch(() => setState("unavailable"));
    return () => { abort.current?.abort(); session.current?.destroy(); };
  }, []);

  const open = async () => {
    if (session.current) return session.current;
    const lm = LM()!;
    session.current = await lm.create({
      initialPrompts: [{ role: "system", content: `${INSTRUCTIONS}\n\nFACTS\n${facts(sections)}` }],
      monitor: (m) => m.addEventListener("downloadprogress", (e) => setProgress((e as unknown as { loaded: number }).loaded)),
    });
    setState("available"); setProgress(null);
    return session.current;
  };

  const ask = async (raw: string) => {
    const q = raw.trim().slice(0, 300);
    if (!q || busy) return;
    setText(""); setBusy(true);
    setChat((c) => [...c, { q, a: "" }]);
    abort.current = new AbortController();
    try {
      const s = await open();
      const reader = s.promptStreaming(q, { signal: abort.current.signal }).getReader();
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        setChat((c) => c.map((m, k) => (k === c.length - 1 ? { ...m, a: m.a + value } : m)));
      }
    } catch (e) {
      setChat((c) => c.map((m, k) => (k === c.length - 1 ? { ...m, a: `Chrome's on-device model couldn't answer. If it is still downloading, try again in a few minutes. (${e instanceof Error ? e.message : "error"})`, error: true } : m)));
    } finally { setBusy(false); }
  };

  return (
    <div>
      <Section title="ASK THE ANALYST" right={state === "available" ? "ON-DEVICE AI · NOTHING LEAVES THIS COMPUTER" : undefined} />
      {state === "checking" ? null : state === "unavailable" ? (
        <p className="dim" style={{ fontSize: 12, padding: "6px 10px" }}>Questions use an AI model that runs on your own computer, so nothing you ask leaves it. This browser doesn't have one: use Chrome 148 or later on a desktop with 16 GB of memory, or the Kestrel app with Apple Intelligence. The brief above works everywhere.</p>
      ) : (
        <div style={{ padding: "6px 10px", display: "grid", gap: 8 }}>
          {state !== "available" && <p className="dim" style={{ fontSize: 12, margin: 0 }}>Chrome downloads its on-device model once (about 2 GB) the first time you ask{progress != null ? `: ${Math.round(progress * 100)}%` : ""}.</p>}
          {chat.map((m, k) => (
            <div key={k} style={{ display: "grid", gap: 4 }}>
              <div style={{ fontSize: 12, fontWeight: 600 }}>{m.q}</div>
              <div className={m.error ? "down" : ""} style={{ fontSize: 13, lineHeight: 1.5, whiteSpace: "pre-wrap" }} aria-live="polite">{m.a || "…"}</div>
            </div>
          ))}
          <div className="follow">{SUGGESTIONS.map((sg) => <button key={sg} disabled={busy} onClick={() => ask(sg)}>{sg}</button>)}</div>
          <form onSubmit={(e) => { e.preventDefault(); void ask(text); }} style={{ display: "flex", gap: 6 }}>
            <input className="field" style={{ flex: 1 }} value={text} maxLength={300} onChange={(e) => setText(e.target.value)} placeholder="Ask about this company…" aria-label="Ask the analyst" disabled={busy} />
            <button className="key fn" type="submit" disabled={busy || !text.trim()}>ASK</button>
          </form>
        </div>
      )}
    </div>
  );
}
