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

interface Route { upstream: string; ttl: number; ua: "browser" | "sec" }

const RANGES = new Set(["1d", "5d", "1mo", "3mo", "6mo", "1y", "2y", "5y", "10y", "ytd", "max"]);
const INTERVALS = new Set(["1m", "2m", "5m", "15m", "30m", "60m", "1h", "1d", "1wk", "1mo"]);
const FRENCH = new Set(["F-F_Research_Data_Factors_daily_CSV.zip", "F-F_Research_Data_5_Factors_2x3_daily_CSV.zip", "F-F_Momentum_Factor_daily_CSV.zip"]);
const SYMBOL = /^[A-Z0-9^=.&-]{1,24}$/;
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
    return null;
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
};

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

export async function handle(req: Request, env: Env, upstreamFetch: Fetcher, cache?: Cache): Promise<Response> {
  const origin = req.headers.get("Origin") ?? "";
  const allowed = env.ALLOWED_ORIGINS.split(",").map((s) => s.trim()).filter(Boolean);
  const cors: Record<string, string> = allowed.includes(origin)
    ? { "Access-Control-Allow-Origin": origin, "Vary": "Origin", "Access-Control-Allow-Methods": "GET, OPTIONS", "Access-Control-Max-Age": "86400" }
    : {};
  if (!cors["Access-Control-Allow-Origin"]) return json(403, { error: "origin not allowed" }, {});
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: { ...SECURITY_HEADERS, ...cors } });
  if (req.method !== "GET") return json(405, { error: "method not allowed" }, cors);
  if (!allow(req.headers.get("CF-Connecting-IP") ?? "local")) return json(429, { error: "too many requests" }, cors);

  const url = new URL(req.url);
  const r = route(url);
  if (!r) return json(404, { error: "unknown or invalid request" }, cors);
  if (r.ua === "sec" && !env.SEC_CONTACT) return json(503, { error: "SEC contact not configured" }, cors);

  const key = new Request(r.upstream);
  const hit = await cache?.match(key);
  if (hit) return withHeaders(hit, cors, "HIT");

  const ua = r.ua === "sec" ? `Kestrel/1.0 (${env.SEC_CONTACT})` : "Mozilla/5.0 (compatible; Kestrel relay)";
  let up: Response;
  try {
    up = await upstreamFetch(r.upstream, { headers: { "User-Agent": ua, "Accept": "*/*" } });
  } catch {
    return json(502, { error: "upstream unreachable" }, cors);
  }
  if (!up.ok) return json(up.status === 404 ? 404 : 502, { error: `upstream ${up.status}` }, cors);
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
