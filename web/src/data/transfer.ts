import { MAX_FILE, openBundle, sealBundle, TransferError, type Bundle } from "../core/transfer";
import type { Bytes } from "../core/auth";
import { PaperAccount } from "../core/paper";
import { AlertBook } from "../core/alerts";
import { alerts } from "./alerts";
import { broker } from "./broker";
import { userData } from "./workspace";

/** This account's watchlists, alerts and paper book as a sealed transfer file (the same format as the iPad/Mac app). */
export async function exportFile(passphrase: string): Promise<Blob> {
  const b: Bundle = {
    exported: Date.now(), watchlists: userData.lists.map((l) => ({ ...l, symbols: [...l.symbols] })), activeID: userData.activeId,
    alerts: AlertBook.from(JSON.parse(JSON.stringify(alerts.book))), account: PaperAccount.from(JSON.parse(JSON.stringify(broker.account))),
  };
  return new Blob([await sealBundle(b, passphrase)], { type: "application/octet-stream" });
}

/** Opens a chosen file. The size is checked before reading, so a huge file can't exhaust memory; the contents
 *  (magic bytes, authenticated encryption, then every field) are checked by openBundle. */
export async function readFile(f: File, passphrase: string) {
  if (f.size > MAX_FILE || f.size <= 24) throw new TransferError("That isn't a Kestrel transfer file");
  return openBundle(new Uint8Array(await f.arrayBuffer()) as Bytes, passphrase);
}

/** Replaces this account's watchlists, alerts and paper book with an opened (already validated) file. */
export function applyBundle(b: Bundle) {
  userData.restore({ lists: b.watchlists, activeId: b.activeID });
  userData.persist();
  alerts.restore({ alerts: b.alerts.alerts });
  alerts.persist();
  broker.restore({ account: b.account });
  broker.persist();
}

export const fileName = () => `Kestrel-${new Date().toISOString().slice(0, 10)}.kestrel`;
