// Pibo 表情系统 · 矢量脸部引擎 (pure functions, ESM — runs in browser & node)
// -----------------------------------------------------------------------------
// 忠于原始 UI: body / sprout / 默认脸 均来自 Figma node 3904:1804 导出的真实矢量
// (src/body.svg, src/sprout.svg)，chrome 已剥离。表情系统只替换会变化的脸部部件，
// 且严格沿用原始锚点/尺寸/配色:
//   眉毛 brows  r2  #cdd7dd @ (76.21,56.01)/(122.21,56.01)
//   眼睛 eyes   r4.5 #454f58 @ (75.71,66.51)/(122.71,66.51)
//   海豹鼻 muzzle Union 交叠圆 #cdd7dd (常驻, 原始 path)
//   脸颊弧 cheeks #d7e0e5 w3 (原始 Vector 61/62)
//   嘴 mouth   仅在需要时才画
// 坐标系 = 原始 frame 3904:1804 (181.16 × 247)。body 组 translate(0,51.99),
//         sprout 组 translate(74.21,0) —— 与 Figma 绝对坐标一致。
// -----------------------------------------------------------------------------

export const C = {
  body:'#fbfcfc', eye:'#454f58', muzzle:'#cdd7dd', brow:'#cdd7dd', browAngry:'#7c8b95',
  cheek:'#d7e0e5', sprout:'#20937a', sproutLine:'#fbfcfc',
  blush:'#f4b3bd', heart:'#f0808f', tear:'#7fb4dc', sweat:'#8fbfe0',
  anger:'#e0645f', zzz:'#9fb0ba', glitchA:'#ff5d73', glitchB:'#3ad0c8',
};

export const VB = { w: 181.16, h: 247 };
const BODY_DY = 51.99, SPROUT_DX = 74.21;

// 真实脸部锚点 (body-local space, 与 src/body.svg 一致) -----------------------
const F = {
  Lx: 75.71, Rx: 122.71, eyeY: 66.51, eyeR: 4.5,
  bLx: 76.21, bRx: 122.21, browY: 56.01, browR: 2,
  cx: 99.2, mouthY: 84,
};
const n = (x) => Math.round(x * 1000) / 1000;

// ---- 原始 body (silhouette + 渐变阴影 + 脚)，脸部已剥离 ----------------------
export function bodyBase() {
  return `
  <g id="feet" stroke="${C.body}" stroke-width="27.0922" stroke-linecap="round" fill="none">
    <path d="M100.336 186.044C108.371 171.355 109.076 126.009 109.076 126.009"/>
    <path d="M73.3719 185.949C86.4027 168.308 89.414 143.511 89.414 143.511"/>
  </g>
  <g id="silhouette">
    <path d="M90.5801 0.0662C-12.2899 4.0094 -12.7898 120.011 17.2101 156.011C47.2101 192.011 124.21 190.113 156.21 163.01C207.233 119.796 177.375 -3.2608 90.5801 0.0662Z" fill="${C.body}"/>
    <path d="M90.5801 0.0662C-12.2899 4.0094 -12.7898 120.011 17.2101 156.011C47.2101 192.011 124.21 190.113 156.21 163.01C207.233 119.796 177.375 -3.2608 90.5801 0.0662Z" fill="url(#piboShade)"/>
  </g>`;
}
export function sproutBase() {
  return `
  <g id="sprout">
    <path d="M24.5767 36.2741C29.9482 41.6456 24.4296 49.4329 21.8514 65.183C21.5987 66.7269 19.7357 67.1063 19.0561 65.6972C16.0119 59.3857 11.3356 47.9393 9.07182 39.2075C7.07366 31.5003 15.3575 24.9597 9.07181 22.4454C-1.22022 18.3286 3.02576 9.80253 0.207244 3.3838C-0.448379 1.89072 0.524983 -0.385685 2.09475 0.0558334C12.2876 2.92271 12.4507 14.2249 21.2241 15.3216C44.6912 18.2549 16.1957 27.8931 24.5767 36.2741Z" fill="${C.sprout}"/>
    <path d="M2.78601 2.75C9.90989 7.77862 7.39558 16.9485 17.0338 20.3502C24.5418 23.0001 17.0338 28.3122 15.7766 34.5979C14.2973 41.9944 22.4815 45.1259 20.3862 63.0935" stroke="${C.sproutLine}" stroke-width="0.838" stroke-linecap="round" fill="none"/>
  </g>`;
}

