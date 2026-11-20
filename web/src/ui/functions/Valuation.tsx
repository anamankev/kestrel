import type { Instrument } from "../../core/instrument";
import { compact } from "../../core/format";
import { csv, csvNum } from "../../core/quant";
import { median, pickPeers, premium, rvRow, type RVRow } from "../../core/valuation";
import { resolve } from "../../core/universe";
import { cik, industry, industryMembers, revenueFor, screen, sharesOutstanding } from "../../data/research";
import { spark } from "../../data/relay";
import { workspace } from "../../data/workspace";
import { Empty, Section, Tile } from "../components";
import { ExportCSV } from "../charts";
import { useAsync } from "../useAsync";

const x = (v?: number, d = 1) => (v == null || !Number.isFinite(v) ? "—" : `${v.toFixed(d)}x`);
const pc = (v?: number, d = 1) => (v == null || !Number.isFinite(v) ? "—" : `${v > 0 ? "+" : ""}${(v * 100).toFixed(d)}%`);
const tint = (v?: number) => (v == null || v === 0 ? "" : v > 0 ? "up" : "down");

const COLS: [keyof RVRow, string, (v?: number) => string][] = [
  ["marketCap", "MKT CAP", (v) => (v == null ? "—" : `$${compact(v)}`)], ["pe", "P/E", (v) => x(v)], ["ps", "P/S", (v) => x(v)], ["pb", "P/B", (v) => x(v)],
  ["revenue", "REVENUE", (v) => (v == null ? "—" : compact(v))], ["growth", "REV GROWTH", (v) => pc(v)], ["margin", "NET MARGIN", (v) => pc(v)],
  ["roe", "ROE", (v) => pc(v)], ["leverage", "LIAB/ASSETS", (v) => pc(v, 0).replace("+", "")],
];

