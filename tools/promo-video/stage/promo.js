// OmniVibe promo timeline. Every visual is a pure function of time t (seconds),
// so frames render deterministically. Config (strings, assets, timing) comes from config.js.
const C = window.PROMO, T = C.text, EV = C.timeline.events, SC = C.timeline.scenes;
const root = document.getElementById('root');
if (C.lang === 'zh') document.body.classList.add('zh');

// ---------- helpers ----------
const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const lerp = (a, b, p) => a + (b - a) * p;
const E = {
  lin: p => p,
  out: p => 1 - Math.pow(1 - p, 3),
  out5: p => 1 - Math.pow(1 - p, 5),
  inOut: p => (p < .5 ? 4 * p * p * p : 1 - Math.pow(-2 * p + 2, 3) / 2),
  in: p => p * p * p,
  back: p => { const c1 = 1.70158, c3 = c1 + 1; return 1 + c3 * Math.pow(p - 1, 3) + c1 * Math.pow(p - 1, 2); },
};
const prog = (t, a, b, e = E.out) => e(clamp((t - a) / (b - a)));
// Opacity window: fade in over [a, a+fi], out over [b-fo, b].
const win = (t, a, b, fi = .35, fo = .35) => Math.min(prog(t, a, a + fi, E.out), 1 - prog(t, b - fo, b, E.in));
function el(tag, cls, parent = root, html = '') { const e = document.createElement(tag); if (cls) e.className = cls; if (html) e.innerHTML = html; parent.appendChild(e); return e; }
function scene() { const s = el('div', 'scene'); return s; }
function css(e, o) { for (const k in o) e.style[k] = o[k]; }
function setT(e, x, y, s = 1, r = 0) { e.style.transform = `translate(${x}px, ${y}px) rotate(${r}deg) scale(${s})`; }
const rand = (() => { let s = 1234567; return () => (s = (s * 16807) % 2147483647) / 2147483647; })();
const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;');

function terminal(parent, title, lines, opts = {}) {
  const w = el('div', 'term', parent);
  const bar = el('div', 'bar', w); const tab = el('div', 'tab', bar, `<i></i><span>${esc(title)}</span>`);
  el('div', 'ctl', w, '—&nbsp;&nbsp;&nbsp;☐&nbsp;&nbsp;&nbsp;✕');
  const body = el('div', 'body', w, lines.join('\n'));
  if (opts.warn) el('div', 'warn', w, opts.warn);
  if (opts.w) css(w, { width: opts.w + 'px', height: opts.h + 'px' });
  w.titleSpan = tab.querySelector('span'); w.bodyDiv = body;
  return w;
}
function keycaps(parent, parts, label) {
  const k = el('div', 'keys', parent); const caps = [];
  if (label) el('span', 'keylabel', k, label);
  parts.forEach((p, i) => { if (i) el('span', 'plus', k, '+'); caps.push(el('div', 'key', k, esc(p))); });
  k.caps = caps; return k;
}
function cursorEl(parent) {
  const c = el('div', 'cursor', parent, `<svg width="34" height="44" viewBox="0 0 34 44"><path d="M3 2 L3 34 L11 27 L17 41 L23 38 L17 25 L28 25 Z" fill="#fff" stroke="#111" stroke-width="2.2" stroke-linejoin="round"/></svg>`);
  return c;
}
function preload(srcs) { return srcs.map(s => { const i = new Image(); i.src = s; return i; }); }
// Sequence player: a stack of <img> where only one is visible.
function sequence(parent, srcs, style) {
  const box = el('div', 'abs', parent); css(box, style);
  const imgs = srcs.map(s => { const i = el('img', 'abs', box); i.src = s; css(i, { left: 0, top: 0, width: '100%', visibility: 'hidden' }); return i; });
  box.show = n => { n = Math.max(0, Math.min(imgs.length - 1, n)); if (box.cur !== n) { if (box.cur !== undefined) imgs[box.cur].style.visibility = 'hidden'; imgs[n].style.visibility = 'visible'; box.cur = n; } };
  return box;
}

