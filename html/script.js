const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'rsg-overlay';
const post = (name, data = {}) => fetch(`https://${RES}/${name}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data)
}).then(r => r.json()).catch(() => null);

const world = document.getElementById('world');
const BASE = 1024;                       // element pixel width before transform
const DEG = Math.PI / 180;
let cfg = { doubleSided: false, audioDistance: 15, maxVolume: 0.6, minSize: 0.25, maxSize: 8, defW: 1.5, defH: 1 };
const overlays = new Map();              // id -> { data, el, media, dist }
let visibleIds = new Set();
let cam = null;
let preview = null;                      // { data, el, media, key }

/* ---------------- media helpers ---------------- */
function ytId(url) {
    const m = url.match(/(?:youtu\.be\/|[?&]v=|\/embed\/|\/shorts\/)([\w-]{11})/);
    return m ? m[1] : null;
}
function detect(url, wanted) {
    if (!/^https:\/\//i.test(url)) return null;
    if (wanted && wanted !== 'auto') return wanted;
    if (ytId(url) && /youtu(\.be|be\.com)/i.test(url)) return 'youtube';
    if (/\.(mp4|webm|ogv)(\?|#|$)/i.test(url)) return 'video';
    return 'image';
}
function buildMedia(type, url, id) {
    let m;
    if (type === 'video') {
        m = document.createElement('video');
        Object.assign(m, { src: url, autoplay: true, loop: true, muted: true, playsInline: true });
        m.addEventListener('loadeddata', () => { m.play().catch(() => {}); });
    } else if (type === 'youtube') {
        const v = id || ytId(url);
        m = document.createElement('iframe');
        m.src = `https://www.youtube.com/embed/${v}?autoplay=1&mute=1&loop=1&playlist=${v}&controls=0&disablekb=1&modestbranding=1&rel=0&enablejsapi=1`;
        m.allow = 'autoplay; encrypted-media';
        m.addEventListener('load', () => { m._ready = true; ytCmd(m, 'listening'); });
    } else {
        m = document.createElement('img');
        m.src = url;
        m.referrerPolicy = 'no-referrer';
    }
    return m;
}
function ytCmd(frame, func, args = []) {
    if (!frame.contentWindow) return;
    const msg = func === 'listening' ? { event: 'listening' } : { event: 'command', func, args };
    frame.contentWindow.postMessage(JSON.stringify(msg), '*');
}
function setVolume(entry, vol) {
    const m = entry.media; if (!m) return;
    vol = Math.max(0, Math.min(1, vol));
    if (entry._vol !== undefined && Math.abs(entry._vol - vol) < 0.02) return;
    entry._vol = vol;
    if (m.tagName === 'VIDEO') { m.muted = vol <= 0.001; m.volume = vol; }
    else if (m.tagName === 'IFRAME' && m._ready) {
        if (vol <= 0.001) ytCmd(m, 'mute'); else { ytCmd(m, 'unMute'); ytCmd(m, 'setVolume', [Math.round(vol * 100)]); }
    }
}

/* ---------------- element lifecycle ---------------- */
function createEl(d, isPreview) {
    const el = document.createElement('div');
    el.className = 'ov' + (d.type === 'image' ? ' img-bg' : '') + (isPreview ? ' preview' : '');
    el.style.width = BASE + 'px';
    el.style.height = Math.round(BASE * d.height / d.width) + 'px';
    el.style.opacity = d.opacity ?? 1;
    el.style.display = 'none';
    const media = buildMedia(d.type, d.url, d.ytId);
    el.appendChild(media);
    world.appendChild(el);
    return { el, media };
}
function show(id) {
    const e = overlays.get(id);
    if (!e || e.el) return;
    Object.assign(e, createEl(e.data, false));
}
function hide(id) {
    const e = overlays.get(id);
    if (!e || !e.el) return;
    if (e.media && e.media.tagName === 'VIDEO') { e.media.pause(); e.media.removeAttribute('src'); e.media.load(); }
    e.el.remove(); e.el = null; e.media = null; e._vol = undefined;
}

