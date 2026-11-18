import { Store } from "./store";
import { AccountDirectory, AuthError, b64, importDataKey, open, seal, unb64, SESSION_LIFETIME, type AccountRecord } from "../core/auth";
import { userData, workspace } from "./workspace";
import { broker } from "./broker";
import { alerts } from "./alerts";

const DIR = "kestrel.accounts.v1";
const DATA = (id: string) => `kestrel.vault.${id}`;
const enc = new TextEncoder(), dec = new TextDecoder();

/** IndexedDB holds the session: the account id and its data key as a non-extractable CryptoKey. */
function idb<T>(mode: IDBTransactionMode, fn: (s: IDBObjectStore) => IDBRequest<T> | void): Promise<T | undefined> {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open("kestrel", 1);
    req.onupgradeneeded = () => req.result.createObjectStore("session");
    req.onerror = () => reject(req.error);
    req.onsuccess = () => {
      const tx = req.result.transaction("session", mode);
      const r = fn(tx.objectStore("session"));
      tx.oncomplete = () => { resolve(r ? (r as IDBRequest<T>).result : undefined); req.result.close(); };
      tx.onerror = () => reject(tx.error);
    };
  });
}

interface Session { id: string; key: CryptoKey; expires: number }

/** Browser accounts: each person's watchlists and workspace live encrypted under their own key. */
export class AuthService extends Store {
  directory = new AccountDirectory(this.loadDirectory());
  current: AccountRecord | null = null;
  ready = false;
  busy = false;
  private key: CryptoKey | null = null;
  private timer: number | undefined;

  private loadDirectory(): AccountRecord[] {
    try { const raw = JSON.parse(localStorage.getItem(DIR) ?? "[]"); return Array.isArray(raw) ? raw : []; } catch { return []; }
  }
  private saveDirectory() { localStorage.setItem(DIR, JSON.stringify(this.directory.accounts)); }

  /** Resumes a stored session (30 days, sliding). */
  async start() {
    // Phase 1 kept the workspace and watchlists in plain browser storage: remove them.
    for (const k of ["kestrel.workspace.v1", "kestrel.watchlists.v1"]) localStorage.removeItem(k);
    try {
      const s = await idb<Session>("readonly", (st) => st.get("current"));
      const r = s && s.expires > Date.now() ? this.directory.accounts.find((a) => a.id === s.id) : undefined;
      if (s && r) await this.enter(r, s.key);
      else if (s) await idb("readwrite", (st) => st.delete("current"));
    } catch { /* no IndexedDB (private mode): sign in each visit */ }
    this.ready = true; this.emit();
  }

  async register(name: string, email: string, password: string, confirm: string) {
    return this.guard(async () => {
      const r = await this.directory.register(name, email, password, confirm);
      await this.unlock(r, password);
    });
  }

  async signIn(email: string, password: string) {
    return this.guard(async () => {
      try { const r = await this.directory.signIn(email, password); await this.unlock(r, password); }
      finally { this.saveDirectory(); } // persists failed-attempt counts and lockouts too
    });
  }

  async signOut() {
    await this.flush();
    this.current = null; this.key = null;
    userData.persist = workspace.persist = broker.persist = alerts.persist = () => {};
    userData.restore(null); workspace.restore(null); broker.restore(null); alerts.restore(null);
    try { await idb("readwrite", (st) => st.delete("current")); } catch { /* ignore */ }
    this.emit();
  }

  /** Deletes the signed-in account and its data from this browser after re-checking the password. */
  async deleteAccount(password: string) {
    const me = this.current;
    if (!me) return;
    return this.guard(async () => {
      await this.directory.signIn(me.email, password);
      localStorage.removeItem(DATA(me.id));
      this.directory.remove(me.id); this.saveDirectory();
      await this.signOut();
    });
  }

  private async guard(fn: () => Promise<void>): Promise<string | null> {
    if (this.busy) return null;
    this.busy = true; this.emit();
    try { await fn(); return null; }
    catch (e) { return e instanceof AuthError ? e.message : "Something went wrong. Try again."; }
    finally { this.busy = false; this.emit(); }
  }

  private async unlock(r: AccountRecord, password: string) {
    const raw = await this.directory.unlockDataKey(r.id, password);
    this.saveDirectory();
    const key = await importDataKey(raw); // non-extractable: scripts can use it but never read it
    await this.enter(r, key);
  }

  private async enter(r: AccountRecord, key: CryptoKey) {
    this.key = key; this.current = r;
    let state: any = null;
    const box = localStorage.getItem(DATA(r.id));
    if (box) { try { state = JSON.parse(dec.decode(await open(unb64(box), key))); } catch { state = null; } }
    userData.restore(state?.watchlists); workspace.restore(state?.workspace); broker.restore(state?.paper); alerts.restore(state?.alerts);
    userData.persist = workspace.persist = broker.persist = alerts.persist = () => this.schedule();
    try { await idb("readwrite", (st) => st.put({ id: r.id, key, expires: Date.now() + SESSION_LIFETIME } satisfies Session, "current")); } catch { /* session won't persist */ }
    this.emit();
  }

  private schedule() { clearTimeout(this.timer); this.timer = window.setTimeout(() => void this.flush(), 400); }

  /** Encrypts and stores the account's data. */
  async flush() {
    clearTimeout(this.timer);
    if (!this.current || !this.key) return;
    const plain = enc.encode(JSON.stringify({ watchlists: userData.snapshot(), workspace: workspace.snapshot(), paper: broker.snapshot(), alerts: alerts.snapshot() }));
    localStorage.setItem(DATA(this.current.id), b64(await seal(plain, this.key)));
  }
}

export const auth = new AuthService();
if (typeof window !== "undefined") window.addEventListener("pagehide", () => void auth.flush());