// ---------- shared content ----------
const tasks = T.tasks; // six task names
function sessionLines(kind, i) {
  const P = T.prompts;
  const sets = [
    [`<span class="c-dim">&gt;</span> <span class="c-w">${esc(P[0])}</span>`, '', `<span class="c-g">●</span> Read(<span class="c-b">src/checkout/form.tsx</span>)`, `<span class="c-g">●</span> Update(<span class="c-b">src/checkout/validate.ts</span>)`, `  <span class="c-dim">⎿  Updated with 12 additions and 4 removals</span>`, '', `<span class="c-o">✻</span> <span class="c-o">Thinking…</span> <span class="c-dim">(esc to interrupt)</span>`],
    [`<span class="c-dim">›</span> <span class="c-w">${esc(P[1])}</span>`, '', `<span class="c-g">•</span> Ran <span class="c-y">pnpm test --filter api</span>`, `  <span class="c-dim">└ 128 passed, 3 failed</span>`, `<span class="c-g">•</span> Editing <span class="c-b">api/webhooks/stripe.ts</span>`, `  <span class="c-g">+ verifySignature(payload, header)</span>`, `  <span class="c-r">- // TODO: verify</span>`],
    [`<span class="c-dim">&gt;</span> <span class="c-w">${esc(P[2])}</span>`, '', `<span class="c-g">●</span> Bash(<span class="c-y">npx playwright test</span>)`, `  <span class="c-dim">⎿  Running 47 tests using 6 workers</span>`, `  <span class="c-g">✓</span> checkout.spec.ts (12)`, `  <span class="c-r">✘</span> refunds.spec.ts › partial refund`, `<span class="c-o">✻</span> <span class="c-o">Investigating flaky test…</span>`],
    [`<span class="c-dim">›</span> <span class="c-w">${esc(P[3])}</span>`, '', `<span class="c-g">•</span> Reading <span class="c-b">CHANGELOG.md</span>`, `<span class="c-g">•</span> Drafting release notes for <span class="c-y">v0.2.0</span>`, `  <span class="c-dim">└ 14 merged PRs grouped by area</span>`, ``, `<span class="c-dim">◦ Working (42s · esc to interrupt)</span>`],
    [`<span class="c-dim">PS D:\\work\\infra&gt;</span> <span class="c-w">terraform plan</span>`, `<span class="c-dim">Refreshing state...</span>`, ``, `<span class="c-g">  + aws_ecs_service.web</span>`, `<span class="c-y">  ~ aws_lb_listener.https</span>`, ``, `<span class="c-w">Plan:</span> 1 to add, 1 to change, 0 to destroy.`],
    [`<span class="c-dim">&gt;</span> <span class="c-w">${esc(P[5])}</span>`, '', `<span class="c-g">●</span> Bash(<span class="c-y">pnpm db:migrate</span>)`, `  <span class="c-r">⎿  Error: relation "orders_v2" already exists</span>`, '', `<span class="c-g">●</span> Read(<span class="c-b">db/migrations/0042_orders.sql</span>)`, `<span class="c-o">✻</span> <span class="c-o">Thinking…</span>`],
  ];
  return sets[i % sets.length];
}

// ---------- background dust ----------
const dust = document.getElementById('dust');
const motes = Array.from({ length: 46 }, () => ({ x: rand() * 1920, y: rand() * 1080, s: .4 + rand() * 1.1, v: 6 + rand() * 18, ph: rand() * 6.28, d: el('div', 'dot', dust) }));
function updateDust(t) {
  const strength = Math.max(win(t, 0, 13.2, 1, .6) * .5, win(t, 8.9, 13.2, .2, .6), win(t, 52.8, 60, .6, .8));
  dust.style.opacity = strength;
  for (const m of motes) setT(m.d, (m.x + Math.sin(t * .4 + m.ph) * 30) % 1920, (m.y - t * m.v + 2160) % 1080, m.s * (.7 + .3 * Math.sin(t * 2 + m.ph)));
}
const grain = document.getElementById('grain');

