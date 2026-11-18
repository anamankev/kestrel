import { useEffect, useState } from "react";
import type { Instrument } from "../../core/instrument";
import type { NewsItem } from "../../core/market";
import { companyNews, matches, SOURCES, topNews } from "../../data/news";
import { Empty, Section } from "../components";

const ago = (t: number) => { const s = Math.max(0, (Date.now() - t) / 1000); return s < 3600 ? `${Math.floor(s / 60)}m` : s < 86400 ? `${Math.floor(s / 3600)}h` : `${Math.floor(s / 86400)}d`; };

export function News({ i }: { i?: Instrument }) {
  const [items, setItems] = useState<NewsItem[] | null>(null);
  const [failed, setFailed] = useState(false);
  const [q, setQ] = useState("");
  const [source, setSource] = useState("ALL");
  useEffect(() => {
    const ctl = new AbortController();
    setItems(null); setFailed(false);
    const run = () => (i ? companyNews(i.symbol, ctl.signal) : topNews(ctl.signal)).then(setItems).catch(() => !ctl.signal.aborted && setFailed(true));
    run();
    const t = setInterval(run, 120_000);
    return () => { ctl.abort(); clearInterval(t); };
  }, [i?.symbol]);
  const shown = (items ?? []).filter((n) => (source === "ALL" || n.source === source) && matches(n, q));
  return (
    <div>
      <div className="toolbar">
        <input className="field" value={q} onChange={(e) => setQ(e.target.value)} placeholder='Search: "exact phrase" -exclude' aria-label="Search headlines" style={{ flex: "1 1 200px" }} />
        {!i && <select className="field" value={source} onChange={(e) => setSource(e.target.value)} aria-label="Source"><option>ALL</option>{SOURCES.map(([, l]) => <option key={l}>{l}</option>)}</select>}
      </div>
      <Section title={i ? `${i.ticker} NEWS` : "TOP NEWS"} right={items ? `${shown.length} OF ${items.length}` : "LOADING…"} />
      {failed ? <Empty title="News unavailable" detail="The feeds didn't respond; retrying every two minutes." /> :
        items && !shown.length ? <Empty title="No headlines match" /> :
        shown.slice(0, 120).map((n) => (
          <a key={n.link} href={n.link} target="_blank" rel="noopener noreferrer" style={{ display: "flex", gap: 10, padding: "7px 8px", borderBottom: "1px solid var(--rule)", color: "var(--text)", textDecoration: "none" }}>
            <span className="mono faint" style={{ fontSize: 10, width: 30, flex: "none" }}>{n.published ? ago(n.published) : ""}</span>
            <span className="mono label" style={{ fontSize: 9, fontWeight: 700, width: 70, flex: "none", paddingTop: 2 }}>{n.source}</span>
            <span style={{ fontSize: 13 }}>{n.title}</span>
          </a>
        ))}
    </div>
  );
}
