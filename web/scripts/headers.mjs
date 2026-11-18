// Writes dist/_headers for Cloudflare Pages: a strict Content-Security-Policy that allows only the
// data sources the app calls, plus standard hardening headers. Run after `vite build`.
// The relay origin comes from VITE_RELAY_URL (the same variable the app is built with).
import { writeFileSync, readFileSync, existsSync } from "node:fs";

const fromEnvFile = () => {
  if (!existsSync(".env.production")) return undefined;
  const m = /^VITE_RELAY_URL=(.+)$/m.exec(readFileSync(".env.production", "utf8"));
  return m?.[1].trim();
};
const relay = process.env.VITE_RELAY_URL ?? fromEnvFile() ?? "http://localhost:8787";
const relayOrigin = new URL(relay).origin;
if (relayOrigin.startsWith("http://") && !/localhost|127\.0\.0\.1/.test(relayOrigin)) throw new Error(`Relay must be https: ${relayOrigin}`);

const connect = [
  "'self'", relayOrigin,
  "https://api.exchange.coinbase.com", "wss://advanced-trade-ws.coinbase.com", // live crypto
  "https://api.worldbank.org", "https://markets.newyorkfed.org", "https://www.deribit.com", // direct public APIs
];
const csp = [
  // 'wasm-unsafe-eval' allows WebAssembly only (Argon2id password hashing); eval() stays blocked.
  "default-src 'self'", "script-src 'self' 'wasm-unsafe-eval'", "style-src 'self' 'unsafe-inline'", "img-src 'self' data:", "font-src 'self'",
  `connect-src ${connect.join(" ")}`, "object-src 'none'", "base-uri 'none'", "form-action 'self'", "frame-ancestors 'none'",
  // Upgrading would break a local http relay; production relays are https anyway.
  ...(relayOrigin.startsWith("https://") ? ["upgrade-insecure-requests"] : []),
].join("; ");

writeFileSync("dist/_headers", `/*
  Content-Security-Policy: ${csp}
  X-Content-Type-Options: nosniff
  Referrer-Policy: no-referrer
  X-Frame-Options: DENY
  Cross-Origin-Opener-Policy: same-origin
  Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=(), usb=()
  Strict-Transport-Security: max-age=31536000; includeSubDomains

/assets/*
  Cache-Control: public, max-age=31536000, immutable
`);
console.log(`dist/_headers written (relay ${relayOrigin})`);