// ================= S1 + S2: chaos and Alt+Tab =================
const S1 = scene();
const chaosWins = [];
const spots = [[90, 70], [620, 40], [1130, 90], [250, 330], [800, 300], [1180, 400], [60, 600], [560, 560], [1080, 640]];
const chaosTitles = T.chaosTitles;
spots.forEach(([x, y], i) => {
  const w = terminal(S1, chaosTitles[i], sessionLines('', i), i === 7 ? { warn: T.waitingPrompt } : {});
  w.base = { x, y, r: (rand() - .5) * 3 };
  chaosWins.push(w);
});
const h1a = el('div', 'h1 abs', S1, esc(T.hook1)); css(h1a, { left: '0', width: '1920px', textAlign: 'center', top: '420px' });
const h1b = el('div', 'h1 abs gold', S1, esc(T.hook2)); css(h1b, { left: '0', width: '1920px', textAlign: 'center', top: '520px' });
const scrim1 = el('div', 'abs', S1); css(scrim1, { inset: 0, background: 'radial-gradient(1100px 520px at 50% 50%, rgba(8,7,6,.86), rgba(8,7,6,.35))' });
S1.appendChild(h1a); S1.appendChild(h1b);
// Alt-Tab switcher
const switcher = el('div', 'abs', S1); css(switcher, { left: '210px', top: '400px', width: '1500px', height: '250px', borderRadius: '18px', background: 'rgba(28,27,24,.92)', border: '1px solid #4a4436', boxShadow: '0 40px 120px rgba(0,0,0,.7)', backdropFilter: 'blur(14px)' });
const thumbs = [];
for (let i = 0; i < 7; i++) {
  const th = el('div', 'abs', switcher); css(th, { left: 40 + i * 205 + 'px', top: '40px', width: '185px', height: '170px', borderRadius: '10px', border: '2px solid transparent' });
  const mini = el('div', 'abs', th); css(mini, { left: '8px', top: '8px', width: '165px', height: '110px', background: '#0d0d0e', borderRadius: '6px', border: '1px solid #3a3833', overflow: 'hidden' });
  for (let l = 0; l < 6; l++) { const ln = el('div', 'abs', mini); css(ln, { left: '10px', top: 16 + l * 14 + 'px', height: '5px', width: 40 + rand() * 100 + 'px', borderRadius: '3px', background: ['#4d6b4a', '#4e4a40', '#3e5a7a', '#6b5536'][l % 4] }); }
  const lab = el('div', 'abs', th, esc(chaosTitles[i % chaosTitles.length])); css(lab, { left: '8px', top: '128px', width: '170px', font: '15px "Segoe UI", NotoSansSC', color: '#cfc7b4', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' });
  thumbs.push(th);
}
const altKeys = keycaps(S1, ['Alt', 'Tab']); css(altKeys, { left: '760px', top: '760px' });
const altCount = el('div', 'abs h2', S1); css(altCount, { left: '1110px', top: '772px', fontSize: '40px', fontWeight: '700', color: '#E3C27E' });
const altText = el('div', 'h1 abs', S1, esc(T.altTab)); css(altText, { left: '0', width: '1920px', textAlign: 'center', top: '290px', fontSize: '60px' });

function updateChaos(t) {
  const on = t < SC.brand[0] + .25;
  S1.style.opacity = on ? 1 : 0; if (!on) return;
  const collapse = prog(t, 8.55, 9.1, E.in);
  chaosWins.forEach((w, i) => {
    const a = EV.windowPops[i];
    const p = prog(t, a, a + .35, E.back), o = prog(t, a, a + .2);
    const drift = Math.sin(t * .5 + i) * 6;
    let x = w.base.x + drift, y = w.base.y + (1 - p) * 30, s = .9 + .1 * p;
    // Alt-Tab: windows jitter forward as focus cycles.
    let z = i;
    const presses = EV.altTab.filter(k => t >= k).length;
    if (presses) { z = (i + presses * 3) % 9 === 8 ? 20 : i; }
    if (collapse > 0) { x = lerp(x, 960 - 360, collapse); y = lerp(y, 540 - 210, collapse); s *= lerp(1, .06, collapse); }
    w.style.opacity = o * (1 - prog(t, 8.85, 9.1));
    w.style.zIndex = z;
    w.style.filter = `blur(${prog(t, 8.3, 8.8) * 6}px) brightness(${1 - .45 * win(t, 1.0, 5.6, .6, .6)})`;
    setT(w, x, y, s, w.base.r * (1 - collapse));
  });
  scrim1.style.opacity = Math.max(win(t, 1.0, 5.8, .5, .5), win(t, 6.05, 8.75, .25, .25)); scrim1.style.zIndex = 30;
  h1a.style.zIndex = h1b.style.zIndex = 31;
  h1a.style.opacity = win(t, 1.1, 5.8, .5, .45); setT(h1a, 0, (1 - prog(t, 1.1, 1.8)) * 24);
  h1b.style.opacity = win(t, 3.2, 5.8, .5, .45); setT(h1b, 0, (1 - prog(t, 3.2, 3.9)) * 24);
  // chip pulse on the hidden waiting window
  const warn = chaosWins[7].querySelector('.warn');
  warn.style.boxShadow = `0 0 ${18 + 14 * Math.sin(t * 7)}px rgba(240,190,90,${.55 * prog(t, EV.waitingChip, EV.waitingChip + .3)})`;
  // Alt-Tab overlay
  const sw = win(t, 6.1, 8.75, .2, .25);
  switcher.style.opacity = sw; switcher.style.zIndex = 40; setT(switcher, 0, (1 - prog(t, 6.1, 6.4)) * 20, .96 + .04 * prog(t, 6.1, 6.4));
  const presses = EV.altTab.filter(k => t >= k).length;
  thumbs.forEach((th, i) => th.style.borderColor = i === presses % 7 ? '#E3C27E' : 'transparent');
  altKeys.style.opacity = sw; altKeys.style.zIndex = 41; altCount.style.zIndex = 41; altText.style.zIndex = 41;
  const pressing = EV.altTab.some(k => t >= k && t < k + .12);
  altKeys.caps[0].classList.toggle('down', t >= 6.15 && t < 8.6);
  altKeys.caps[1].classList.toggle('down', pressing);
  altCount.textContent = presses ? '× ' + (presses * 2 + 1) : ''; altCount.style.opacity = sw;
  altText.style.opacity = win(t, 6.4, 8.7, .3, .25);
}

// ================= S3: brand =================
const S3 = scene();
const glow = el('div', 'abs', S3); css(glow, { left: '460px', top: '40px', width: '1000px', height: '1000px', borderRadius: '50%', background: 'radial-gradient(circle, rgba(233,201,129,.28) 0%, rgba(233,201,129,.08) 35%, transparent 70%)' });
const ringSvg = el('div', 'abs', S3, `<svg width="560" height="560" viewBox="0 0 560 560"><circle cx="280" cy="280" r="250" fill="none" stroke="#E9C981" stroke-width="2.5" stroke-dasharray="1571" stroke-dashoffset="1571" id="ringPath" opacity=".85"/><circle cx="280" cy="280" r="268" fill="none" stroke="#E9C981" stroke-width="1" stroke-dasharray="4 10" opacity=".35" id="ringDots"/></svg>`);
css(ringSvg, { left: '680px', top: '60px' });
const icon = el('img', 'abs', S3); icon.src = C.assets.icon; css(icon, { left: '810px', top: '190px', width: '300px', height: '300px' });
const word = el('div', 'abs', S3, 'OmniVibe'); css(word, { left: 0, width: '1920px', textAlign: 'center', top: '600px', fontSize: '128px', fontWeight: '700', color: '#F6EEDB', letterSpacing: '.02em' });
const tag = el('div', 'abs serif', S3, esc(T.tagline)); css(tag, { left: 0, width: '1920px', textAlign: 'center', top: '770px', fontSize: '50px', color: '#E3C27E', fontWeight: '600' });
const sub = el('div', 'abs h2', S3, esc(T.brandSub)); css(sub, { left: 0, width: '1920px', textAlign: 'center', top: '860px', fontSize: '30px' });
const burst = Array.from({ length: 28 }, (_, i) => ({ a: i / 28 * 6.283 + rand() * .2, sp: 280 + rand() * 360, d: el('div', 'dot', S3) }));
function updateBrand(t) {
  const [a, b] = SC.brand; const on = t > a - .4 && t < b + .1;
  S3.style.opacity = on ? 1 - prog(t, b - .45, b, E.in) : 0; if (!on) return;
  const z = 1 + .04 * prog(t, a, b, E.lin);
  S3.style.transform = `scale(${z})`;
  glow.style.opacity = prog(t, a - .05, a + .4) * (.8 + .2 * Math.sin(t * 2));
  document.getElementById('ringPath').setAttribute('stroke-dashoffset', 1571 * (1 - prog(t, a - .1, a + .7, E.inOut)));
  document.getElementById('ringDots').style.opacity = .35 * prog(t, a + .4, a + 1);
  ringSvg.style.transform = `rotate(${(t - a) * 6}deg)`;
  const ip = prog(t, a + .05, a + .65, E.back);
  icon.style.opacity = prog(t, a + .05, a + .3); icon.style.transform = `scale(${.55 + .45 * ip})`;
  icon.style.filter = `drop-shadow(0 0 ${40 * prog(t, a, a + .5)}px rgba(240,190,90,.45))`;
  const wp = prog(t, a + .5, a + 1.3, E.out5);
  word.style.opacity = wp; word.style.letterSpacing = lerp(.35, .02, wp) + 'em';
  tag.style.opacity = prog(t, a + 1.35, a + 1.9); setT(tag, 0, (1 - prog(t, a + 1.35, a + 2)) * 18);
  sub.style.opacity = prog(t, a + 2.0, a + 2.6); setT(sub, 0, (1 - prog(t, a + 2.0, a + 2.7)) * 18);
  burst.forEach(p => { const q = prog(t, a, a + 1.6, E.out); setT(p.d, 960 + Math.cos(p.a) * p.sp * q, 340 + Math.sin(p.a) * p.sp * q, 1.4 * (1 - q)); p.d.style.opacity = (1 - q) * (t >= a ? 1 : 0); });
}

// ================= S4: capture =================
const DECK = { left: 1060, top: 142, scale: .75, cx: 1405, cy: 524.5, r: 240 };
const slotPos = n => { const th = (n - 1) * 40 * Math.PI / 180; return [DECK.cx + DECK.r * Math.sin(th), DECK.cy - DECK.r * Math.cos(th)]; };
const S4 = scene();
const deckBox = el('div', 'abs', S4); css(deckBox, { left: DECK.left + 'px', top: DECK.top + 'px', width: 920 * DECK.scale + 'px', height: 1060 * DECK.scale + 'px' });
const fills = C.assets.fill.map(src => { const i = el('img', 'abs', deckBox); i.src = src; css(i, { left: 0, top: 0, width: '100%', opacity: 0 }); return i; });
const capTitle = el('div', 'h1 abs', S4, esc(T.captureTitle)); css(capTitle, { left: '140px', top: '150px', width: '900px' });
const capSub = el('div', 'h2 abs', S4, esc(T.captureSub)); css(capSub, { left: '140px', top: '250px', width: '860px' });
const capSub2 = el('div', 'h2 abs gold', S4, esc(T.captureDone)); css(capSub2, { left: '140px', top: '250px', width: '860px' });
const capCards = tasks.map((name, i) => { const w = terminal(S4, name, sessionLines('', i), { w: 400, h: 230 }); w.bodyDiv.style.fontSize = '12px'; w.base = { x: 150 + (i % 3) * 60 + Math.floor(i / 3) * 360, y: 420 + (i % 3) * 120 }; return w; });
const capFlash = Array.from({ length: 6 }, () => el('div', 'ring', S4));
const cur4 = cursorEl(S4);
function updateCapture(t) {
  const [a, b] = SC.capture; const on = t > a - .1 && t < b + .4;
  S4.style.opacity = on ? 1 : 0; if (!on) return;
  const caps = EV.captures;
  const filled = caps.filter(c => t >= c + .05).length;
  const deckIn = prog(t, a, a + .6);
  fills.forEach((im, k) => { im.style.opacity = (k === filled ? 1 : 0) * deckIn * (1 - prog(t, b - .2, b + .25)); });
  if (filled > 0 && t < caps[filled - 1] + .2) { const pf = prog(t, caps[filled - 1] + .05, caps[filled - 1] + .2); fills[filled - 1].style.opacity = (1 - pf) * deckIn; fills[filled].style.opacity = pf * deckIn; }
  deckBox.style.transform = `scale(${.92 + .08 * deckIn})`;
  capTitle.style.opacity = win(t, a + .2, b, .5, .4); setT(capTitle, 0, (1 - prog(t, a + .2, a + .9)) * 26);
  capSub.style.opacity = win(t, a + .6, caps[5] + .4, .5, .3);
  capSub2.style.opacity = win(t, caps[5] + .45, b, .4, .4);
  let cx = 1700, cy = 980, cvis = 0, down = false;
  capCards.forEach((w, i) => {
    const c = caps[i], s0 = c - .6;
    const appear = prog(t, a + .3 + i * .1, a + .7 + i * .1);
    const f = prog(t, s0, c, E.inOut);
    const [tx, ty] = slotPos(i + 1);
    const sx = w.base.x, sy = w.base.y;
    const mx = lerp(sx, tx - 200, .5), my = Math.min(sy, ty) - 180;
    const x = (1 - f) * (1 - f) * sx + 2 * (1 - f) * f * mx + f * f * (tx - 200);
    const y = (1 - f) * (1 - f) * sy + 2 * (1 - f) * f * my + f * f * (ty - 115);
    const s = lerp(1, .16, prog(t, s0 + .15, c, E.in));
    w.style.opacity = appear * (1 - prog(t, c - .12, c));
    w.style.zIndex = t > s0 ? 20 : i;
    setT(w, x, y, s);
    if (t > s0 - .35 && t < c + .1) { cvis = 1; const grab = prog(t, s0 - .35, s0, E.inOut); cx = lerp(1700, sx + 120, grab); cy = lerp(980, sy + 18, grab); if (t >= s0) { cx = x + 120 * s + 200 * (1 - s); cy = y + 18 + 97 * (1 - s); down = true; } }
    const fl = capFlash[i]; const fp = prog(t, c, c + .55);
    css(fl, { left: tx - 10 - 60 * fp + 'px', top: ty - 10 - 60 * fp + 'px', width: 20 + 120 * fp + 'px', height: 20 + 120 * fp + 'px', opacity: t >= c ? (1 - fp) * .9 : 0 });
  });
  cur4.style.opacity = cvis; setT(cur4, cx, cy, down ? .9 : 1);
}

// ================= S5: switch (dock motion + radial) =================
const S5 = scene();
const stage = terminal(S5, tasks[0], sessionLines('', 0), { w: 820, h: 480 }); css(stage, { left: '120px', top: '400px' });
const sTitleA = el('div', 'h1 abs', S5, esc(T.switchA)); css(sTitleA, { left: '120px', top: '160px', width: '980px', fontSize: '64px' });
const sTitleB = el('div', 'h1 abs', S5, esc(T.switchB)); css(sTitleB, { left: '120px', top: '160px', width: '980px', fontSize: '64px' });
const sTitleC = el('div', 'h1 abs', S5, esc(T.radialTitle)); css(sTitleC, { left: '120px', top: '160px', width: '840px', fontSize: '64px' });
const sKeys = keycaps(S5, ['Alt', '3'], T.orPress); css(sKeys, { left: '120px', top: '275px' });
const qKeys = keycaps(S5, ['Alt', 'Q'], T.hold); css(qKeys, { left: '120px', top: '275px' });
const dockSeq = sequence(S5, C.assets.dock, { left: DECK.left + 'px', top: DECK.top + 'px', width: 920 * DECK.scale + 'px' });
const radialBox = el('div', 'abs', S5); css(radialBox, { left: '1010px', top: '200px', width: '846px', height: '612px', overflow: 'hidden', borderRadius: '22px', boxShadow: '0 40px 120px rgba(0,0,0,.7)', border: '1px solid #3d3628' });
const radialSeq = sequence(radialBox, C.assets.radial, { left: 0, top: '-72px', width: '846px' });
const cur5 = cursorEl(S5);
const dockFrameAt = s => { const tm = C.dockTiming; let lo = 0; for (let i = 0; i < tm.length; i++) if (tm[i].at <= s) lo = i; return lo; };
function updateSwitch(t) {
  const [a, b] = SC.switch; const on = t > a - .3 && t < b + .1;
  S5.style.opacity = on ? 1 - prog(t, b - .3, b, E.in) : 0; if (!on) return;
  const st = win(t, a + .1, b, .5, .3); stage.style.opacity = st; setT(stage, 0, (1 - prog(t, a + .1, a + .7)) * 30);
  const flip1 = EV.switchConfirm, flip2 = EV.radialRelease + .05;
  const which = t >= flip2 ? 1 : t >= flip1 ? 2 : 0;
  if (stage.cur !== which) { stage.cur = which; stage.titleSpan.textContent = tasks[which]; stage.bodyDiv.innerHTML = sessionLines('', which).join('\n'); }
  const fl = Math.max(win(t, flip1, flip1 + .35, .05, .3), win(t, flip2, flip2 + .35, .05, .3));
  stage.style.filter = `brightness(${1 + .5 * fl})`; stage.style.boxShadow = `0 30px 80px rgba(0,0,0,.55), 0 0 ${60 * fl}px rgba(233,201,129,${.6 * fl})`;
  sTitleA.style.opacity = win(t, a + .2, 22.9, .4, .3);
  sTitleB.style.opacity = win(t, 22.95, 26.7, .35, .3);
  sTitleC.style.opacity = win(t, 26.8, b, .35, .3);
  sKeys.style.opacity = win(t, 25.0, 26.7, .3, .3);
  sKeys.caps[0].classList.toggle('down', t > 25.35 && t < 25.8); sKeys.caps[1].classList.toggle('down', t > 25.45 && t < 25.8);
  qKeys.style.opacity = win(t, 26.9, b, .3, .3);
  const held = t > 27.0 && t < EV.radialRelease; qKeys.caps[0].classList.toggle('down', held); qKeys.caps[1].classList.toggle('down', held);
  // dock sequence
  const s = t - EV.dockMotionStart;
  dockSeq.show(dockFrameAt(Math.max(0, s)));
  dockSeq.style.opacity = (t < 26.9 ? 1 : 1 - prog(t, 26.6, 27.0)) * prog(t, a - .3, a + .1);
  // radial
  const rp = win(t, 26.85, b, .35, .3); radialBox.style.opacity = rp; radialBox.style.transform = `scale(${.94 + .06 * prog(t, 26.85, 27.3)})`;
  radialSeq.show(Math.round((t - EV.radialStart) * 30));
  // cursor path
  const [p2x, p2y] = slotPos(2), [p3x, p3y] = slotPos(3);
  const path = [[a, 1760, 980], [21.5, 1760, 980], [21.85, DECK.cx, DECK.cy], [22.7, DECK.cx, DECK.cy], [22.95, p2x, p2y], [23.6, p2x, p2y], [23.75, p3x, p3y], [25.2, p3x, p3y], [25.7, 1780, 960],
    [27.1, 1780, 960], [27.4, 1433, 459], [27.8, 1433, 459], [28.0, 1542, 329], [29.4, 1542, 329], [29.8, 1800, 980]];
  let px = 1760, py = 980;
  for (let i = 1; i < path.length; i++) { const [t0, x0, y0] = path[i - 1], [t1, x1, y1] = path[i]; if (t >= t0 && t <= t1) { const q = E.inOut((t - t0) / (t1 - t0)); px = lerp(x0, x1, q); py = lerp(y0, y1, q); break; } if (t > t1) { px = x1; py = y1; } }
  cur5.style.opacity = win(t, 21.3, 26.0, .2, .3) + win(t, 27.0, 29.9, .2, .2);
  const click = t > EV.switchConfirm - .12 && t < EV.switchConfirm + .08;
  setT(cur5, px - 4, py - 3, click ? .85 : 1);
}

// ================= S6: overview =================
const S6 = scene();
const INV = { left: 80, top: 46, w: 1760, h: 987 };
const camera = el('div', 'abs', S6); css(camera, { left: 0, top: 0, width: '1920px', height: '1080px', transformOrigin: '0 0' });
const inv = el('img', 'abs', camera); inv.src = C.assets.inventory; css(inv, { left: INV.left + 'px', top: INV.top + 'px', width: INV.w + 'px', borderRadius: '10px', boxShadow: '0 40px 140px rgba(0,0,0,.75)' });
const card2 = { x: INV.left + .343 * INV.w, y: INV.top + .107 * INV.h, w: .314 * INV.w, h: .411 * INV.h };
const glowCard = el('div', 'abs', camera); css(glowCard, { left: card2.x + 'px', top: card2.y + 'px', width: card2.w + 'px', height: card2.h + 'px', borderRadius: '6px', border: '3px solid #F0C46E' });
const leftShade = el('div', 'abs', S6); css(leftShade, { inset: 0, background: 'linear-gradient(90deg, rgba(8,7,6,.94) 0%, rgba(8,7,6,.85) 34%, rgba(8,7,6,0) 58%)' });
const oTitle = el('div', 'h1 abs', S6, esc(T.overviewTitle)); css(oTitle, { left: '110px', top: '390px', width: '880px', fontSize: '70px' });
const oSub = el('div', 'h2 abs', S6, esc(T.overviewSub)); css(oSub, { left: '120px', top: '560px', width: '760px', whiteSpace: 'pre-line' });
const tabKeys = keycaps(S6, ['Tab']); css(tabKeys, { left: '880px', top: '500px', transform: 'scale(1.6)' });
const chips = el('div', 'abs', S6, T.chips.map((c, i) => `<span class="chip" style="color:${['#9fd7a0', '#f3cf7f', '#cfe6b4', '#f39c8a'][i]}">${esc(c)}</span>`).join('')); css(chips, { left: 0, width: '1920px', textAlign: 'center', top: '988px' });
function updateOverview(t) {
  const [a, b] = SC.overview; const on = t > a - .1 && t < b + .1;
  S6.style.opacity = on ? 1 - prog(t, b - .3, b, E.in) : 0; if (!on) return;
  tabKeys.style.opacity = win(t, a, EV.tabKey + .45, .2, .25); tabKeys.style.zIndex = 5; tabKeys.caps[0].classList.toggle('down', t > EV.tabKey && t < EV.tabKey + .18);
  const ip = prog(t, EV.tabKey + .1, EV.tabKey + .6, E.out5);
  inv.style.opacity = ip;
  const zIn = prog(t, EV.waitingFocus - .2, EV.waitingFocus + .6, E.inOut), zOut = prog(t, 35.4, 36.1, E.inOut);
  const z = zIn * (1 - zOut);
  const base = lerp(.94 + .06 * ip, .88, zOut), by = lerp(540, 480, zOut);
  const s = lerp(base, 1.5, z);
  const ccx = card2.x + card2.w / 2, ccy = card2.y + card2.h / 2;
  const tx = lerp(960 - 960 * s, 1340 - ccx * s, z), ty = lerp(by - 540 * s, 520 - ccy * s, z);
  camera.style.transform = `translate(${tx}px, ${ty}px) scale(${s})`;
  glowCard.style.opacity = z * (.75 + .25 * Math.sin(t * 6));
  glowCard.style.boxShadow = `0 0 ${30 + 20 * Math.sin(t * 6)}px rgba(240,196,110,.6)`;
  leftShade.style.opacity = z; oTitle.style.opacity = win(t, EV.waitingFocus + .2, 35.5, .4, .3) ; oSub.style.opacity = win(t, EV.waitingFocus + .5, 35.5, .4, .3);
  setT(oTitle, (1 - prog(t, EV.waitingFocus + .2, EV.waitingFocus + .8)) * -30, 0);
  chips.style.opacity = win(t, 35.9, b, .35, .3); setT(chips, 0, (1 - prog(t, 35.9, 36.4)) * 20);
}

// ================= S7: arrange =================
const S7 = scene();
const desk = el('div', 'abs', S7); css(desk, { inset: 0, background: 'linear-gradient(160deg, #15130f, #0b0a08)' });
const arrWins = tasks.map((n, i) => { const w = terminal(S7, n, sessionLines('', i), { w: 700, h: 410 }); w.mess = { x: 120 + rand() * 1000, y: 60 + rand() * 420, r: (rand() - .5) * 2.5, s: .85 + rand() * .25 }; return w; });
const aKeys = keycaps(S7, ['Alt', '`']); css(aKeys, { left: '1500px', top: '950px' });
const aPill = el('div', 'pill', S7, esc(T.arrangeA)); css(aPill, { left: '120px', top: '952px' });
const aPill2 = el('div', 'pill', S7, esc(T.arrangeB)); css(aPill2, { left: '120px', top: '952px' });
function updateArrange(t) {
  const [a, b] = SC.arrange; const on = t > a - .1 && t < b + .1;
  S7.style.opacity = on ? prog(t, a - .1, a + .3) * (1 - prog(t, b - .3, b, E.in)) : 0; if (!on) return;
  const g = prog(t, EV.arrangeGrid, EV.arrangeGrid + .8, E.inOut) * (1 - prog(t, EV.restoreGrid, EV.restoreGrid + .7, E.inOut));
  const W = 1920 - 80, H = 920 - 40, gap = 14, cw = (W - 2 * gap) / 3, ch = (H - gap) / 2;
  arrWins.forEach((w, i) => {
    const gx = 40 + (i % 3) * (cw + gap), gy = 30 + Math.floor(i / 3) * (ch + gap);
    const m = w.mess, d = (i * .05);
    const gi = clamp((g - d) / (1 - .25));
    const ww = lerp(700 * m.s, cw, gi), hh = lerp(410 * m.s, ch, gi);
    css(w, { width: ww + 'px', height: hh + 'px', zIndex: i });
    w.style.opacity = prog(t, a + i * .06, a + .3 + i * .06);
    setT(w, lerp(m.x, gx, gi), lerp(m.y, gy, gi), 1, m.r * (1 - gi));
    w.bodyDiv.style.fontSize = lerp(15 * m.s, 14, gi) + 'px';
  });
  aKeys.style.opacity = prog(t, a + .2, a + .5);
  const d1 = t > EV.arrangeKey && t < EV.arrangeKey + .2, d2 = t > EV.restoreKey && t < EV.restoreKey + .2;
  aKeys.caps[0].classList.toggle('down', d1 || d2); aKeys.caps[1].classList.toggle('down', d1 || d2);
  aPill.style.opacity = win(t, 38.6, 40.9, .3, .25); aPill2.style.opacity = win(t, 41.0, b, .3, .3);
}

// ================= S8: themes =================
const S8 = scene();
const slides = C.themes.map((th, i) => {
  const s = el('div', 'abs', S8); css(s, { inset: 0, opacity: 0, overflow: 'hidden' });
  const art = el('img', 'abs', s); art.src = th.art; css(art, { left: '-0px', top: '-25px', width: '1920px', height: '1131px', transformOrigin: '50% 50%' });
  const shade = el('div', 'abs', s); css(shade, { inset: 0, background: th.light ? 'linear-gradient(90deg, rgba(255,255,255,.35), rgba(255,255,255,0) 50%)' : 'linear-gradient(90deg, rgba(0,0,0,.45), rgba(0,0,0,0) 55%)' });
  const lines = el('div', 'abs', s, sessionLines('', i).join('\n')); css(lines, { left: '170px', top: '360px', font: '23px/1.6 "Cascadia Mono", NotoSansSC', color: th.fg, whiteSpace: 'pre', opacity: .92 });
  lines.classList.add('themed');
  const name = el('div', 'abs', s, `<div style="font-size:66px;font-weight:700;color:${th.fg}" class="serif">${esc(th.name)}</div><div style="margin-top:8px;font-size:28px;color:${th.accent}">${esc(th.sub)}</div>`);
  css(name, { left: '170px', top: '150px' });
  const deck = el('img', 'abs', s); deck.src = th.deck; css(deck, { left: '1290px', top: '230px', width: '552px', filter: 'drop-shadow(0 20px 40px rgba(0,0,0,.6))' });
  s.parts = { art, deck, name, lines }; return s;
});
const mTitle = el('div', 'h1 abs', S8, esc(T.themesTitle)); css(mTitle, { left: 0, width: '1920px', textAlign: 'center', top: '400px', fontSize: '96px' });
const mSub = el('div', 'h2 abs', S8, esc(T.themesSub)); css(mSub, { left: 0, width: '1920px', textAlign: 'center', top: '530px' });
const mScrim = el('div', 'abs', S8); css(mScrim, { inset: 0, background: 'rgba(8,7,6,.9)' });
S8.appendChild(mTitle); S8.appendChild(mSub);
const collage = el('div', 'abs', S8); css(collage, { inset: 0, background: 'radial-gradient(1100px 600px at 50% 50%, #1f1b14, #0b0a08)' });
const colDecks = C.themes.map((th, i) => { const d = el('img', 'abs', collage); d.src = th.deck; const row = i < 4 ? 0 : 1, col = row ? i - 4 : i, n = row ? 3 : 4; css(d, { width: '300px', left: (1920 - n * 300 - (n - 1) * 90) / 2 + col * 390 + 'px', top: (row ? 430 : 60) + 'px' }); return d; });
const colText = el('div', 'h1 abs', collage, esc(T.collage)); css(colText, { left: 0, width: '1920px', textAlign: 'center', top: '900px', fontSize: '58px' });
function updateThemes(t) {
  const [a, b] = SC.themes; const on = t > a - .1 && t < b + .1;
  S8.style.opacity = on ? prog(t, a - .1, a + .15) * (1 - prog(t, b - .25, b, E.in)) : 0; if (!on) return;
  const cuts = EV.themeCuts;
  slides.forEach((s, i) => {
    const s0 = cuts[i], s1 = cuts[i + 1];
    const vis = t >= s0 - .12 && t < s1 + .12;
    s.style.opacity = vis ? Math.min(prog(t, s0 - .12, s0 + .1), 1 - prog(t, s1 - .05, s1 + .12)) : 0;
    if (!vis) return;
    const p = prog(t, s0, s1, E.lin);
    s.parts.art.style.transform = `scale(${1.02 + .05 * p})`;
    s.parts.deck.style.transform = `translate(${(1 - prog(t, s0, s0 + .45, E.out5)) * 120}px, ${-8 * p}px)`;
    s.parts.name.style.transform = `translateY(${(1 - prog(t, s0 + .05, s0 + .5)) * 20}px)`; s.parts.name.style.opacity = prog(t, s0 + .05, s0 + .4);
  });
  const tw = win(t, a, cuts[1] + .05, .25, .3);
  mScrim.style.opacity = tw; mTitle.style.opacity = tw; mSub.style.opacity = win(t, a + .2, cuts[1] + .05, .3, .3);
  mTitle.style.transform = `scale(${1.06 - .06 * prog(t, a, a + .8)})`;
  const cs = cuts[cuts.length - 1]; const cp = prog(t, cs - .1, cs + .25);
  collage.style.opacity = t >= cs - .1 ? cp : 0;
  colDecks.forEach((d, i) => { const q = prog(t, cs + i * .05, cs + .35 + i * .05, E.back); d.style.opacity = q; d.style.transform = `translateY(${(1 - q) * 60}px) scale(${.9 + .1 * q})`; });
  colText.style.opacity = prog(t, cs + .3, cs + .7);
}

// ================= S9: call to action =================
const S9 = scene();
const ctaGlow = el('div', 'abs', S9); css(ctaGlow, { left: '360px', top: '-100px', width: '1200px', height: '900px', borderRadius: '50%', background: 'radial-gradient(circle, rgba(233,201,129,.22), transparent 65%)' });
const ctaIcon = el('img', 'abs', S9); ctaIcon.src = C.assets.icon; css(ctaIcon, { left: '855px', top: '90px', width: '210px', height: '210px' });
const ctaWord = el('div', 'abs', S9, 'OmniVibe'); css(ctaWord, { left: 0, width: '1920px', textAlign: 'center', top: '320px', fontSize: '104px', fontWeight: '700', color: '#F6EEDB' });
const ctaLine = el('div', 'abs h2', S9, esc(T.cta1)); css(ctaLine, { left: 0, width: '1920px', textAlign: 'center', top: '470px', fontSize: '36px', color: '#E3C27E' });
const ctaBtn = el('div', 'abs', S9, `<span style="font-size:40px;margin-right:16px;color:#4a3410">★</span>${esc(T.ctaStar)}`); css(ctaBtn, { left: '660px', width: '600px', top: '580px', height: '96px', borderRadius: '48px', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: '38px', fontWeight: '700', color: '#17140F', background: 'linear-gradient(#F3D58F, #D9AE5C)', boxShadow: '0 16px 50px rgba(233,190,100,.35)' });
const ctaUrl = el('div', 'abs', S9, esc(T.ctaUrl)); css(ctaUrl, { left: 0, width: '1920px', textAlign: 'center', top: '715px', font: '600 40px "Cascadia Mono", monospace', color: '#F3EAD3' });
const ctaJoin = el('div', 'abs h2', S9, esc(T.ctaJoin)); css(ctaJoin, { left: 0, width: '1920px', textAlign: 'center', top: '800px', fontSize: '30px' });
const fine = el('div', 'abs', S9, esc(T.fine)); css(fine, { left: 0, width: '1920px', textAlign: 'center', top: '1010px', fontSize: '18px', color: '#7f765f' });
function updateCta(t) {
  const [a, b] = SC.cta; const on = t > a - .1;
  S9.style.opacity = on ? prog(t, a - .05, a + .3) * (1 - prog(t, b - .7, b - .05, E.in)) : 0; if (!on) return;
  ctaGlow.style.opacity = .7 + .3 * Math.sin(t * 1.5);
  const ip = prog(t, a + .05, a + .6, E.back); ctaIcon.style.opacity = prog(t, a, a + .3); ctaIcon.style.transform = `scale(${.6 + .4 * ip})`;
  ctaWord.style.opacity = prog(t, a + .35, a + .9); ctaWord.style.letterSpacing = lerp(.2, .02, prog(t, a + .35, a + 1.1, E.out5)) + 'em';
  ctaLine.style.opacity = prog(t, a + .9, a + 1.4);
  const bp = prog(t, a + 1.4, a + 2.0, E.back); ctaBtn.style.opacity = prog(t, a + 1.4, a + 1.7); ctaBtn.style.transform = `scale(${.85 + .15 * bp + .015 * Math.sin(t * 4) * prog(t, a + 2.2, a + 2.6)})`;
  ctaUrl.style.opacity = prog(t, a + 1.9, a + 2.4);
  ctaJoin.style.opacity = prog(t, a + 2.5, a + 3.1);
  fine.style.opacity = prog(t, a + 3.0, a + 3.6);
}

// ---------- master ----------
window.seek = function (t) {
  updateDust(t);
  updateChaos(t); updateBrand(t); updateCapture(t); updateSwitch(t); updateOverview(t); updateArrange(t); updateThemes(t); updateCta(t);
  grain.style.backgroundPosition = `${(t * 997) % 256}px ${(t * 613) % 256}px`;
  document.getElementById('bg').style.opacity = 1;
};
window.ready = () => Promise.all(Array.from(document.images).map(i => i.complete ? Promise.resolve() : new Promise(r => { i.onload = i.onerror = r; })))
  .then(() => document.fonts.ready).then(() => true);
seek(0);
