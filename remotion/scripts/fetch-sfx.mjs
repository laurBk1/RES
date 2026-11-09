// Download the @remotion/sfx sounds into public/sfx so renders work offline and use staticFile().
import fs from "node:fs";
import path from "node:path";
import * as sfx from "@remotion/sfx";

const dir = path.join(process.cwd(), "public", "sfx");
fs.mkdirSync(dir, { recursive: true });
const urls = Object.values(sfx).filter((v) => typeof v === "string" && v.startsWith("https://"));
await Promise.all(urls.map(async (url) => {
  const out = path.join(dir, path.basename(url));
  if (fs.existsSync(out)) return;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${url}: ${res.status}`);
  fs.writeFileSync(out, Buffer.from(await res.arrayBuffer()));
}));
console.log(`${urls.length} sound effects in public/sfx`);
