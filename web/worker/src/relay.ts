/**
 * Kestrel relay: forwards a fixed set of read-only market-data requests that browsers can't make
 * directly (no CORS, or a required User-Agent). Not an open proxy: every route, path segment and
 * query value is validated against an allowlist, and only Kestrel's own origins may call it.
 */
export interface Env {
  /** Comma-separated origins allowed to call the relay (the site and local dev). */
  ALLOWED_ORIGINS: string;
  /** Contact email the SEC requires in the User-Agent; a Cloudflare secret, never committed. */
  SEC_CONTACT?: string;
}

type Fetcher = (url: string, init?: RequestInit) => Promise<Response>;

interface Route { upstream: string; ttl: number; ua: "browser" | "sec"; post?: string }

const RANGES = new Set(["1d", "5d", "1mo", "3mo", "6mo", "1y", "2y", "5y", "10y", "ytd", "max"]);
const INTERVALS = new Set(["1m", "2m", "5m", "15m", "30m", "60m", "1h", "1d", "1wk", "1mo"]);
const FRENCH = new Set(["F-F_Research_Data_Factors_daily_CSV.zip", "F-F_Research_Data_5_Factors_2x3_daily_CSV.zip", "F-F_Momentum_Factor_daily_CSV.zip"]);
const SYMBOL = /^[A-Z0-9^=.&-]{1,24}$/;
/** World Bank indicators shown in ECST (bulk ZIP downloads). */
const WB = new Set(["NY.GDP.MKTP.KD.ZG", "NY.GDP.MKTP.CD", "NY.GDP.PCAP.CD", "FP.CPI.TOTL.ZG", "SL.UEM.TOTL.ZS", "BN.CAB.XOKA.GD.ZS", "GC.DOD.TOTL.GD.ZS", "NE.EXP.GNFS.ZS", "BX.KLT.DINV.WD.GD.ZS", "FR.INR.RINR", "SP.POP.TOTL"]);
/** BLS series shown in ECO, fetched in one request. BLS allows ~25 unregistered requests a day per IP,
 * and every visitor shares the relay's IP, so this is cached for 12 hours. */
const BLS_SERIES = ["CUSR0000SA0", "CUSR0000SA0L1E", "WPSFD4", "LNS14000000", "CES0000000001", "CES0500000003", "LNS11300000"];
/** Market news feeds (the same sources as the app). */
const FEEDS: Record<string, string> = {
  cnbc: "https://www.cnbc.com/id/100003114/device/rss/rss.html",
  cnbcfin: "https://www.cnbc.com/id/10000664/device/rss/rss.html",
  marketwatch: "https://feeds.content.dowjones.io/public/rss/mw_topstories",
  coindesk: "https://www.coindesk.com/arc/outboundfeeds/rss/",
};

