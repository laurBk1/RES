// Convert a TTF/OTF into the typeface JSON that three.js FontLoader reads, so 3D text keeps Romanian diacritics.
// usage: node scripts/font-to-typeface.mjs fonts/Anton-Regular.ttf public/fonts/anton.typeface.json
import fs from "node:fs";
import opentype from "opentype.js";

const [src, out] = process.argv.slice(2);
if (!src || !out) {
  console.error("usage: node scripts/font-to-typeface.mjs FONT.ttf OUT.json");
  process.exit(1);
}
const font = opentype.loadSync(src);
const scale = 100000 / ((font.unitsPerEm || 2048) * 72);
const r = (v) => Math.round(v * scale);
const glyphs = {};
for (let i = 0; i < font.glyphs.length; i++) {
  const g = font.glyphs.get(i);
  for (const code of g.unicodes || []) {
    const o = g.path.commands
      .map((c) => {
        if (c.type === "M") return `m ${r(c.x)} ${r(c.y)}`;
        if (c.type === "L") return `l ${r(c.x)} ${r(c.y)}`;
        // three.js expects the end point first, then the control points.
        if (c.type === "Q") return `q ${r(c.x)} ${r(c.y)} ${r(c.x1)} ${r(c.y1)}`;
        if (c.type === "C") return `b ${r(c.x)} ${r(c.y)} ${r(c.x1)} ${r(c.y1)} ${r(c.x2)} ${r(c.y2)}`;
        return "";
      })
      .filter(Boolean)
      .join(" ");
    glyphs[String.fromCodePoint(code)] = { ha: r(g.advanceWidth), x_min: r(g.xMin ?? 0), x_max: r(g.xMax ?? 0), o };
  }
}
const head = font.tables.head;
fs.mkdirSync(new URL(".", `file://${process.cwd()}/${out}`).pathname, { recursive: true });
fs.writeFileSync(out, JSON.stringify({
  glyphs,
  familyName: font.names.fontFamily?.en ?? "font",
  ascender: r(font.ascender),
  descender: r(font.descender),
  underlinePosition: r(font.tables.post.underlinePosition),
  underlineThickness: r(font.tables.post.underlineThickness),
  boundingBox: { xMin: r(head.xMin), yMin: r(head.yMin), xMax: r(head.xMax), yMax: r(head.yMax) },
  resolution: 1000,
  original_font_information: {},
  cssFontWeight: "normal",
  cssFontStyle: "normal",
}));
console.log(`${Object.keys(glyphs).length} glyphs -> ${out}`);