/* ---------------- projection ---------------- */
function camBasis(c) {
    const p = c.rx * DEG, y = c.rz * DEG;
    const f = [-Math.sin(y) * Math.cos(p), Math.cos(y) * Math.cos(p), Math.sin(p)];
    const r = [Math.cos(y), Math.sin(y), 0];
    const u = [r[1] * f[2] - r[2] * f[1], r[2] * f[0] - r[0] * f[2], r[0] * f[1] - r[1] * f[0]];
    return { f, r, u, tan: Math.tan(c.fov * DEG / 2) };
}
function project(P, c, b, W, H) {
    const rel = [P[0] - c.x, P[1] - c.y, P[2] - c.z];
    const z = rel[0] * b.f[0] + rel[1] * b.f[1] + rel[2] * b.f[2];
    if (z < 0.05) return null;
    const x = rel[0] * b.r[0] + rel[1] * b.r[1] + rel[2] * b.r[2];
    const y = rel[0] * b.u[0] + rel[1] * b.u[1] + rel[2] * b.u[2];
    return [W / 2 * (1 + x / (z * b.tan * (W / H))), H / 2 * (1 - y / (z * b.tan))];
}
function corners(d) {
    const h = d.heading * DEG;
    const rx = -Math.cos(h), ry = -Math.sin(h);   // viewer right when facing the front
    const hw = d.width / 2, hh = d.height / 2;
    return [
        [d.x - rx * hw, d.y - ry * hw, d.z + hh],   // TL
        [d.x + rx * hw, d.y + ry * hw, d.z + hh],   // TR
        [d.x - rx * hw, d.y - ry * hw, d.z - hh],   // BL
        [d.x + rx * hw, d.y + ry * hw, d.z - hh],   // BR
    ];
}
// 2D homography -> CSS matrix3d
const adjm = m => [m[4]*m[8]-m[5]*m[7], m[2]*m[7]-m[1]*m[8], m[1]*m[5]-m[2]*m[4], m[5]*m[6]-m[3]*m[8], m[0]*m[8]-m[2]*m[6], m[2]*m[3]-m[0]*m[5], m[3]*m[7]-m[4]*m[6], m[1]*m[6]-m[0]*m[7], m[0]*m[4]-m[1]*m[3]];
const mm = (a, b) => { const c = []; for (let i = 0; i < 3; i++) for (let j = 0; j < 3; j++) { let s = 0; for (let k = 0; k < 3; k++) s += a[3*i+k] * b[3*k+j]; c[3*i+j] = s; } return c; };
const mv = (m, v) => [m[0]*v[0]+m[1]*v[1]+m[2]*v[2], m[3]*v[0]+m[4]*v[1]+m[5]*v[2], m[6]*v[0]+m[7]*v[1]+m[8]*v[2]];
const basis = (p) => { const m = [p[0], p[2], p[4], p[1], p[3], p[5], 1, 1, 1]; const v = mv(adjm(m), [p[6], p[7], 1]); return mm(m, [v[0],0,0, 0,v[1],0, 0,0,v[2]]); };
function matrix3d(w, h, dst) {
    const t = mm(basis(dst), adjm(basis([0, 0, w, 0, 0, h, w, h])));
    for (let i = 0; i < 9; i++) t[i] /= t[8];
    return `matrix3d(${t[0]},${t[3]},0,${t[6]},${t[1]},${t[4]},0,${t[7]},0,0,1,0,${t[2]},${t[5]},0,${t[8]})`;
}

function place(entry, c, b, W, H) {
    const d = entry.data, el = entry.el;
    if (!el) return;
    if (!cfg.doubleSided) {
        const h = d.heading * DEG;
        if ((c.x - d.x) * -Math.sin(h) + (c.y - d.y) * Math.cos(h) < 0) { el.style.display = 'none'; return; }
    }
    const pts = [];
    for (const P of corners(d)) { const s = project(P, c, b, W, H); if (!s) { el.style.display = 'none'; return; } pts.push(s[0], s[1]); }
    el.style.display = 'block';
    el.style.transform = matrix3d(BASE, el.offsetHeight || BASE * d.height / d.width, pts);
}