// ---- 脸部部件 (真实锚点/尺寸) ------------------------------------------------
function brows(kind) {
  if (kind === 'none') return '';
  const { bLx, bRx, browY, browR } = F;
  if (kind === 'flat')
    return `<circle cx="${bLx}" cy="${browY}" r="${browR}" fill="${C.brow}"/><circle cx="${bRx}" cy="${browY}" r="${browR}" fill="${C.brow}"/>`;
  if (kind === 'raised') {
    const y = browY - 4;
    return `<circle cx="${bLx + 1}" cy="${y}" r="${browR}" fill="${C.brow}"/><circle cx="${bRx - 1}" cy="${y}" r="${browR}" fill="${C.brow}"/>`;
  }
  if (kind === 'angry') // 外高内低 → 怒
    return `<path d="M68,54.5 L84,58.5" stroke="${C.browAngry}" stroke-width="2.6" stroke-linecap="round"/>
            <path d="M130.42,54.5 L114.42,58.5" stroke="${C.browAngry}" stroke-width="2.6" stroke-linecap="round"/>`;
  if (kind === 'sad') // 内高外低 → 八字
    return `<path d="M68,58.5 L84,54.5" stroke="${C.browAngry}" stroke-width="2.6" stroke-linecap="round"/>
            <path d="M130.42,58.5 L114.42,54.5" stroke="${C.browAngry}" stroke-width="2.6" stroke-linecap="round"/>`;
  return '';
}

function oneEye(side, kind) {
  const cx = side < 0 ? F.Lx : F.Rx, cy = F.eyeY, r = F.eyeR;
  const s = (a) => n(cx + side * a); // mirror x
  switch (kind) {
    case 'dot':  return `<circle cx="${cx}" cy="${cy}" r="${r}" fill="${C.eye}"/>`;
    case 'wide': return `<circle cx="${cx}" cy="${cy}" r="5.6" fill="${C.eye}"/><circle cx="${n(cx-1.8)}" cy="${cy-1.9}" r="1.7" fill="#fff"/>`;
    case 'sparkle': return `<circle cx="${cx}" cy="${cy}" r="5" fill="${C.eye}"/><path d="M${cx},${cy-3.2} L${cx+1},${cy-1} L${cx+3.2},${cy} L${cx+1},${cy+1} L${cx},${cy+3.2} L${cx-1},${cy+1} L${cx-3.2},${cy} L${cx-1},${cy-1} Z" fill="#fff"/>`;
    case 'happy': return `<path d="M${cx-5.5},${cy+1.5} Q${cx},${cy-5} ${cx+5.5},${cy+1.5}" fill="none" stroke="${C.eye}" stroke-width="2.4" stroke-linecap="round"/>`;
    case 'sleep': return `<path d="M${cx-5.5},${cy-1} Q${cx},${cy+4.5} ${cx+5.5},${cy-1}" fill="none" stroke="${C.eye}" stroke-width="2.4" stroke-linecap="round"/>`;
    case 'half':  return `<path d="M${cx-4.5},${cy} A4.5,4.5 0 0 0 ${cx+4.5},${cy} Z" fill="${C.eye}"/><path d="M${cx-5.8},${cy-0.4} L${cx+5.8},${cy-0.4}" stroke="${C.eye}" stroke-width="2" stroke-linecap="round"/>`;
    case 'squeeze': return `<path d="M${s(-5)},${cy-5} L${s(3)},${cy} L${s(-5)},${cy+5}" fill="none" stroke="${C.eye}" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>`;
    case 'x':     return `<path d="M${cx-4},${cy-4} L${cx+4},${cy+4} M${cx+4},${cy-4} L${cx-4},${cy+4}" stroke="${C.eye}" stroke-width="2.4" stroke-linecap="round"/>`;
    case 'spiral':return `<path d="M${cx},${cy} m0,-4.6 a4.6,4.6 0 1 1 -3.2,1.4 a2.6,2.6 0 1 1 1.8,-0.8" fill="none" stroke="${C.eye}" stroke-width="1.8" stroke-linecap="round"/>`;
    case 'heart': return `<path d="M${cx},${cy+4} C${cx-4.6},${cy-0.6} ${cx-3.8},${cy-5.4} ${cx},${cy-2.4} C${cx+3.8},${cy-5.4} ${cx+4.6},${cy-0.6} ${cx},${cy+4} Z" fill="${C.heart}"/>`;
    default:      return `<circle cx="${cx}" cy="${cy}" r="${r}" fill="${C.eye}"/>`;
  }
}
function eyes(kind) { return oneEye(-1, kind) + oneEye(1, kind); }