/** Maps a relay path to its upstream URL, or null if the request isn't allowed. */
export function route(url: URL): Route | null {
  const p = url.pathname.split("/").filter(Boolean);
  const q = url.searchParams;
  if (p[0] === "yahoo" && p[1] === "chart" && p.length === 3) {
    const sym = decodeURIComponent(p[2]).toUpperCase();
    const range = q.get("range") ?? "1d", interval = q.get("interval") ?? "1d", events = q.get("events");
    if (!SYMBOL.test(sym) || !RANGES.has(range) || !INTERVALS.has(interval) || (events !== null && events !== "div,splits")) return null;
    const u = new URL(`https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(sym)}`);
    u.searchParams.set("range", range); u.searchParams.set("interval", interval); u.searchParams.set("includePrePost", "false");
    if (events) u.searchParams.set("events", events);
    return { upstream: u.toString(), ttl: range === "1d" || range === "5d" ? 20 : 900, ua: "browser" };
  }
  if (p[0] === "yahoo" && p[1] === "spark" && p.length === 2) {
    // Batch quotes: up to 20 symbols per request (one request instead of twenty).
    const syms = (q.get("symbols") ?? "").toUpperCase().split(",").filter(Boolean);
    const range = q.get("range") ?? "1d", interval = q.get("interval") ?? "5m";
    if (!syms.length || syms.length > 20 || !syms.every((x) => SYMBOL.test(x)) || !["1d", "5d"].includes(range) || !["5m", "15m"].includes(interval)) return null;
    const u = new URL("https://query1.finance.yahoo.com/v8/finance/spark");
    u.searchParams.set("symbols", syms.join(",")); u.searchParams.set("range", range); u.searchParams.set("interval", interval);
    return { upstream: u.toString(), ttl: 20, ua: "browser" };
  }
  if (p[0] === "yahoo" && p[1] === "search" && p.length === 2) {
    const text = (q.get("q") ?? "").trim();
    const n = Number(q.get("n") ?? "10");
    if (text.length < 1 || text.length > 64 || !Number.isInteger(n) || n < 1 || n > 25) return null;
    const u = new URL("https://query1.finance.yahoo.com/v1/finance/search");
    u.searchParams.set("q", text); u.searchParams.set("quotesCount", String(n)); u.searchParams.set("newsCount", "0"); u.searchParams.set("listsCount", "0");
    return { upstream: u.toString(), ttl: 3600, ua: "browser" };
  }
  if (p[0] === "sec") {
    if (p[1] === "tickers" && p.length === 2) return { upstream: "https://www.sec.gov/files/company_tickers.json", ttl: 86400, ua: "sec" };
    if ((p[1] === "submissions" || p[1] === "facts") && p.length === 3 && /^\d{1,10}$/.test(p[2])) {
      const cik = p[2].padStart(10, "0");
      return p[1] === "submissions"
        ? { upstream: `https://data.sec.gov/submissions/CIK${cik}.json`, ttl: 3600, ua: "sec" }
        : { upstream: `https://data.sec.gov/api/xbrl/companyfacts/CIK${cik}.json`, ttl: 21600, ua: "sec" };
    }
    if (p[1] === "frames" && p.length === 4 && /^[A-Za-z]{2,100}$/.test(p[2]) && /^CY\d{4}(Q4I)?$/.test(p[3])) {
      return { upstream: `https://data.sec.gov/api/xbrl/frames/us-gaap/${p[2]}/USD/${p[3]}.json`, ttl: 86400, ua: "sec" };
    }
    // Every 10-K filer under one SIC industry code (RV peers), 100 per page.
    if (p[1] === "sic" && p.length === 3 && /^\d{4}$/.test(p[2])) {
      const start = Number(q.get("start") ?? "0");
      if (!Number.isInteger(start) || start < 0 || start > 3000 || start % 100 !== 0) return null;
      return { upstream: `https://www.sec.gov/cgi-bin/browse-edgar?action=getcompany&SIC=${p[2]}&type=10-K&dateb=&owner=include&start=${start}&count=100&output=atom`, ttl: 86400, ua: "sec" };
    }
    // Shares outstanding for every filer at one quarter end (market caps).
    if (p[1] === "shares" && p.length === 3 && /^CY\d{4}Q[1-4]I$/.test(p[2])) {
      return { upstream: `https://data.sec.gov/api/xbrl/frames/dei/EntityCommonStockSharesOutstanding/shares/${p[2]}.json`, ttl: 86400, ua: "sec" };
    }
    return null;
  }
  if (p[0] === "wb" && p[1] === "bulk" && p.length === 3 && WB.has(p[2])) {
    return { upstream: `https://api.worldbank.org/v2/en/indicator/${p[2]}?downloadformat=csv`, ttl: 86400, ua: "browser" };
  }
  if (p[0] === "bls" && p.length === 1) {
    return { upstream: "https://api.bls.gov/publicAPI/v1/timeseries/data/", ttl: 43200, ua: "browser", post: JSON.stringify({ seriesid: BLS_SERIES }) };
  }
  if (p[0] === "rss" && p.length === 2) {
    if (p[1] === "company") {
      const sym = (q.get("s") ?? "").toUpperCase();
      if (!SYMBOL.test(sym)) return null;
      return { upstream: `https://feeds.finance.yahoo.com/rss/2.0/headline?s=${encodeURIComponent(sym)}&region=US&lang=en-US`, ttl: 300, ua: "browser" };
    }
    const feed = FEEDS[p[1]];
    return feed ? { upstream: feed, ttl: 300, ua: "browser" } : null;
  }
  // U.S. Treasury daily par yield curve, one CSV per year (GC, YAS).
  if (p[0] === "tsy" && p.length === 2 && /^\d{4}$/.test(p[1])) {
    const y = Number(p[1]), now = new Date().getUTCFullYear();
    if (y < 1990 || y > now) return null;
    return { upstream: `https://home.treasury.gov/resource-center/data-chart-center/interest-rates/daily-treasury-rates.csv/${y}/all?type=daily_treasury_yield_curve&field_tdr_date_value=${y}&page&_format=csv`, ttl: y === now ? 3600 : 86400, ua: "browser" };
  }
  if (p[0] === "french" && p.length === 2 && FRENCH.has(p[1])) {
    return { upstream: `https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/ftp/${p[1]}`, ttl: 86400, ua: "browser" };
  }
  return null;
}

const SECURITY_HEADERS: Record<string, string> = {
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer",
  "Cross-Origin-Resource-Policy": "cross-origin",
  "Strict-Transport-Security": "max-age=31536000; includeSubDomains",
  // Responses are data, never pages: nothing may run or be framed even if an upstream sends HTML.
  "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'; sandbox",
  "X-Frame-Options": "DENY",
};

const EMAIL = /^[^@\s]{1,64}@[^@\s]{1,190}\.[A-Za-z]{2,24}$/;