function render() {
    if (!cam || cam.hidden) { world.style.display = 'none'; return; }
    world.style.display = 'block';
    const W = window.innerWidth, H = window.innerHeight, b = camBasis(cam);
    for (const id of visibleIds) place(overlays.get(id), cam, b, W, H);
    if (preview) place(preview, cam, b, W, H);
}

/* ---------------- preview ---------------- */
function setPreview(d) {
    if (!d) { if (preview) { preview.el.remove(); preview = null; } return; }
    d.type = detect(d.url, d.type) || 'image';
    const key = d.url + '|' + d.type;          // media only rebuilt when the source changes
    if (!preview || preview.key !== key) {
        if (preview) preview.el.remove();
        preview = { key, data: d, ...createEl(d, true) };
        if (preview.media.tagName === 'VIDEO') preview.media.muted = true;
    }
    preview.data = d;
    preview.el.style.height = Math.round(BASE * d.height / d.width) + 'px';
    preview.el.style.opacity = d.opacity ?? 1;
    preview.el.classList.toggle('invalid', !!d.invalid);
}

/* ---------------- messages ---------------- */
window.addEventListener('message', (e) => {
    const { action, data } = e.data || {};
    switch (action) {
        case 'config': Object.assign(cfg, data); initForm(); break;
        case 'setOverlays':
            for (const id of [...overlays.keys()]) hide(id);
            overlays.clear(); visibleIds.clear();
            (data || []).forEach(o => overlays.set(o.id, { data: o }));
            break;
        case 'addOverlay': overlays.set(data.id, { data }); break;
        case 'removeOverlay': hide(data); overlays.delete(data); visibleIds.delete(data); break;
        case 'visible': {
            const next = new Set();
            (data || []).forEach(v => {
                const e = overlays.get(v.id); if (!e) return;
                next.add(v.id); show(v.id); e.dist = v.dist;
                if (e.data.type !== 'image') {
                    const fall = Math.max(0, 1 - v.dist / cfg.audioDistance);
                    setVolume(e, fall * fall * (e.data.volume ?? 0.5) * cfg.maxVolume * 2);
                }
            });
            for (const id of visibleIds) if (!next.has(id)) hide(id);
            visibleIds = next;
            break;
        }
        case 'cam': cam = data; render(); break;
        case 'preview': setPreview(data); break;
        case 'openMenu': openMenu(data); break;
        case 'placeHud': updateHud(data); break;
        case 'adjustOpen': openAdjust(data); break;
        case 'adjustClose': closeAdjust(); break;
        case 'lookMode':
            document.getElementById('adjust').classList.toggle('looking', !!data);
            document.getElementById('lookTip').classList.toggle('hidden', !data);
            break;
        case 'closeMenu': document.getElementById('menu').classList.add('hidden'); break;
    }
});

/* ---------------- menu ---------------- */
const $ = id => document.getElementById(id);
const menuEl = $('menu');
let menuData = null;

function initForm() {
    for (const k of ['width', 'height']) { $(k).min = cfg.minSize; $(k).max = cfg.maxSize; }
    $('width').value = cfg.defW; $('height').value = cfg.defH;
    [...$('mediaType').options].forEach(o => {
        if (o.value === 'video') o.disabled = !cfg.allowVideo;
        if (o.value === 'youtube') o.disabled = !cfg.allowYoutube;
    });
    updateForm();
}
function updateForm() {
    $('wVal').textContent = (+$('width').value).toFixed(2) + ' m';
    $('hVal').textContent = (+$('height').value).toFixed(2) + ' m';
    $('oVal').textContent = Math.round($('opacity').value * 100) + '%';
    $('vVal').textContent = Math.round($('volume').value * 100) + '%';
    const url = $('url').value.trim();
    const t = url ? detect(url, $('mediaType').value) : null;
    const pill = $('detected');
    pill.textContent = url ? (t || 'invalid link') : '—';
    pill.classList.toggle('bad', !!url && !t);
    $('volRow').classList.toggle('hidden', t === 'image');
    $('placeBtn').disabled = !t || (menuData && !menuData.admin && menuData.owned >= menuData.max);
    $('fitBtn').disabled = !t || t === 'youtube';
}
['width', 'height', 'opacity', 'volume', 'url', 'mediaType'].forEach(id => $(id).addEventListener('input', updateForm));

