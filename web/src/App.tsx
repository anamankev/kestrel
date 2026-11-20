import { useEffect, useState } from "react";
import { auth } from "./data/auth";
import { useStore } from "./data/store";
import { AuthView } from "./ui/Auth";
import { PREVIEW, SubscribeView } from "./ui/Subscribe";
import { Terminal } from "./ui/Shell";

/** Launch order, as in the app: sign in → subscribe → terminal. */
export function App() {
  useStore(auth);
  const [preview, setPreview] = useState(() => PREVIEW && sessionStorage.getItem("kestrel.preview") === auth.current?.id);
  useEffect(() => { void auth.start(); }, []);
  useEffect(() => { setPreview(PREVIEW && !!auth.current && sessionStorage.getItem("kestrel.preview") === auth.current.id); }, [auth.current?.id]);
  if (!auth.ready) return <div className="empty"><div className="t">Loading…</div></div>;
  if (!auth.current) return <AuthView />;
  // Production builds compile the preview out entirely (PREVIEW is a build-time constant), key included.
  if (!preview) return <SubscribeView onPreview={PREVIEW ? () => { sessionStorage.setItem("kestrel.preview", auth.current!.id); setPreview(true); } : undefined} />;
  return <Terminal />;
}
