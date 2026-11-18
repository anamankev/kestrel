import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "./ui/theme.css";
import { App } from "./App";
import { market } from "./data/market";
import { workspace, userData } from "./data/workspace";
import { auth } from "./data/auth";

// Development only: inspect state from the console. Stripped from production builds.
if (import.meta.env.DEV) Object.assign(window, { __kestrel: { market, workspace, auth, userData } });

createRoot(document.getElementById("root")!).render(<StrictMode><App /></StrictMode>);
