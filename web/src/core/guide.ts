/** The guide, answered fully offline: a port of KestrelCore's KestrelGuide, with web wording. Data is generated from Guide.swift. */
import type { Instrument } from "./instrument";
import { all, crypto, equities, instrument, resolve, token } from "./universe";
import { fn, functionFrom } from "./command";
import { topics as rawTopics, howTos as rawHowTos, glossary as rawGlossary, glossaryHome } from "./guide.generated";

export interface Topic { function: string; summary: string; example: string; keywords: string[]; steps: string[] }
export interface HowTo { title: string; keywords: string[]; intro: string; steps: string[]; commands: string[]; followUps: string[] }
export interface Reply { text: string; commands: string[]; followUps: string[] }
export interface Context { security?: Instrument; function?: string }

/** App wording that doesn't fit the browser ("" drops a step). */
const WEB: Record<string, string> = {
  "Tap EXPORT CSV to save or share the table (Files, Mail, AirDrop).": "Click EXPORT CSV to download the table.",
  "Add a contact email once in PREF: the SEC requires every app to identify itself.": "",
  "Needs the SEC contact email in PREF.": "",
  "Needs the SEC contact email in PREF (earnings dates come from SEC filings).": "",
  "Tap a row to load it into the other panels; long-press for more functions or Set alert…": "Click a row to load it into the other panels.",
  "Type a ticker then ALRT, e.g. NVDA ALRT (or long-press any row and choose Set alert…).": "Type a ticker then ALRT, e.g. NVDA ALRT.",
  "Alerts fire once; on iPad they're checked in the background, on Mac from the menu bar.": "Alerts fire once, while Kestrel is open in a browser tab; allow notifications to see them from other tabs.",
  "settings: SEC contact email, colour-vision-safe colours, refresh speed, subscription, iPad ↔ Mac transfer, account": "settings: colour-vision-safe colours, subscription, paper account, transfer between web, iPad and Mac, and your account (sign out or delete)",
  "Sections: SEC EDGAR contact, display, data refresh, subscription, transfer between iPad and Mac, reset, account (sign out).": "Sections: display, data, subscription, paper account reset, transfer between web, iPad and Mac, and account (sign out or delete).",
  "See your plan and renewal date; Manage subscription opens Apple's subscription settings.": "See the plans and everything that's included.",
  "Restore purchases brings back a subscription bought on this Apple ID.": "Web checkout opens soon; subscriptions are available now in the Kestrel app for iPad and Mac.",
  "Type a ticker then ALRT, e.g. NVDA ALRT, or long-press a watchlist row and choose Set alert….": "Type a ticker then ALRT, e.g. NVDA ALRT.",
  "They keep working with the app closed: background refresh on iPad, the menu bar on Mac.": "They're checked while Kestrel is open in a tab; allow browser notifications to see them from other tabs.",
  "⌘/ opens or closes this guide.": "Ctrl+/ (⌘/ on a Mac) opens or closes this guide.",
  "⌘/ opens or closes me; ↺ starts over. I never give investment advice.": "Ctrl+/ (⌘/ on a Mac) opens or closes me; ↺ starts over. I never give investment advice.",
  "PREF sets how often delayed quotes refresh.": "Delayed quotes refresh about every 45 seconds, and every 15 seconds for securities on screen.",
  "Kestrel Pro is $9.99 a month, $49.99 for 6 months or $99.99 a year, through your Apple ID:": "Kestrel Pro is $9.99 a month, $49.99 for 6 months or $99.99 a year:",
  "Manage subscription opens Apple's settings to change or cancel.": "",
  "Green is up and red down (blue/orange in colour-vision-safe mode, the eye icon at the bottom right).": "Green is up and red down (blue/orange in colour-vision-safe mode, in PREF).",
  "Green is up, red is down (blue/orange with colour-vision-safe mode); tap a tile to load it.": "Green is up, red is down (blue/orange with colour-vision-safe mode in PREF); click a tile to load it.",
  "Kestrel has no API keys and no servers; it reads public market data directly.": "Market data comes from public sources, some through Kestrel's data relay, which sees the symbols you view, not who you are.",
  "This guide runs entirely on the device too.": "This guide runs entirely in your browser too.",
  "Your data stays on your device:": "Your data stays in your browser:",
  "Passwords are never stored, only a salted hash; each account's data is encrypted on the device.": "Passwords are never stored, only a salted hash; each account's data is encrypted in this browser.",
  "Your account, watchlists, paper trades, alerts and this guide live on the device, so nothing is lost while you're offline.": "Your account, watchlists, paper trades, alerts and this guide live in this browser, so nothing is lost while you're offline.",
  "I'm Kestrel's built-in guide. I run entirely on your device, with no internet or AI service:": "I'm Kestrel's built-in guide. I run entirely in your browser, with no AI service:",
  "Tap a command button to open that screen; tap a suggested question to keep going.": "Click a command button to open that screen; click a suggested question to keep going.",
};
const OVERRIDE: Record<string, Partial<HowTo>> = {
  "SEC contact email": { intro: "On the web there's nothing to set up: Kestrel's data relay identifies itself to the SEC for you.", steps: ["FA, EVTS, EQS, ERN and EVST load directly.", "If one fails, the SEC may be busy: reopen the function to retry."], commands: ["MSFT FA", "EQS"] },
  "Moving data between iPad and Mac": { intro: "Your web account lives in this browser, encrypted. Move it to or from the iPad or Mac app with an encrypted file:", steps: ["Open PREF → TRANSFER BETWEEN WEB, IPAD AND MAC.", "Type a passphrase (10+ characters) and click EXPORT FILE, or CHOOSE FILE… to open one exported elsewhere with the same passphrase.", "Importing replaces this account's watchlists, alerts and paper book. Clearing this site's data in your browser deletes the account, so export first."], followUps: ["Is my data private?"] },
};
const web = (s: string) => (s in WEB ? WEB[s] : s);
const fix = (steps: string[]) => steps.map(web).filter(Boolean);
export const topics: Topic[] = rawTopics.map((t) => ({ ...t, summary: web(t.summary), steps: fix(t.steps) }));
export const howTos: HowTo[] = rawHowTos.map((h) => ({ ...h, intro: web(h.intro), steps: fix(h.steps), ...OVERRIDE[h.title] }));
export const glossary = rawGlossary;

