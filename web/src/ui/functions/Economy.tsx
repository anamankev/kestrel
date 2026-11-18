import { useMemo, useState } from "react";
import { MACRO, transform, WB_INDICATORS, type Country, type Point, type WBUnit } from "../../core/econ";
import { compact } from "../../core/format";
import { csv, csvNum } from "../../core/quant";
import { rates } from "../../core/universe";
import { bls, countries, nyfed, worldBank } from "../../data/research";
import { market } from "../../data/market";
import { useStore } from "../../data/store";
import { Empty, Section, Seg, Sparkline } from "../components";
import { ExportCSV, LineChart } from "../charts";
import { useAsync } from "../useAsync";

const month = (t: number) => new Date(t).toLocaleDateString("en-US", { month: "short", year: "2-digit", timeZone: "UTC" });
const day = (t: number) => new Date(t).toLocaleDateString("en-US", { month: "short", day: "numeric", timeZone: "UTC" });
const tint = (v?: number | null) => (v == null || v === 0 ? "" : v > 0 ? "up" : "down");

/** ECO: US policy rates, the Treasury curve, inflation and the labour market. */
export function Economy() {
  useStore(market);
  const macro = useAsync(() => bls(), []);
  const effr = useAsync(() => nyfed("effr"), []), sofr = useAsync(() => nyfed("sofr"), []);
  const [open, setOpen] = useState<string | null>(null);
  const t10 = market.quotes.get("^TNX")?.last, t3m = market.quotes.get("^IRX")?.last;
  const spread = t10 != null && t3m != null ? (t10 - t3m) * 100 : null;
  const rate = (title: string, r: typeof effr, target: boolean) => {
    const s = r.data?.series ?? [], last = s[s.length - 1], prior = s[s.length - 2];
    const bp = last && prior ? Math.round((last.value - prior.value) * 100) : null;
    return (
      <div className="tile" style={{ flex: 1 }}>
        <div className="k">{title}</div>
        <div className="v" style={{ fontSize: 20 }}>{last ? `${last.value.toFixed(2)}%` : r.loading ? "…" : "—"} {bp != null && <span className={tint(bp)} style={{ fontSize: 11 }}>{bp > 0 ? "+" : ""}{bp} bp d/d</span>}</div>
        {target && r.data?.targetLow != null && <div className="s warn">TARGET {r.data.targetLow.toFixed(2)}–{r.data.targetHigh?.toFixed(2)}%</div>}
        <Sparkline values={s.map((p) => p.value)} w={220} h={28} />
        <div className="s">{last ? `as of ${day(last.date)}` : r.error ?? ""}</div>
      </div>
    );
  };
  const series = (id: string) => transform(MACRO.find((m) => m.id === id)!, macro.data?.[id] ?? []);
  const fmt = (unit: string, v?: number) => (v == null ? "—" : unit === "K" ? `${v > 0 ? "+" : ""}${v.toFixed(0)}K` : `${v.toFixed(1)}%`);
  return (
    <div>
      <div className="tiles" style={{ display: "flex" }}>{rate("FED FUNDS (EFFR)", effr, true)}{rate("SOFR", sofr, false)}</div>
      <Section title="TREASURY CURVE" right={spread != null ? <span className={spread < 0 ? "down" : "up"}>10Y–3M {spread > 0 ? "+" : ""}{spread.toFixed(0)} bp{spread < 0 ? " · INVERTED" : ""}</span> : undefined} />
      <div style={{ display: "flex", gap: 18, padding: "6px 10px 10px" }} className="mono">
        {rates.map((t) => <div key={t.symbol} style={{ textAlign: "center" }}><div style={{ fontSize: 13, fontWeight: 600 }}>{market.quotes.get(t.symbol)?.last?.toFixed(2) ?? "—"}</div><div className="dim" style={{ fontSize: 9, fontWeight: 700 }}>{t.ticker.replace("US", "")}</div></div>)}
      </div>
      {(["INFLATION", "LABOR"] as const).map((g) => (
        <div key={g}>
          <Section title={g} right="BLS · MONTHLY" />
          <table className="t"><thead><tr><th style={{ textAlign: "left" }}>INDICATOR</th><th>LATEST</th><th>PRIOR</th><th>CHG</th><th>PERIOD</th><th>2Y TREND</th></tr></thead>
            <tbody>{MACRO.filter((m) => m.group === g).map((m) => {
              const s = series(m.id), last = s[s.length - 1], prior = s[s.length - 2], chg = last && prior ? last.value - prior.value : null;
              return [
                <tr key={m.id} className="click" onClick={() => setOpen(open === m.id ? null : m.id)}>
                  <td style={{ textAlign: "left", fontFamily: "var(--ui)" }}>{m.name}</td><td><b>{fmt(m.unit, last?.value)}</b></td><td className="dim">{fmt(m.unit, prior?.value)}</td>
                  <td className={tint(m.id === "LNS14000000" && chg != null ? -chg : chg)}>{chg == null ? "—" : `${chg > 0 ? "+" : ""}${chg.toFixed(m.unit === "K" ? 0 : 1)}${m.unit === "K" ? "K" : " pt"}`}</td>
                  <td className="dim">{last ? month(last.date) : "—"}</td><td style={{ textAlign: "center" }}><Sparkline values={s.slice(-24).map((p) => p.value)} /></td></tr>,
                open === m.id && s.length > 1 ? <tr key={m.id + "-chart"}><td colSpan={6} style={{ padding: 8 }}><LineChart x={s.map((p) => p.date)} series={[{ name: m.name, values: s.map((p) => p.value), width: 2 }]} zero={m.transform === "level" ? undefined : 0} xFormat={month} yLabel={m.unit === "K" ? "Thousands of jobs" : "Percent"} h={180} /></td></tr> : null,
              ];
            })}</tbody></table>
        </div>
      ))}
      <p className="faint mono" style={{ fontSize: 9, padding: 8 }}>{macro.loading ? "Loading BLS…" : macro.error ? `BLS: ${macro.error}` : "Sources: U.S. Bureau of Labor Statistics, Federal Reserve Bank of New York, delayed Treasury yields. Click a row for its full history."}</p>
    </div>
  );
}

