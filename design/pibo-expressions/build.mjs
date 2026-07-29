// build.mjs — 生成静态 SVG 文件 + 组合大图。 用法: node build.mjs
import { buildSVG } from './pibo-face.js';
import { FACES } from './faces.js';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const outDir = join(here, 'svg');
mkdirSync(outDir, { recursive: true });

let idx = 0;
for (const f of FACES) {
  const svg = buildSVG(f, { bg: true });
  const num = String(++idx).padStart(2, '0');
  writeFileSync(join(outDir, `pibo-${num}-${f.id}.svg`), svg);
}
console.log(`✓ wrote ${idx} expression SVGs → svg/`);

// contact sheet: all faces in a grid, one big SVG
const cols = 4;
const cellW = 181, cellH = 247, pad = 16, labelH = 30;
const rows = Math.ceil(FACES.length / cols);
const W = cols * (cellW + pad) + pad;
const H = rows * (cellH + labelH + pad) + pad + 40;
let cells = '';
FACES.forEach((f, i) => {
  const cx = pad + (i % cols) * (cellW + pad);
  const cy = 48 + Math.floor(i / cols) * (cellH + labelH + pad);
  const inner = buildSVG(f, { bg: true, size: cellW }); // explicit w/h so nested <svg> keeps its box
  cells += `<g transform="translate(${cx},${cy})">${inner}
    <text x="${cellW / 2}" y="${cellH + 20}" text-anchor="middle" font-family="PingFang SC, sans-serif"
          font-size="15" fill="#454f58" font-weight="600">${f.zh} · ${f.name}</text></g>`;
});
const sheet = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">
  <rect width="${W}" height="${H}" fill="#f4f7f6"/>
  <text x="${W / 2}" y="30" text-anchor="middle" font-family="PingFang SC, sans-serif" font-size="20"
        font-weight="700" fill="#20937a">Pibo 表情系统 · Expression System</text>
  ${cells}
</svg>`;
writeFileSync(join(here, 'pibo-expression-sheet.svg'), sheet);
console.log('✓ wrote contact sheet → pibo-expression-sheet.svg');