/** RV: the company against same-industry peers (SEC SIC code), sized by revenue, valued at delayed prices. */
export function RelativeValuation({ i, panel }: { i: Instrument; panel: number }) {
  const s = useAsync(async () => {
    if (i.assetClass !== "EQUITY") return { kind: "na" as const };
    const c = await cik(i);
    if (!c) return { kind: "nosec" as const };
    const [ind, sc, shares] = await Promise.all([industry(c), screen(), sharesOutstanding()]);
    const target = sc.rows.find((r) => r.cik === c);
    if (!target || !ind.sic) return { kind: "nodata" as const, year: sc.year };
    let members = await industryMembers(ind.sic), group = false;
    let peers = pickPeers(target, sc.rows, new Set(members.map((m) => m.cik)), 12);
    // Exact codes can be narrow (HP files under 3570, Apple and Dell under 3571): widen to the 3-digit group.
    if (peers.length < 5 && /^\d{4}$/.test(ind.sic)) {
      const siblings = await Promise.all(Array.from({ length: 10 }, (_, k) => `${ind.sic.slice(0, 3)}${k}`).map((c) => industryMembers(c).catch(() => [])));
      members = siblings.flat(); group = true;
      peers = pickPeers(target, sc.rows, new Set(members.map((m) => m.cik)), 12);
    }
    const prior = await revenueFor(sc.year - 1);
    const list = [target, ...peers];
    const quotes = await spark(list.map((r) => resolve(r.ticker, "EQUITY")?.symbol ?? r.ticker)).catch(() => new Map());
    const rows = list.map((r, k) => {
      const sym = resolve(r.ticker, "EQUITY")?.symbol ?? r.ticker;
      return rvRow(r, k === 0, quotes.get(sym)?.quote.last, shares.get(r.cik), prior.get(r.cik));
    });
    return { kind: "ok" as const, rows, industry: ind, year: sc.year, members: new Set(members.map((m) => m.cik)).size, group };
  }, [i.symbol]);

  const d = s.data;
  if (s.loading) return <Empty title="Finding industry peers in SEC filings…" detail="The first load reads every filer's annual report; later companies are instant." />;
  if (s.error) return <Empty title="SEC request failed" detail={s.error} />;
  if (d?.kind === "na") return <Empty title="RV compares companies" detail="Load a US-listed stock, e.g. AAPL RV." />;
  if (d?.kind === "nosec") return <Empty title={`${i.ticker} doesn't file with the SEC`} detail="RV uses SEC annual reports, so it covers US-listed companies." />;
  if (d?.kind === "nodata" || !d) return <Empty title={`No FY${d?.year ?? ""} annual data for ${i.ticker} yet`} detail="It appears once the company's 10-K is in SEC's XBRL frames." />;

  const target = d.rows[0], peers = d.rows.slice(1);
  const med = Object.fromEntries(COLS.map(([k]) => [k, median(peers.map((r) => r[k] as number | undefined))])) as Partial<Record<keyof RVRow, number>>;
  const open = (r: RVRow, fn: "DES" | "FA") => { const inst = resolve(r.ticker, "EQUITY"); if (inst) workspace.load({ fn, instrument: inst }, panel); };
  return (
    <div>
      <div className="toolbar">
        <span className="mono label" style={{ fontSize: 10, fontWeight: 700 }}>SIC {d.industry.sic} · {d.industry.name.toUpperCase()}{d.group ? ` · WIDENED TO ${d.industry.sic.slice(0, 3)}x` : ""}</span>
        <span className="spacer" />
        <ExportCSV name={`${i.ticker}-relative-valuation.csv`} build={() => csv(["Ticker", "Company", "Price", "Market cap", "P/E", "P/S", "P/B", "Revenue", "Revenue growth", "Net margin", "ROE", "Liabilities/assets"],
          d.rows.map((r) => [r.ticker, r.name, csvNum(r.price), csvNum(r.marketCap, 0), csvNum(r.pe), csvNum(r.ps), csvNum(r.pb), csvNum(r.revenue, 0), csvNum(r.growth), csvNum(r.margin), csvNum(r.roe), csvNum(r.leverage)]))} />
      </div>
      <div className="tiles">
        <Tile k="P/E VS PEERS" v={pc(premium(target.pe, med.pe), 0)} s={`${x(target.pe)} VS MEDIAN ${x(med.pe)}`} />
        <Tile k="P/S VS PEERS" v={pc(premium(target.ps, med.ps), 0)} s={`${x(target.ps)} VS MEDIAN ${x(med.ps)}`} />
        <Tile k="NET MARGIN" v={pc(target.margin)} s={`PEER MEDIAN ${pc(med.margin)}`} className={tint((target.margin ?? 0) - (med.margin ?? 0))} />
        <Tile k="REVENUE GROWTH" v={pc(target.growth)} s={`PEER MEDIAN ${pc(med.growth)}`} className={tint((target.growth ?? 0) - (med.growth ?? 0))} />
      </div>
      <Section title={`${i.ticker} VS ${peers.length} PEERS · FY${d.year} 10-K · CLOSEST IN REVENUE`} right={`${d.members} FILERS IN THIS INDUSTRY`} />
      {peers.length === 0 ? <Empty title="No peers with annual data in this industry" detail="SEC lists no other 10-K filer under this SIC code with complete figures." /> :
        <table className="t">
          <thead><tr><th style={{ textAlign: "left" }}>COMPANY</th>{COLS.map(([k, t]) => <th key={k}>{t}</th>)}</tr></thead>
          <tbody>
            {d.rows.map((r) => (
              <tr key={r.cik} className="click" tabIndex={0} onClick={() => open(r, "FA")} title="Open financials (FA)" style={r.isTarget ? { outline: "1px solid var(--accent-dim)" } : undefined}>
                <td style={{ textAlign: "left" }}><b className="accent">{r.ticker}</b> <span style={{ fontFamily: "var(--ui)", fontSize: 11 }}>{r.name.slice(0, 28)}</span>{r.isTarget && <span className="badge" style={{ marginLeft: 6, background: "var(--accent)", color: "var(--canvas)" }}>TARGET</span>}</td>
                {COLS.map(([k, , f]) => <td key={k}>{f(r[k] as number | undefined)}</td>)}
              </tr>
            ))}
            <tr><td style={{ textAlign: "left" }} className="label"><b>PEER MEDIAN</b></td>{COLS.map(([k, , f]) => <td key={k} className="label">{f(med[k])}</td>)}</tr>
          </tbody>
        </table>}
      <p className="faint" style={{ fontSize: 10, padding: 8 }}>
        Peers: other 10-K filers under the same SEC SIC industry code (or its 3-digit group when the code has fewer than 5), closest in revenue. Market cap = delayed price × shares outstanding from the latest
        SEC filing. P/E is blank for losses. Figures are from each company's FY{d.year} 10-K; click a row for its financials.
      </p>
    </div>
  );
}
