#!/usr/bin/env node
// gen_readme_badges.js — monochrome README badges in the same Mono grammar as the charts.
// Local SVG on purpose: no shields.io round-trip, nothing to rate-limit or go stale, and the paper/ink
// palette matches assets/readme/charts/* instead of clashing with it.
const fs = require('fs'), path = require('path');
const OUT = process.argv[2] || '.';

const PAPER='#F0EFEB', INK='#1C1C1A', MUTED='#8F8E88', LINE='#D6D5CE';
const esc = s => String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');

// Advance widths by character CLASS, not a flat per-char average: a flat average over-measures any
// string containing spaces or `+` (both far narrower than an uppercase glyph), which left the wider
// badges with a visibly uneven right margin. Ratios are Inter's, scaled by font-size, plus tracking.
const CLASS_W = c =>
  c === ' '                    ? 0.26 :
  /[+]/.test(c)                ? 0.60 :
  /[.,:;'|]/.test(c)           ? 0.28 :
  /[0-9]/.test(c)              ? 0.60 :
  /[IJl1]/.test(c)             ? 0.34 :
  /[MW]/.test(c)               ? 0.88 :
  /[a-z]/.test(c)              ? 0.57 :
                                 0.68;
const measure = (s, size, tracking) =>
  [...s].reduce((w,c)=>w + CLASS_W(c)*size + tracking*size, 0);

function badge({file, label, value}){
  const PAD=9, GAP=7, H=22;
  const lw = measure(label, 8, 0.10), vw = measure(value, 9, 0.04);
  const W = Math.round(PAD + lw + GAP + vw + PAD);
  const svg =
`<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" role="img" aria-label="${esc(label)}: ${esc(value)}" font-family="Inter, -apple-system, sans-serif">`
+`<style>text{font-family:Inter,-apple-system,'Helvetica Neue',Arial,sans-serif}</style>`
+`<title>${esc(label)}: ${esc(value)}</title>`
+`<rect x="0.5" y="0.5" width="${W-1}" height="${H-1}" rx="${(H-1)/2}" fill="${PAPER}" stroke="${LINE}"/>`
+`<text x="${PAD}" y="14.6" font-size="8" font-weight="600" letter-spacing="0.1em" fill="${MUTED}">${esc(label)}</text>`
+`<text x="${PAD+lw+GAP}" y="14.8" font-size="9" font-weight="800" letter-spacing="0.04em" fill="${INK}">${esc(value)}</text>`
+`</svg>\n`;
  fs.writeFileSync(path.join(OUT,file), svg);
  console.log(`  ${file}  ${W}×${H}`);
}

badge({file:'badge-version.svg', label:'VERSION',  value:'v2.2'});
// The count is a CLAIM. scripts/smoke_test.sh asserts this badge matches its own total and tells you to
// rerun this generator when it drifts, so a stale front-page number fails the suite rather than shipping.
badge({file:'badge-smoke.svg',   label:'SMOKE',    value:'312 PASSING'});
badge({file:'badge-panel.svg',   label:'PANEL',    value:'CLAUDE + CODEX + GEMINI'});
badge({file:'badge-deps.svg',    label:'RUNTIME',  value:'BASH + PYTHON3'});
badge({file:'badge-license.svg', label:'LICENSE',  value:'MIT'});
