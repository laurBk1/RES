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

// Curated CC0 sounds from wyzowl/sfx-kit, pinned to a commit (list in src/short/sfx-kit.json).
const kit = JSON.parse(fs.readFileSync(path.join(process.cwd(), "src", "short", "sfx-kit.json"), "utf8"));
const kitDir = path.join(dir, "kit");
fs.mkdirSync(kitDir, { recursive: true });
const files = new Map(Object.values(kit.kinds).flat().map(([id, file]) => [id, file]));
await Promise.all([...files].map(async ([id, file]) => {
  const out = path.join(kitDir, `${id}.wav`);
  if (fs.existsSync(out)) return;
  const url = `https://raw.githubusercontent.com/wyzowl/sfx-kit/${kit.commit}/${file}`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${url}: ${res.status}`);
  fs.writeFileSync(out, Buffer.from(await res.arrayBuffer()));
}));
console.log(`${files.size} sfx-kit sounds in public/sfx/kit`);