// 原始海豹鼻 Union path (常驻)
function muzzle(show) {
  if (!show) return '';
  return `<path d="M105.71 63.0094C109.852 63.0094 113.21 66.3673 113.21 70.5094C113.21 74.6516 109.852 78.0094 105.71 78.0094C103.735 78.0094 101.939 77.2455 100.599 75.9973C100.112 75.5431 99.3082 75.5431 98.8209 75.9973C97.4817 77.2455 95.6853 78.0094 93.7101 78.0094C89.568 78.0094 86.2101 74.6516 86.2101 70.5094C86.2101 66.3673 89.568 63.0094 93.7101 63.0094C95.6852 63.0094 97.4817 63.773 98.821 65.0209C99.3083 65.475 100.112 65.475 100.599 65.0209C101.939 63.773 103.735 63.0094 105.71 63.0094Z" fill="${C.muzzle}"/>`;
}

// 原始脸颊弧 Vector 61/62
function cheeks(kind) {
  if (kind === 'none') return '';
  const curls = `<path d="M59.3781 86.6812C64.0892 93.1218 63.1534 101.663 56.0228 102.104C48.4538 102.572 41.9795 95.892 40.1778 86.8104" stroke="${C.cheek}" stroke-width="3" stroke-linecap="round" fill="none"/>
                 <path d="M138.787 86.8332C136.068 94.4085 139.411 102.405 146.435 100.796C153.891 99.0881 158.248 90.7781 157.399 81.4781" stroke="${C.cheek}" stroke-width="3" stroke-linecap="round" fill="none"/>`;
  if (kind === 'blush')
    return curls + `<ellipse cx="60" cy="78" rx="7" ry="4" fill="${C.blush}" opacity="0.7"/><ellipse cx="138" cy="78" rx="7" ry="4" fill="${C.blush}" opacity="0.7"/>`;
  return curls;
}

function mouth(kind) {
  const y = F.mouthY, cx = F.cx;
  switch (kind) {
    case 'none':  return '';
    case 'smile': return `<path d="M${cx-8},${y-2} Q${cx},${y+5} ${cx+8},${y-2}" fill="none" stroke="${C.eye}" stroke-width="2.2" stroke-linecap="round"/>`;
    case 'frown': return `<path d="M${cx-8},${y+3} Q${cx},${y-4} ${cx+8},${y+3}" fill="none" stroke="${C.eye}" stroke-width="2.2" stroke-linecap="round"/>`;
    case 'wavy':  return `<path d="M${cx-8},${y} Q${cx-4},${y-4} ${cx},${y} T${cx+8},${y}" fill="none" stroke="${C.eye}" stroke-width="2" stroke-linecap="round"/>`;
    case 'open':  return `<path d="M${cx-8},${y-3} Q${cx},${y-5} ${cx+8},${y-3} Q${cx+6},${y+7} ${cx},${y+8} Q${cx-6},${y+7} ${cx-8},${y-3} Z" fill="${C.eye}"/><path d="M${cx-4},${y+3} Q${cx},${y+8} ${cx+4},${y+3} Z" fill="${C.heart}"/>`;
    case 'o':     return `<ellipse cx="${cx}" cy="${y+1}" rx="3.4" ry="4.4" fill="${C.eye}"/>`;
    case 'cat':   return `<path d="M${cx-8},${y-2} Q${cx-4},${y+4} ${cx},${y-2} Q${cx+4},${y+4} ${cx+8},${y-2}" fill="none" stroke="${C.eye}" stroke-width="2" stroke-linecap="round"/>`;
    default:      return '';
  }
}

