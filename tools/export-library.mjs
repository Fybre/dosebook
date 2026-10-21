#!/usr/bin/env node
// Exports the Bench reference library (TypeScript) to JSON resources for BenchCore.
//
//   node tools/export-library.mjs <path-to-Bench-clone>
//
// The data files import types only, so Node's type stripping can load them once
// they carry a .ts extension. They are copied to a temp dir first so nothing in
// the clone is modified or executed beyond the data modules themselves.
import { mkdtempSync, copyFileSync, writeFileSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const src = process.argv[2];
if (!src) {
  console.error("usage: node tools/export-library.mjs <path-to-Bench-clone>");
  process.exit(1);
}
const here = dirname(fileURLToPath(import.meta.url));
const out = resolve(here, "../BenchCore/Sources/BenchCore/Resources");
const work = mkdtempSync(join(tmpdir(), "bench-lib-"));
const groups = ["metabolic", "repair", "growth", "anabolic", "ancillary"];

mkdirSync(join(work, "peptides"));
for (const g of groups) copyFileSync(join(src, "src/lib/data/peptides", `${g}.ts`), join(work, "peptides", `${g}.ts`));
copyFileSync(join(src, "src/lib/data/labs.ts"), join(work, "labs.ts"));

const load = (p) => import(pathToFileURL(join(work, p)).href);
const peptides = [];
for (const g of groups) {
  const mod = await load(`peptides/${g}.ts`);
  peptides.push(...mod[g.toUpperCase()]);
}
// Same order as PEPTIDES in index.ts.
peptides.sort((a, b) => a.name.localeCompare(b.name));
const ids = new Set(peptides.map((p) => p.id));
if (ids.size !== peptides.length) throw new Error("duplicate peptide id");

const labs = await load("labs.ts");
writeFileSync(join(out, "peptides.json"), JSON.stringify(peptides, null, 1) + "\n");
writeFileSync(
  join(out, "labs.json"),
  JSON.stringify({ markers: labs.LAB_MARKERS, categoryLabels: labs.LAB_CATEGORY_LABEL }, null, 1) + "\n",
);
console.log(`peptides: ${peptides.length}, lab markers: ${labs.LAB_MARKERS.length} -> ${out}`);
