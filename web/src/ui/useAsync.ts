import { useEffect, useState } from "react";

/** Runs an async loader when `deps` change; ignores results from stale runs. */
export function useAsync<T>(load: () => Promise<T>, deps: unknown[]): { data?: T; error?: string; loading: boolean } {
  const [s, set] = useState<{ data?: T; error?: string; loading: boolean }>({ loading: true });
  useEffect(() => {
    let live = true;
    set({ loading: true });
    load().then((data) => live && set({ data, loading: false }), (e) => live && set({ error: String(e?.message ?? e), loading: false }));
    return () => { live = false; };
  }, deps); // eslint-disable-line react-hooks/exhaustive-deps
  return s;
}