// read natural size of the media and keep aspect ratio
$('fitBtn').addEventListener('click', () => {
    const url = $('url').value.trim(), t = detect(url, $('mediaType').value);
    const apply = (w, h) => {
        if (!w || !h) return;
        const width = +$('width').value;
        $('height').value = Math.min(cfg.maxSize, Math.max(cfg.minSize, width * h / w)).toFixed(2);
        updateForm();
    };
    if (t === 'image') { const i = new Image(); i.onload = () => apply(i.naturalWidth, i.naturalHeight); i.src = url; }
    else if (t === 'video') { const v = document.createElement('video'); v.onloadedmetadata = () => apply(v.videoWidth, v.videoHeight); v.src = url; }
});

$('placeBtn').addEventListener('click', () => {
    const url = $('url').value.trim(), t = detect(url, $('mediaType').value);
    if (!t) return;
    post('place', {
        url, mediaType: t, width: +$('width').value, height: +$('height').value,
        opacity: +$('opacity').value, volume: +$('volume').value,
    });
});

function icon(t) { return t === 'youtube' ? '▶' : t === 'video' ? '▣' : '▨'; }
function renderList() {
    const list = $('list'); list.innerHTML = '';
    const items = (menuData && menuData.list) || [];
    let info = menuData ? `You own ${menuData.owned}${menuData.admin ? '' : ' / ' + menuData.max} overlays` : '';
    if (menuData && menuData.cost > 0) info += ` • $${menuData.cost} per placement`;
    if (menuData && menuData.item) info += ` • requires ${menuData.item}`;
    $('info').textContent = info;
    if (!items.length) { const e = document.createElement('div'); e.className = 'empty'; e.textContent = 'No overlays nearby'; list.appendChild(e); return; }
    items.forEach(o => {
        const row = document.createElement('div'); row.className = 'item';
        const ic = document.createElement('div'); ic.className = 'badge-ico'; ic.textContent = icon(o.type);
        const meta = document.createElement('div'); meta.className = 'meta';
        const n = document.createElement('div'); n.className = 'name'; n.textContent = `#${o.id} • ${o.type}`;
        const d = document.createElement('div'); d.className = 'desc';
        d.textContent = `${o.mine ? 'Yours' : o.owner} • ${o.dist} m away`;
        d.title = o.url;
        meta.append(n, d); row.append(ic, meta);
        if (o.canDelete) {
            const b = document.createElement('button'); b.className = 'wood-btn muted del'; b.textContent = 'Remove';
            b.addEventListener('click', async () => {
                b.disabled = true;
                const res = await post('delete', { id: o.id });
                if (res && res.menu) { menuData = res.menu; renderList(); updateForm(); }
            });
            row.appendChild(b);
        }
        list.appendChild(row);
    });
}
function openMenu(data) { menuData = data; menuEl.classList.remove('hidden'); renderList(); updateForm(); $('url').focus(); }

$('closeBtn').addEventListener('click', () => post('close'));
document.addEventListener('keyup', e => {
    if (e.key !== 'Escape') return;
    if (!menuEl.classList.contains('hidden')) post('close');
    else if (adj) post('adjustCancel');
});


