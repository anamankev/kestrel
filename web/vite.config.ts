import { existsSync, readFileSync } from "node:fs";
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

/** `vite preview` serves dist/_headers' site-wide block, so the production CSP can be checked locally. */
function siteHeaders(): Record<string, string> {
  if (!existsSync("dist/_headers")) return {};
  const block = readFileSync("dist/_headers", "utf8").split(/\n(?=\S)/)[0];
  return Object.fromEntries(block.split("\n").slice(1).map((l) => l.trim()).filter((l) => l && !l.startsWith("Strict-Transport")).map((l) => [l.slice(0, l.indexOf(":")), l.slice(l.indexOf(":") + 1).trim()]));
}

export default defineConfig({
  plugins: [react()],
  server: { port: 5173, strictPort: true },
  preview: { port: 4173, strictPort: true, headers: siteHeaders() },
  build: { sourcemap: false, target: "es2022" },
  test: { environment: "node", include: ["src/**/*.test.ts", "worker/src/**/*.test.ts"] },
} as never);