/** Functions that need a security first (KestrelCore's `requiresSecurity`). */
const NEEDS = new Set(["DES", "FA", "EVTS", "GP", "HP", "DEPTH", "TAS", "CN", "OMON", "TRADE", "BT", "OSA", "BETA", "FACT", "DVD", "EVST"]);

export function normalize(s: string): string {
  let t = " " + s.toLowerCase() + " ";
  t = t.replace(/’/g, "'").replace(/[?!,.;:\n]/g, " ").replace(/'s /g, " ");
  return t.replace(/ {2,}/g, " ");
}
const glossaryTerm = (q: string) => Object.keys(glossary).sort((a, b) => b.length - a.length).find((k) => q.includes(` ${k} `) || q.includes(` ${k}s `));
const matches = (q: string, k: string) => q.includes(` ${k} `) || q.includes(` ${k}s `) || (k.length >= 6 && q.includes(` ${k}`));

function rank(q: string, original = ""): [Topic, number][] {
  // A function code counts only when typed in capitals ("DVD"), so words like "trade" or "top" don't masquerade as commands.
  const typed = new Set(original.split(/[^A-Za-z]+/).filter((w) => w && w === w.toUpperCase()));
  return topics.flatMap((t): [Topic, number][] => {
    let score = 0;
    for (const k of t.keywords) if (matches(q, k)) score += k.includes(" ") ? 3 : 2;
    if (typed.has(t.function)) score += 4;
    if (t.function === "ECST" && country(original || q)) score += 3;
    return score > 0 ? [[t, score]] : [];
  }).sort((a, b) => b[1] - a[1]);
}
const rankHowTos = (q: string): [HowTo, number][] => howTos.flatMap((h): [HowTo, number][] => {
  const s = h.keywords.filter((k) => matches(q, k)).reduce((n, k) => n + (k.includes(" ") ? 3 : 2), 0);
  return s > 0 ? [[h, s]] : [];
}).sort((a, b) => b[1] - a[1]);

const numbered = (steps: string[]) => steps.map((s, k) => `${k + 1}. ${s}`).join("\n");
const render = (h: HowTo): Reply => ({ text: `${h.intro}\n${numbered(h.steps)}`, commands: [...h.commands], followUps: [...h.followUps] });
function howToUse(t: Topic, security?: Instrument): Reply {
  const cmd = command(t, security, "");
  return { text: `How to use ${t.function} (${fn(t.function).title}): it shows ${t.summary}.\n${numbered(t.steps)}`, commands: cmd === t.example ? [cmd] : [cmd, t.example],
    followUps: NEEDS.has(t.function) ? ["What about another stock?", "What can Kestrel do?"] : ["What can Kestrel do?"] };
}
function command(t: Topic, s: Instrument | undefined, question: string): string {
  if (t.function === "ECST") { const c = country(question); if (c) return `ECST ${c.toUpperCase()}`; }
  if (!s) return t.example;
  if (t.function === "TOP" && s.assetClass === "EQUITY") return `${token(s)} CN`;
  if (t.function === "TRADE") return `${token(s)} ${question.includes(" sell") || question.includes(" short") ? "SELL" : "BUY"}`;
  if (NEEDS.has(t.function) || t.function === "ALRT") return `${token(s)} ${t.function}`;
  return t.example;
}

const COUNTRIES = ["united states", "united kingdom", "south africa", "south korea", "new zealand", "saudi arabia", "japan", "china", "india", "germany",
  "france", "italy", "spain", "canada", "brazil", "mexico", "russia", "australia", "indonesia", "turkey", "argentina", "nigeria",
  "egypt", "kenya", "ghana", "pakistan", "bangladesh", "vietnam", "thailand", "malaysia", "singapore", "philippines", "israel",
  "switzerland", "sweden", "norway", "denmark", "finland", "netherlands", "belgium", "austria", "poland", "ireland", "portugal",
  "greece", "chile", "colombia", "peru", "ukraine", "korea", "uk"];
/** A country named in the question, for ECST ("japan economy" → ECST JAPAN). */
export function country(question: string): string | undefined {
  const q = normalize(question), c = COUNTRIES.find((x) => q.includes(` ${x} `));
  return c === "uk" ? "united kingdom" : c;
}

const esc = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const SKIP = new Set(["I", "A", "OK", "US", "USA", "CEO", "ETF", "SEC", "GDP", "CPI", "FX", "P/E", "PE", "IV", "VAR", "ROE", "ROA", "EPS", "AI", "IPO", "UK", "EU", "MY", "ME", "IS", "IT", "OR", "AND", "THE", "FOR", "HOW", "WHAT", "CSV", "PNL", "SMB", "HML", "GO", "DO", "TO"]);
const ENGLISH = new Set(["link", "sol", "ada", "cost", "meta", "spy", "all", "ma", "ms", "gs", "v", "amd", "ko"]);
const ALIASES: Record<string, string> = { "coca-cola": "KO", "coca cola": "KO", coke: "KO", google: "GOOGL", facebook: "META", berkshire: "BRK-B", "jp morgan": "JPM", goldman: "GS", "home depot": "HD",
  "s&p 500": "SPX", "s&p": "SPX", "dow jones": "INDU", nasdaq: "CCMP", ether: "ETH", gold: "GC1", oil: "CL1", crude: "CL1", euro: "EURUSD" };
const COMMON = new Set(["advanced", "bank", "spdr", "invesco", "the", "new"]);

/** A security named in the question: a ticker in capitals, a lower-case ticker that isn't an everyday word, or a company or coin named in words. */
export function securityMentioned(question: string): Instrument | undefined {
  const words = question.split(/[\s,?!;:()"]+/).filter(Boolean).map((w) => w.replace(/['’]s$/, "").replace(/^['’]+|['’]+$/g, ""));
  for (const w of words) {
    if (w.length > 12 || w !== w.toUpperCase() || !/[A-Z]/.test(w) || SKIP.has(w) || functionFrom(w)) continue;
    const i = instrument(w) ?? all.find((x) => x.ticker === w);
    if (i) return i;
    if (w.includes(".")) { const r = resolve(w); if (r) return r; }
  }
  for (const w of words.map((x) => x.toLowerCase())) {
    if (w.length < 3 || ENGLISH.has(w)) continue;
    const i = [...equities, ...crypto].find((x) => x.ticker.toLowerCase() === w);
    if (i) return i;
  }
  const lower = question.toLowerCase();
  for (const [name, t] of Object.entries(ALIASES).sort((a, b) => b[0].length - a[0].length)) {
    if (new RegExp(`(^|[^\\w])${esc(name)}($|[^\\w])`).test(lower)) { const i = resolve(t); if (i) return i; }
  }
  for (const i of [...equities, ...crypto]) {
    const name = (i.name.toLowerCase().split(" ")[0] ?? "").replace(/^[^\w]+|[^\w]+$/g, "");
    if (name.length < 4 || COMMON.has(name)) continue;
    if (new RegExp(`\\b${esc(name)}\\b`).test(lower)) return i;
  }
  return undefined;
}
function securitiesMentioned(question: string): Instrument[] {
  const out: Instrument[] = [];
  for (const part of question.split(/[,;]/).flatMap((p) => p.split(" and ")).flatMap((p) => p.split(" vs "))) {
    const i = securityMentioned(part);
    if (i && !out.includes(i)) out.push(i);
    if (out.length === 3) break;
  }
  return out;
}

/** Answers `question`, updating `context` so follow-ups ("how do I use it?", "and for Microsoft?") work. */
export function answer(question: string, context: Context = {}): Reply {
  const q = normalize(question);
  const named = securityMentioned(question);
  const security = named ?? context.security;
  try {
    const fs = rank(q, question), hs = rankHowTos(q);
    const bestF = fs[0]?.[1] ?? 0, bestH = hs[0]?.[1] ?? 0;

    // 1. Follow-ups about the current function.
    const follow = [" it ", " that ", " this ", " more", "how does it", "how do i use it", "how do i read", "explain that", "what does it show", "steps"];
    const cur = topics.find((t) => t.function === context.function);
    if (bestF < 2 && bestH < 3 && cur && follow.some((w) => q.includes(w))) return howToUse(cur, security);

    // 2. A new security alone keeps the function: "and for Microsoft?".
    const switching = [" what about ", " and for ", " how about ", " and ", " now ", " same for ", " for "].some((p) => q.startsWith(p));
    if (named && bestF < (switching ? 4 : 2) && bestH < 3 && !glossaryTerm(q) && cur && (NEEDS.has(cur.function) || cur.function === "ALRT" || cur.function === "TRADE")) {
      return { text: `${cur.function} for ${named.ticker} (${named.name}): ${cur.summary}.`, commands: [command(cur, named, q), `${token(named)} DES`], followUps: [`How do I use ${cur.function}?`] };
    }

    // 3. Task guides. Advice requests always get the no-advice answer.
    const top = hs[0];
    if (top && (top[0].title === "Investment advice" ? top[1] >= 2 : top[1] >= 3) && (top[1] >= bestF || q.includes(" how ") || top[0].title === "Investment advice")) {
      const h = top[0];
      if (h.title === "Investment advice") {
        const t = security ? token(security) : "AAPL", r = render(h);
        r.commands = [`${t} DES`, security?.assetClass === "CRYPTO" ? `${t} GP` : `${t} FA`, `${t} BETA`];
        return r;
      }
      if ((h.title === "Placing a paper trade" || h.title === "Short selling") && security) {
        context.function = "TRADE";
        const side = h.title === "Short selling" || q.includes(" sell") ? "SELL" : "BUY", r = render(h);
        r.commands = [`${token(security)} ${side}`, ...r.commands.filter((c) => !c.endsWith(" BUY") && !c.endsWith(" SELL"))];
        return r;
      }
      return render(h);
    }

    // 4. Glossary.
    const definitional = [" what is ", " what are ", " what does ", " what do ", " whats ", " what ", " mean", " explain", " define", " definition", " meaning"].some((w) => q.includes(w));
    const term = glossaryTerm(q);
    if (term && (definitional || q.trim() === term)) {
      const related = fs.slice(0, 2).map(([t]) => command(t, security, q)), home = glossaryHome[term];
      return { text: glossary[term] + (home ? ` See ${home}.` : ""), commands: related.length ? related : home ? [home] : [], followUps: ["What can Kestrel do?"] };
    }

    // 5. Greetings and "I'm lost".
    const greet = [" hi ", " hello ", " hey ", " help ", " lost ", " confused ", " confusing ", " stuck ", " don't understand ", " dont understand ", " overwhelmed ", " thanks ", " thank you "];
    if (!fs.length && !named && (!q.trim() || greet.some((g) => q.includes(g)))) {
      if (q.includes(" thank")) return { text: "You're welcome! Ask me anything else, any time.", commands: [], followUps: ["What can Kestrel do?"] };
      return render(howTos.find((h) => h.title === "Getting started")!);
    }

    // 6. Functions.
    if (!fs.length) {
      if (named) { const t = token(named); return { text: `${named.name} (${named.ticker}). DES is its overview and GP its chart.`, commands: [`${t} DES`, `${t} GP`, named.assetClass === "EQUITY" ? `${t} FA` : `${t} HP`], followUps: ["How do I place a trade?", "What can Kestrel do?"] }; }
      return { text: "I'm not sure what you mean. Try describing what you want to see or do, like \"Apple's dividends\", \"compare my watchlist\" or \"how do I buy\". To find a company or ticker, SECF searches every exchange.", commands: ["HELP", "SECF"], followUps: ["What can Kestrel do?", "How do I place a trade?"] };
    }
    const picks = fs.slice(0, 3).filter(([, s]) => s >= Math.max(1, Math.floor(fs[0][1] / 2))).map(([t]) => t);
    const main = picks[0];
    context.function = main.function;
    if (main.function === "COMP") {
      const several = securitiesMentioned(question);
      if (several.length >= 2) {
        const [a, b] = several;
        return { text: `To compare ${a.ticker} and ${b.ticker}: add both to your watchlist (W) and run COMP for returns, Sharpe and drawdown side by side, or open each chart (GP).`, commands: [`${token(a)} GP`, "W", "COMP"], followUps: ["How do I manage watchlists?"] };
      }
    }
    if (main.function === "TOP" && security?.assetClass === "EQUITY") {
      context.function = "CN";
      return { text: `CN shows news for ${security.ticker}; TOP has all market news with search.`, commands: [`${token(security)} CN`, "TOP"], followUps: ["What about another stock?"] };
    }
    if ([" how ", " use ", " using ", " steps ", " work ", " works "].some((w) => q.includes(w))) return howToUse(main, security);
    let text = `${main.function} shows ${main.summary}.`;
    if (security && NEEDS.has(main.function)) text = `${main.function} for ${security.ticker} shows ${main.summary}.`;
    else if (NEEDS.has(main.function)) text += ` Type a ticker first, e.g. ${main.example}. Don't know the ticker? Use SECF.`;
    if (picks.length > 1) text += "\nRelated: " + picks.slice(1).map((t) => `${t.function} (${fn(t.function).title.toLowerCase()})`).join(", ") + ".";
    return { text, commands: picks.map((t) => command(t, security, q)), followUps: [`How do I use ${main.function}?`, ...(NEEDS.has(main.function) ? ["What about another stock?"] : [])] };
  } finally {
    if (named) context.security = named;
  }
}