/* ---------------- aim HUD ---------------- */
function meter(fillEl, dist, max) {
    const pct = Math.min(1, dist / max);
    fillEl.style.width = (pct * 100) + '%';
    fillEl.className = 'fill ' + (pct > 1 || dist > max ? 'stat-bad' : pct > 0.75 ? 'stat-warn' : 'stat-good');
    if (dist > max) fillEl.style.width = '100%';
}
function updateHud(d) {
    const hud = $('placeHud');
    if (!d) { hud.classList.add('hidden'); return; }
    hud.classList.remove('hidden');
    $('hudDist').textContent = `${d.dist.toFixed(1)} / ${d.maxDist} m`;
    meter($('hudFill'), d.dist, d.maxDist);
    const surf = { wall: 'Snapped to wall', ground: 'Standing on ground', air: 'Floating' }[d.surface] || '';
    $('hudMeta').textContent = d.valid
        ? `${surf} • ${Math.round(d.heading)}°${d.zOff ? ` • ${d.zOff > 0 ? '+' : ''}${d.zOff.toFixed(2)} m` : ''}`
        : 'Too far away — move closer';
}

/* ---------------- adjust panel ---------------- */
let adj = null;            // live state being edited
let adjOrig = null;        // state when locked, for Reset
let adjLimits = { maxDist: 10, minSize: 0.25, maxSize: 8 };
let step = 0.05;
let pending = false, dirty = false;

const clampSize = v => Math.min(adjLimits.maxSize, Math.max(adjLimits.minSize, v));
const r2 = v => Math.round(v * 100) / 100;

function openAdjust(d) {
    adj = { ...d.state };
    adjOrig = { ...d.state };
    adjLimits = d;
    for (const k of ['adjW', 'adjH']) { $(k).min = d.minSize; $(k).max = d.maxSize; }
    $('adjVolRow').classList.toggle('hidden', detect(adj.url, adj.mediaType) === 'image');
    $('adjust').classList.remove('hidden', 'looking');
    syncInputs();
    applyAdjust();
}
function closeAdjust() { adj = null; $('adjust').classList.add('hidden'); $('lookTip').classList.add('hidden'); }

function syncInputs() {
    $('rot').value = adj.heading; $('rotVal').textContent = adj.heading.toFixed(1) + '°';
    $('adjW').value = adj.width; $('adjWVal').textContent = adj.width.toFixed(2) + ' m';
    $('adjH').value = adj.height; $('adjHVal').textContent = adj.height.toFixed(2) + ' m';
    $('adjO').value = adj.opacity; $('adjOVal').textContent = Math.round(adj.opacity * 100) + '%';
    $('adjV').value = adj.volume; $('adjVVal').textContent = Math.round(adj.volume * 100) + '%';
}

// redraw preview instantly, then ask the client to validate range (throttled to one request in flight)
function applyAdjust() {
    if (!adj) return;
    setPreview({ url: adj.url, type: adj.mediaType, x: adj.x, y: adj.y, z: adj.z, heading: adj.heading,
        width: adj.width, height: adj.height, opacity: adj.opacity, invalid: adj._invalid });
    syncInputs();
    if (pending) { dirty = true; return; }
    pending = true;
    post('adjustUpdate', adj).then(res => {
        pending = false;
        if (res && adj && res.dist !== undefined) {
            adj._invalid = !res.valid;
            $('adjDist').textContent = `${res.dist.toFixed(1)} / ${adjLimits.maxDist} m`;
            meter($('adjFill'), res.dist, adjLimits.maxDist);
            $('adjConfirm').disabled = !res.valid;
            $('adjHint').textContent = res.valid
                ? 'Hold right mouse to look around • WASD / arrows move • Q/E rotate • Shift = fine'
                : 'Too far from you — move it closer or walk nearer';
            if (preview) preview.el.classList.toggle('invalid', !res.valid);
        }
        if (dirty) { dirty = false; applyAdjust(); }
    });
}