/** Checks the deployment's configuration; returns a problem, or null when it is safe to serve. */
export function configProblem(env: Env): string | null {
  const origins = (env.ALLOWED_ORIGINS ?? "").split(",").map((s) => s.trim()).filter(Boolean);
  if (!origins.length) return "ALLOWED_ORIGINS is empty";
  for (const o of origins) {
    if (o === "*" || o.includes("*")) return "ALLOWED_ORIGINS may not contain a wildcard";
    let u: URL;
    try { u = new URL(o); } catch { return `ALLOWED_ORIGINS has an invalid origin: ${o}`; }
    if (u.origin !== o) return `ALLOWED_ORIGINS entries must be bare origins: ${o}`;
    if (u.protocol !== "https:" && !["localhost", "127.0.0.1"].includes(u.hostname)) return `ALLOWED_ORIGINS must be https: ${o}`;
  }
  if (env.SEC_CONTACT !== undefined && !EMAIL.test(env.SEC_CONTACT)) return "SEC_CONTACT is not an email address";
  return null;
}

/** Security log line for Workers Logs / `wrangler tail`. The IP is hashed, never stored in clear. */
export type Logger = (event: Record<string, unknown>) => void;
const defaultLog: Logger = (e) => console.warn(JSON.stringify(e));
async function ipTag(ip: string): Promise<string> {
  const d = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`kestrel-relay|${ip}`)));
  return [...d.slice(0, 6)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function json(status: number, body: unknown, cors: Record<string, string>) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", ...SECURITY_HEADERS, ...cors } });
}

/** Best-effort per-IP limit: 120 requests a minute per relay instance. */
const hits = new Map<string, { n: number; reset: number }>();
export function allow(ip: string, now = Date.now(), limit = 120): boolean {
  const h = hits.get(ip);
  if (!h || now > h.reset) { hits.set(ip, { n: 1, reset: now + 60_000 }); if (hits.size > 10_000) hits.clear(); return true; }
  h.n += 1;
  return h.n <= limit;
}

export async function handle(req: Request, env: Env, upstreamFetch: Fetcher, cache?: Cache, log: Logger = defaultLog): Promise<Response> {
  const problem = configProblem(env);
  if (problem) { log({ event: "misconfigured", problem }); return json(500, { error: "relay misconfigured" }, {}); }
  const ip = req.headers.get("CF-Connecting-IP") ?? "local";
  const path = new URL(req.url).pathname.slice(0, 80);
  const warn = async (event: string, extra: Record<string, unknown> = {}) => log({ event, ip: await ipTag(ip), path, ...extra });
  const origin = req.headers.get("Origin") ?? "";
  const allowed = env.ALLOWED_ORIGINS.split(",").map((s) => s.trim()).filter(Boolean);
  const cors: Record<string, string> = allowed.includes(origin)
    ? { "Access-Control-Allow-Origin": origin, "Vary": "Origin", "Access-Control-Allow-Methods": "GET, OPTIONS", "Access-Control-Max-Age": "86400" }
    : {};
  if (!cors["Access-Control-Allow-Origin"]) { await warn("origin_rejected", { origin: origin.slice(0, 80) }); return json(403, { error: "origin not allowed" }, {}); }
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: { ...SECURITY_HEADERS, ...cors } });
  if (req.method !== "GET") { await warn("method_rejected", { method: req.method.slice(0, 10) }); return json(405, { error: "method not allowed" }, cors); }
  if (!allow(ip)) { await warn("rate_limited"); return json(429, { error: "too many requests" }, cors); }

  const url = new URL(req.url);
  const r = route(url);
  if (!r) { await warn("route_rejected", { query: url.search.slice(0, 120) }); return json(404, { error: "unknown or invalid request" }, cors); }
  if (r.ua === "sec" && !env.SEC_CONTACT) return json(503, { error: "SEC contact not configured" }, cors);

  const key = new Request(r.post ? `${r.upstream}#${r.post}` : r.upstream);
  const hit = await cache?.match(key);
  if (hit) return withHeaders(hit, cors, "HIT");

  const ua = r.ua === "sec" ? `Kestrel/1.0 (${env.SEC_CONTACT})` : "Mozilla/5.0 (compatible; Kestrel relay)";
  let up: Response;
  try {
    up = await upstreamFetch(r.upstream, r.post
      ? { method: "POST", body: r.post, headers: { "User-Agent": ua, "Accept": "*/*", "Content-Type": "application/json" } }
      : { headers: { "User-Agent": ua, "Accept": "*/*" } });
  } catch {
    log({ event: "upstream_unreachable", path });
    return json(502, { error: "upstream unreachable" }, cors);
  }
  if (!up.ok) { log({ event: "upstream_error", status: up.status, path }); return json(up.status === 404 ? 404 : 502, { error: `upstream ${up.status}` }, cors); }
  const body = await up.arrayBuffer();
  if (body.byteLength > 25 * 1024 * 1024) return json(502, { error: "upstream response too large" }, cors);
  const res = new Response(body, { status: 200, headers: { "Content-Type": up.headers.get("Content-Type") ?? "application/octet-stream", "Cache-Control": `public, max-age=${r.ttl}` } });
  if (cache) await cache.put(key, res.clone());
  return withHeaders(res, cors, "MISS");
}

function withHeaders(res: Response, cors: Record<string, string>, cacheState: string) {
  const h = new Headers(res.headers);
  for (const [k, v] of Object.entries({ ...SECURITY_HEADERS, ...cors, "X-Kestrel-Cache": cacheState })) h.set(k, v);
  return new Response(res.body, { status: res.status, headers: h });
}
