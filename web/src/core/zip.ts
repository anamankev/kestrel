/** Minimal ZIP reader for one-file deflate archives (French Data Library, World Bank bulk). */
export async function zipFile(data: Uint8Array, match: (name: string) => boolean = () => true, maxSize = 32 << 20): Promise<Uint8Array> {
  const b = data, u16 = (o: number) => b[o] | (b[o + 1] << 8), u32 = (o: number) => (u16(o) | (u16(o + 2) << 16)) >>> 0;
  let eocd = -1;
  for (let i = b.length - 22; i >= Math.max(0, b.length - 65_557); i--) if (b[i] === 0x50 && b[i + 1] === 0x4b && b[i + 2] === 5 && b[i + 3] === 6) { eocd = i; break; }
  if (eocd < 0) throw new Error("not a zip");
  let cd = u32(eocd + 16);
  for (let e = 0; e < u16(eocd + 10); e++) {
    if (u32(cd) !== 0x02014b50) throw new Error("corrupt zip");
    const nameLen = u16(cd + 28), name = new TextDecoder().decode(b.subarray(cd + 46, cd + 46 + nameLen));
    if (match(name)) {
      const method = u16(cd + 10), packed = u32(cd + 20), size = u32(cd + 24), local = u32(cd + 42);
      if (size > maxSize || u32(local) !== 0x04034b50) throw new Error("corrupt zip");
      const start = local + 30 + u16(local + 26) + u16(local + 28);
      const body = b.slice(start, start + packed);
      if (method === 0) return body;
      if (method !== 8) throw new Error("unsupported zip method");
      const out = new Uint8Array(await new Response(new Blob([body]).stream().pipeThrough(new DecompressionStream("deflate-raw"))).arrayBuffer());
      if (out.length !== size) throw new Error("corrupt zip");
      return out;
    }
    cd += 46 + nameLen + u16(cd + 30) + u16(cd + 32);
  }
  throw new Error("file not found in zip");
}