function move(dir, amt) {
    const h = adj.heading * DEG;
    const right = [-Math.cos(h), -Math.sin(h)], out = [-Math.sin(h), Math.cos(h)];
    switch (dir) {
        case 'left':  adj.x -= right[0] * amt; adj.y -= right[1] * amt; break;
        case 'right': adj.x += right[0] * amt; adj.y += right[1] * amt; break;
        case 'up':    adj.z += amt; break;
        case 'down':  adj.z -= amt; break;
        case 'fwd':   adj.x += out[0] * amt; adj.y += out[1] * amt; break;
        case 'back':  adj.x -= out[0] * amt; adj.y -= out[1] * amt; break;
    }
}
function rotate(sign, amt) { adj.heading = ((adj.heading + sign * amt) % 360 + 360) % 360; }

// press-and-hold repeat on nudge buttons
document.querySelectorAll('#adjust .nudge').forEach(btn => {
    let t1, t2;
    const act = () => {
        if (!adj) return;
        if (btn.dataset.move) move(btn.dataset.move, step);
        else rotate(+btn.dataset.rot, step >= 0.25 ? 15 : step >= 0.05 ? 5 : 1);
        applyAdjust();
    };
    const stop = () => { clearTimeout(t1); clearInterval(t2); };
    btn.addEventListener('mousedown', e => { if (e.button !== 0) return; act(); t1 = setTimeout(() => t2 = setInterval(act, 60), 300); });
    btn.addEventListener('mouseup', stop); btn.addEventListener('mouseleave', stop);
});
document.querySelectorAll('#steps button').forEach(b => b.addEventListener('click', () => {
    document.querySelectorAll('#steps button').forEach(x => x.classList.remove('on'));
    b.classList.add('on'); step = +b.dataset.step;
}));

$('rot').addEventListener('input', () => { adj.heading = +$('rot').value; applyAdjust(); });
$('adjW').addEventListener('input', () => {
    const w = +$('adjW').value;
    if ($('lockAspect').checked) adj.height = r2(clampSize(adj.height * w / adj.width));
    adj.width = w; applyAdjust();
});
$('adjH').addEventListener('input', () => {
    const h = +$('adjH').value;
    if ($('lockAspect').checked) adj.width = r2(clampSize(adj.width * h / adj.height));
    adj.height = h; applyAdjust();
});
$('adjO').addEventListener('input', () => { adj.opacity = +$('adjO').value; applyAdjust(); });
$('adjV').addEventListener('input', () => { adj.volume = +$('adjV').value; applyAdjust(); });

$('adjReset').addEventListener('click', () => { if (adjOrig) { adj = { ...adjOrig }; applyAdjust(); } });
$('adjCancel').addEventListener('click', () => post('adjustCancel'));
$('adjReaim').addEventListener('click', () => post('adjustReaim', adj));
$('adjConfirm').addEventListener('click', () => {
    if (!adj || adj._invalid) return;
    const { _invalid, _rot, _z, ...state } = adj;
    post('adjustConfirm', state);
});

// keyboard shortcuts while the panel has focus
document.addEventListener('keydown', e => {
    if (!adj || e.target.tagName === 'INPUT' && e.target.type === 'text') return;
    const amt = e.shiftKey ? step / 5 : step;
    const map = { w: 'up', arrowup: 'up', s: 'down', arrowdown: 'down', a: 'left', arrowleft: 'left',
        d: 'right', arrowright: 'right', r: 'fwd', pageup: 'fwd', f: 'back', pagedown: 'back' };
    const k = e.key.toLowerCase();
    if (map[k]) { move(map[k], amt); }
    else if (k === 'q') rotate(-1, e.shiftKey ? 1 : 5);
    else if (k === 'e') rotate(1, e.shiftKey ? 1 : 5);
    else if (k === 'enter') { $('adjConfirm').click(); return; }
    else return;
    e.preventDefault();
    applyAdjust();
});

// hold right mouse anywhere to hand the camera back to the game
document.addEventListener('mousedown', e => { if (adj && e.button === 2) post('lookStart'); });
document.addEventListener('contextmenu', e => e.preventDefault());

initForm();
post('ready');
