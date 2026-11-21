import { useEffect } from "react";
import { SOURCES } from "../../core/health";
import { health } from "../../data/health";
import { relayFetch } from "../../data/relay";
import { useStore } from "../../data/store";
import { Section } from "../components";

const ago = (t: number) => { const s = Math.round((Date.now() - t) / 1000); return s < 60 ? `${s}s ago` : s < 3600 ? `${Math.round(s / 60)}m ago` : `${Math.round(s / 3600)}h ago`; };

/** DATA: whether each source is answering, how fast, and what depends on it. */
export function DataSources() {
  useStore(health);
  useEffect(() => {
    const stale = SOURCES.some((s) => { const r = health.results.get(s.id); return !r || Date.now() - r.at > 300_000; });
    if (stale) void health.checkAll((p) => relayFetch(p));
  }, []);
  const down = SOURCES.filter((s) => health.results.get(s.id)?.status === "DOWN").length;
  return (
    <div>
      <div className="toolbar">
        <span className="label" style={{ font: "700 10px var(--mono)" }}>
          {health.checking ? "CHECKING EVERY SOURCE…" : down ? `${down} SOURCE${down > 1 ? "S" : ""} DOWN` : "ALL CHECKED SOURCES ANSWERING"}
        </span>
        <span className="spacer" />
        <button className="key fn" disabled={health.checking} onClick={() => void health.checkAll((p) => relayFetch(p))}>CHECK ALL</button>
      </div>
      <Section title="DATA SOURCES" right="FREE PUBLIC SOURCES · PRICES DELAYED EXCEPT LIVE CRYPTO" />
      <table className="t">
        <thead><tr><th style={{ textAlign: "left" }}>SOURCE</th><th style={{ textAlign: "left" }}>POWERS</th><th>STATUS</th><th>RESPONSE</th><th>CHECKED</th></tr></thead>
        <tbody>{SOURCES.map((s) => {
          const r = health.results.get(s.id);
          return (
            <tr key={s.id}>
              <td style={{ textAlign: "left" }}><b>{s.name}</b></td>
              <td style={{ textAlign: "left" }} className="dim">{s.powers}</td>
              <td className={r?.status === "OK" ? "up" : r?.status === "DOWN" ? "down" : r ? "warn" : "dim"} title={r?.error}>{r ? r.status : "…"}{r?.error ? ` · ${r.error}` : ""}</td>
              <td>{r && s.probe.kind !== "feed" ? `${r.ms} ms` : "—"}</td>
              <td className="dim">{r ? ago(r.at) : "—"}</td>
            </tr>
          );
        })}</tbody>
      </table>
      <p className="faint" style={{ fontSize: 10, padding: 8 }}>Kestrel also updates this table from every request it makes, so a source that failed for any screen shows here. Over 3 seconds counts as slow. If a source is down, the screens it powers show a short note and retry on their own.</p>
    </div>
  );
}
