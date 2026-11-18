import { StrictMode } from "react";
import { broker } from "./data/broker";
import { alerts } from "./data/alerts";
import { resolve } from "./core/universe";
import { createRoot } from "react-dom/client";
import "./ui/theme.css";
import { App } from "./App";
import { market } from "./data/market";
import { workspace, userData } from "./data/workspace";
import { auth } from "./data/auth";
import "./data/prefs";

// Keyboard: focusable table rows and headers (tr.click, [data-click]) activate with Enter or Space, like buttons.
document.addEventListener("keydown", (e) => {
  if (e.key !== "Enter" && e.key !== " ") return;
  const t = e.target as HTMLElement | null;
  if (t?.matches?.("tr.click, [data-click]")) { e.preventDefault(); t.click(); }
});

// Development only: inspect state from the console. Stripped from production builds.
if (import.meta.env.DEV) Object.assign(window, { __kestrel: { market, workspace, auth, userData, broker, alerts, resolve } });

createRoot(document.getElementById("root")!).render(<StrictMode><App /></StrictMode>);
