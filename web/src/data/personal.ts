/** Per-person screen settings kept in plain browser storage (outside the encrypted vault): chart trendlines
 *  and the bond calculator's inputs. They are cleared at sign-out so the next person on a shared computer
 *  (a library or lab machine) never sees them. Display preferences (ranges, colour mode) are kept. */
export const PERSONAL_PREFIXES = ["gp.lines.", "yas."];

export function clearPersonalUI(storage: Storage = localStorage) {
  try {
    const doomed: string[] = [];
    for (let i = 0; i < storage.length; i++) { const k = storage.key(i); if (k && PERSONAL_PREFIXES.some((p) => k.startsWith(p))) doomed.push(k); }
    doomed.forEach((k) => storage.removeItem(k));
  } catch { /* storage unavailable */ }
}