function extras(list = []) {
  let out = '';
  for (const e of list) {
    if (e === 'zzz')
      out += `<g fill="${C.zzz}" font-family="Verdana, sans-serif" font-weight="700">
                <text x="140" y="32" font-size="9">z</text>
                <text x="149" y="20" font-size="12">Z</text>
                <text x="161" y="5" font-size="16">Z</text></g>`;
    else if (e === 'anger')
      out += `<g stroke="${C.anger}" stroke-width="2.6" stroke-linecap="round" fill="none">
                <path d="M146,20 l8,0 M150,16 l0,8"/><path d="M143,28 l5,-5 M143,23 l5,5" stroke-width="2"/></g>`;
    else if (e === 'sweat')
      out += `<path d="M150,52 C154,58 156,62 152,64 C148,62 146,58 150,52 Z" fill="${C.sweat}" opacity="0.9"/>`;
    else if (e === 'tear')
      out += `<path d="M72,72 C75,79 77,84 73,86 C69,84 68,79 72,72 Z" fill="${C.tear}"/>`;
    else if (e === 'hearts')
      out += `<g fill="${C.heart}"><path d="M150,26 c-3.6,-3.6 -2.7,-8 0.9,-5.4 c3.6,-2.6 4.5,1.8 0.9,5.4 Z" opacity="0.9"/>
                <path d="M36,52 c-2.8,-2.8 -1.9,-6.4 0.9,-4.2 c2.8,-2 3.7,1.4 0.9,4.2 Z" opacity="0.7"/></g>`;
    else if (e === 'sparkle')
      out += `<g fill="#ffd45e"><path d="M40,58 l1.5,3 3,1.5 -3,1.5 -1.5,3 -1.5,-3 -3,-1.5 3,-1.5 Z"/>
                <path d="M152,42 l1.1,2.2 2.2,1.1 -2.2,1.1 -1.1,2.2 -1.1,-2.2 -2.2,-1.1 2.2,-1.1 Z"/></g>`;
    else if (e === 'glitch')
      out += `<g opacity="0.85"><rect x="55" y="64" width="26" height="3.2" fill="${C.glitchA}" opacity="0.6"/>
                <rect x="112" y="68" width="22" height="2.8" fill="${C.glitchB}" opacity="0.6"/>
                <rect x="70" y="66" width="58" height="1.4" fill="#fff" opacity="0.5"/></g>`;
  }
  return out;
}

// ---- compose -----------------------------------------------------------------
export function faceGroup(cfg) {
  return `<g id="face">
    ${brows(cfg.brows ?? 'flat')}
    ${eyes(cfg.eyes ?? 'dot')}
    ${muzzle(cfg.muzzle ?? true)}
    ${cheeks(cfg.cheeks ?? 'default')}
    ${mouth(cfg.mouth ?? 'none')}
    ${extras(cfg.extras)}
  </g>`;
}

export function buildSVG(cfg, opts = {}) {
  const { bg = true, size = null } = opts;
  const dim = size ? `width="${size}" height="${Math.round(size * VB.h / VB.w)}"` : '';
  const bgRect = bg
    ? `<rect x="0" y="0" width="${VB.w}" height="${VB.h}" rx="22" fill="${cfg.bg ?? '#cde9de'}"/>`
    : '';
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${VB.w} ${VB.h}" ${dim} role="img" aria-label="Pibo ${cfg.name}">
  <title>Pibo · ${cfg.name}${cfg.zh ? ' / ' + cfg.zh : ''}</title>
  <defs>
    <linearGradient id="piboShade" x1="95.4116" y1="94.4747" x2="59.9674" y2="152.474" gradientUnits="userSpaceOnUse">
      <stop stop-color="#ffffff" stop-opacity="0"/><stop offset="1" stop-color="#ffffff"/>
    </linearGradient>
  </defs>
  ${bgRect}
  <g transform="translate(${SPROUT_DX},0)">${sproutBase()}</g>
  <g transform="translate(0,${BODY_DY})">
    ${bodyBase()}
    ${faceGroup(cfg)}
  </g>
</svg>`;
}