const unitFmt = (u: WBUnit, v?: number) => (v == null ? "—" : u === "percent" ? `${v.toFixed(1)}%` : u === "usd" ? `$${compact(v)}` : compact(v));
const latest = (s?: Point[]) => (s && s.length ? s[s.length - 1] : undefined);
/** World Bank points carry the year itself as their date. */
const year = (t: number) => t;

/** Find a country from free text: ISO3 code, exact name, then prefix or substring. */
export function findCountry(list: Country[], q?: string): Country | undefined {
  const t = (q ?? "").trim().toUpperCase();
  if (!t) return undefined;
  const alias: Record<string, string> = { US: "USA", USA: "USA", UK: "GBR", BRITAIN: "GBR", ENGLAND: "GBR", KOREA: "KOR", "SOUTH KOREA": "KOR", RUSSIA: "RUS", CHINA: "CHN", EU: "EMU" };
  return list.find((c) => c.id === (alias[t] ?? t)) ?? list.find((c) => c.name.toUpperCase() === t) ?? list.find((c) => c.name.toUpperCase().startsWith(t)) ?? list.find((c) => c.name.toUpperCase().includes(t));
}

/** ECST: World Bank indicators. Profile one country, or rank every country on one indicator. */
export function WorldEconomy({ query }: { query?: string }) {
  const list = useAsync(() => countries(), []);
  const [mode, setMode] = useState<"COUNTRY PROFILE" | "RANK COUNTRIES">("COUNTRY PROFILE");
  const [picked, setPicked] = useState<string | null>(null);
  const [indicator, setIndicator] = useState(WB_INDICATORS[0].id);
  const [region, setRegion] = useState("ALL");
  const [asc, setAsc] = useState(false);
  const all = list.data ?? [];
  const country = all.find((c) => c.id === picked) ?? findCountry(all, query) ?? all.find((c) => c.id === "USA");
  const profile = useAsync(async () => mode === "COUNTRY PROFILE" ? Promise.all(WB_INDICATORS.map((w) => worldBank(w.id).then((m) => m, () => null))) : null, [mode]);
  const rank = useAsync(() => (mode === "RANK COUNTRIES" ? worldBank(indicator) : Promise.resolve(null)), [mode, indicator]);
  const info = WB_INDICATORS.find((w) => w.id === indicator)!;
  const rows = useMemo(() => {
    if (!rank.data) return [];
    return all.filter((c) => region === "ALL" || c.region === region).flatMap((c) => { const p = latest(rank.data!.get(c.id)); return p ? [{ c, p }] : []; })
      .sort((a, b) => (asc ? a.p.value - b.p.value : b.p.value - a.p.value));
  }, [rank.data, all, region, asc]);
  if (list.loading) return <Empty title="Loading World Bank countries…" />;
  if (list.error) return <Empty title="World Bank unavailable" detail={list.error} />;
  if (query && !findCountry(all, query) && !picked) return <Empty title={`No country matches "${query}"`} detail="Try ECST JAPAN, ECST BRAZIL or ECST DEU." />;
  const regions = [...new Set(all.map((c) => c.region))].filter(Boolean).sort();
  return (
    <div>
      <div className="toolbar">
        <Seg label="Mode" value={mode} options={["COUNTRY PROFILE", "RANK COUNTRIES"] as const} onChange={setMode} />
        {mode === "COUNTRY PROFILE"
          ? <select className="field" value={country?.id} onChange={(e) => setPicked(e.target.value)} aria-label="Country">{all.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}</select>
          : <>
            <select className="field" value={indicator} onChange={(e) => setIndicator(e.target.value)} aria-label="Indicator">{WB_INDICATORS.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}</select>
            <select className="field" value={region} onChange={(e) => setRegion(e.target.value)} aria-label="Region"><option value="ALL">All regions</option>{regions.map((r) => <option key={r}>{r}</option>)}</select>
          </>}
        <span className="spacer" />
        {mode === "COUNTRY PROFILE" && country && profile.data && <ExportCSV name={`${country.id}-profile.csv`} build={() => csv(["Indicator", "Year", "Value"], WB_INDICATORS.flatMap((w, k) => (profile.data![k]?.get(country.id) ?? []).map((p) => [w.name, String(year(p.date)), csvNum(p.value, 6)])))} />}
        {mode === "RANK COUNTRIES" && rows.length > 0 && <ExportCSV name={`${indicator}-ranking.csv`} build={() => csv(["Rank", "Country", "ISO3", "Region", "Year", info.name], rows.map((r, n) => [String(n + 1), r.c.name, r.c.id, r.c.region, String(year(r.p.date)), csvNum(r.p.value, 6)]))} />}
      </div>
      {mode === "COUNTRY PROFILE" && country && <>
        <Section title={`${country.name.toUpperCase()} · ${country.region.toUpperCase()} · ${country.income.toUpperCase()}`} right="WORLD BANK · ANNUAL" />
        {profile.loading ? <Empty title="Loading 11 World Bank indicators…" detail="The first load downloads each series for every country; switching countries is then instant." /> :
          <table className="t"><thead><tr><th style={{ textAlign: "left" }}>INDICATOR</th><th>LATEST</th><th>YEAR</th><th>PRIOR</th><th>15Y</th></tr></thead>
            <tbody>{WB_INDICATORS.map((w, k) => { const s = (profile.data?.[k]?.get(country.id) ?? []).filter((p) => year(p.date) >= new Date().getUTCFullYear() - 16), l = s[s.length - 1], p = s[s.length - 2];
              return <tr key={w.id} className="click" onClick={() => { setIndicator(w.id); setMode("RANK COUNTRIES"); }}>
                <td style={{ textAlign: "left", fontFamily: "var(--ui)" }}>{w.name}</td><td><b>{profile.data?.[k] == null ? "unavailable" : unitFmt(w.unit, l?.value)}</b></td><td className="dim">{l ? year(l.date) : "—"}</td>
                <td className="dim">{unitFmt(w.unit, p?.value)}</td><td style={{ textAlign: "center" }}><Sparkline values={s.map((x) => x.value)} /></td></tr>; })}</tbody></table>}
        <p className="faint" style={{ fontSize: 10, padding: "4px 8px" }}>Click an indicator to rank every country on it.</p>
      </>}
      {mode === "RANK COUNTRIES" && <>
        <Section title={`${info.short} · LATEST AVAILABLE YEAR`} right={rank.loading ? "LOADING…" : rank.error ? "WORLD BANK DIDN'T RESPOND" : `${rows.length} COUNTRIES`} />
        {rank.loading ? <Empty title="Loading…" /> : rank.error ? <Empty title="The World Bank didn't respond for this indicator" detail={rank.error} /> :
          <table className="t"><thead><tr><th>#</th><th style={{ textAlign: "left" }}>COUNTRY</th><th style={{ textAlign: "left" }}>REGION</th><th style={{ cursor: "pointer" }} className="accent" onClick={() => setAsc(!asc)}>VALUE {asc ? "▲" : "▼"}</th><th>YEAR</th></tr></thead>
            <tbody>{rows.map((r, n) => <tr key={r.c.id} className="click" onClick={() => { setPicked(r.c.id); setMode("COUNTRY PROFILE"); }}>
              <td className="faint">{n + 1}</td><td style={{ textAlign: "left", fontFamily: "var(--ui)" }}>{r.c.name}</td><td style={{ textAlign: "left", fontFamily: "var(--ui)" }} className="dim">{r.c.region}</td>
              <td><b>{unitFmt(info.unit, r.p.value)}</b></td><td className="dim">{year(r.p.date)}</td></tr>)}</tbody></table>}
      </>}
      <p className="faint mono" style={{ fontSize: 9, padding: 8 }}>Source: World Bank, World Development Indicators (CC BY 4.0). Annual data; the latest year varies by country and series.</p>
    </div>
  );
}
