import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "./ui/theme.css";
import { Terminal } from "./ui/Shell";
import { market } from "./data/market";
import { workspace } from "./data/workspace";

// Development only: inspect state from the console. Stripped from production builds.
if (import.meta.env.DEV) Object.assign(window, { __kestrel: { market, workspace } });

createRoot(document.getElementById("root")!).render(<StrictMode><Terminal /></StrictMode>);
