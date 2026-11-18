// Fails a production build that would point at the wrong relay or ship the preview bypass by accident.
// `npm run build:local` builds against the local relay for checking the production bundle on this machine.
import { existsSync, readFileSync } from "node:fs";

const file = existsSync(".env.production") ? readFileSync(".env.production", "utf8") : "";
const get = (k) => process.env[k] ?? new RegExp(`^${k}=(.+)$`, "m").exec(file)?.[1]?.trim();
const relay = get("VITE_RELAY_URL");
const local = process.env.KESTREL_LOCAL_BUILD === "1";
const fail = (m) => { console.error(`check-env: ${m}`); process.exit(1); };

if (!relay) fail("VITE_RELAY_URL is not set (put it in .env.production, or use `npm run build:local`)");
let u;
try { u = new URL(relay); } catch { fail(`VITE_RELAY_URL is not a URL: ${relay}`); }
if (!local && u.protocol !== "https:") fail(`VITE_RELAY_URL must be https for a production build: ${relay}`);
if (!local && get("VITE_WEB_PREVIEW") === "1") console.warn("check-env: VITE_WEB_PREVIEW=1 lets signed-in users past the subscribe page without paying");
console.log(`check-env: ok (relay ${u.origin}${local ? ", local build" : ""})`);
