import { Store } from "./store";

const CVD = "kestrel.cvd";
const read = (k: string) => { try { return localStorage.getItem(k); } catch { return null; } };

/** Device display preferences (not account data, so not in the vault). */
export class Prefs extends Store {
  cvd = read(CVD) === "1";
  constructor() { super(); this.apply(); }
  setCVD(on: boolean) {
    this.cvd = on;
    try { localStorage.setItem(CVD, on ? "1" : "0"); } catch { /* private mode */ }
    this.apply(); this.emit();
  }
  private apply() {
    if (typeof document === "undefined") return;
    if (this.cvd) document.documentElement.setAttribute("data-cvd", "1"); else document.documentElement.removeAttribute("data-cvd");
  }
}
export const prefs = new Prefs();
