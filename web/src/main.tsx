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

// Development only: inspect state from the console. Stripped from production builds.
if (import.meta.env.DEV) Object.assign(window, { __kestrel: { market, workspace, auth, userData, broker, alerts, resolve } });

createRoot(document.getElementById("root")!).render(<StrictMode><App /></StrictMode>);
