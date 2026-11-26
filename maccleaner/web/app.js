"use strict";

const TOKEN = document.querySelector('meta[name="mc-token"]').content;
const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => Array.from(el.querySelectorAll(s));

const state = {
  scanned: false,
  path: null,          // folder yang sedang dilihat di Analisis
  selected: new Map(), // path -> {path, size, safety, title, contents}
  summary: null,
  recs: null,
};

const CAT_COLORS = {
  cache: "#22c55e", log: "#84cc16", dev: "#8b5cf6", trash: "#14b8a6", downloads: "#06b6d4",
  installer: "#0ea5e9", backup: "#f59e0b", vm: "#f97316", apps: "#3b82f6", appdata: "#6366f1",
  media: "#ec4899", docs: "#a855f7", mail: "#eab308", cloud: "#38bdf8", system: "#64748b",
  other: "#9ca3af",
};

// ---------------------------------------------------------------- util
function esc(s) {
  return String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}
// Satuan desimal (1 GB = 1000³ byte), sama seperti Finder di macOS.
function human(n) {
  n = Number(n) || 0;
  const u = ["B", "KB", "MB", "GB", "TB"];
  let i = 0;
  while (Math.abs(n) >= 999.5 && i < u.length - 1) { n /= 1000; i++; }
  return i === 0 ? `${n} B` : `${n.toFixed(n >= 100 ? 0 : 1).replace(".", ",")} ${u[i]}`;
}
const rtf = new Intl.RelativeTimeFormat("id", { numeric: "auto" });
function ago(ts) {
  if (!ts) return "";
  const s = (Date.now() / 1000) - ts;
  const steps = [[60, "second"], [3600, "minute"], [86400, "hour"], [2592000, "day"], [31536000, "month"], [Infinity, "year"]];
  const div = { second: 1, minute: 60, hour: 3600, day: 86400, month: 2592000, year: 31536000 };
  for (const [lim, unit] of steps) if (s < lim) return rtf.format(-Math.round(s / div[unit]), unit);
}
// 45 dtk · 3 mnt 12 dtk · 1 jam 5 mnt
function fmtDuration(sec) {
  const s = Math.max(0, Math.round(sec || 0));
  if (s < 60) return `${s} dtk`;
  if (s < 3600) {
    const m = Math.floor(s / 60), r = s % 60;
    return r ? `${m} mnt ${r} dtk` : `${m} mnt`;
  }
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
  return m ? `${h} jam ${m} mnt` : `${h} jam`;
}
function fmtEta(sec) {
  if (sec === null || sec === undefined) return "Memperkirakan sisa waktu…";
  if (sec < 10) return "Hampir selesai…";
  if (sec < 60) return "Kurang dari 1 menit lagi";
  if (sec < 3600) return `Sekitar ${Math.max(1, Math.round(sec / 60))} menit lagi`;
  const total = Math.round(sec / 60), h = Math.floor(total / 60), m = total % 60;
  return m ? `Sekitar ${h} jam ${m} menit lagi` : `Sekitar ${h} jam lagi`;
}
const ESTIMATE_NOTE = {
  history: "Perkiraan berdasarkan pemindaian sebelumnya di folder ini.",
  disk: "Perkiraan berdasarkan pemakaian disk.",
  tree: "Pemindaian pertama di folder ini — perkiraan makin akurat seiring berjalan.",
};
function badge(rule) {
  return `<span class="badge ${esc(rule.safety)}">${esc(rule.safetyLabel)}</span>`;
}
function toast(msg, kind = "") {
  const el = document.createElement("div");
  el.className = `toast ${kind}`;
  el.textContent = msg;
  $("#toasts").appendChild(el);
  setTimeout(() => el.remove(), kind === "err" ? 9000 : 5000);
}

async function api(path, body) {
  const opt = { headers: { "X-Token": TOKEN } };
  if (body !== undefined) {
    opt.method = "POST";
    opt.headers["Content-Type"] = "application/json";
    opt.body = JSON.stringify(body);
  }
  const res = await fetch(path, opt);
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`);
  return data;
}

// ---------------------------------------------------------------- navigasi
function show(view) {
  $$(".view").forEach(v => v.classList.toggle("active", v.id === `view-${view}`));
  $$("nav button").forEach(b => b.classList.toggle("active", b.dataset.view === view));
  updateSelbar();
  if (view === "explore" && state.scanned && !$("#list").childElementCount) openFolder(null);
  if (view === "large" && state.scanned) loadLarge();
  window.scrollTo(0, 0);
}
$$("nav button").forEach(b => b.addEventListener("click", () => show(b.dataset.view)));
$$("[data-goto]").forEach(b => b.addEventListener("click", () => show(b.dataset.goto)));

// ---------------------------------------------------------------- disk
async function loadDisks() {
  const { disks } = await api("/api/disks");
  const box = $("#disks");
  box.innerHTML = "";
  for (const d of disks) {
    const el = document.createElement("div");
    el.className = `card disk lvl-${d.level}`;
    el.innerHTML = `
      <div class="disk-top">
        <div><div class="disk-name">${esc(d.name)}</div><div class="muted small">${esc(d.mount)}${d.fs ? " · " + esc(d.fs) : ""}</div></div>
        <div class="disk-pct">${Math.round(d.percent)}%</div>
      </div>
      <div class="meter"><div style="width:${Math.min(100, d.percent)}%"></div></div>
      <div class="disk-nums"><span>Terpakai ${human(d.used)}</span><span>Sisa ${human(d.free)} dari ${human(d.total)}</span></div>
      <div class="disk-msg">${esc(d.message)}</div>
      <div class="actions"></div>`;
    const acts = $(".actions", el);
    d.scanPaths.forEach((sp, i) => {
      const b = document.createElement("button");
      b.className = "btn" + (i === 0 ? " primary" : "");
      b.textContent = `Pindai ${sp.label.charAt(0).toLowerCase() + sp.label.slice(1)}`;
      b.addEventListener("click", () => startScan(sp.path));
      acts.appendChild(b);
    });
    box.appendChild(el);
  }
}
$("#refreshDisks").addEventListener("click", () => loadDisks().catch(e => toast(e.message, "err")));

// ---------------------------------------------------------------- pindai
let pollTimer = null;
let smoothEta = null;
async function startScan(path) {
  smoothEta = null;
  try {
    await api("/api/scan", { path });
  } catch (e) { toast(e.message, "err"); return; }
  $("#scanOverlay").classList.remove("hidden");
  pollTimer && clearInterval(pollTimer);
  pollTimer = setInterval(pollScan, 300);
  pollScan();
}
async function pollScan() {
  let s;
  try { s = await api("/api/status"); } catch (e) { return; }
  $("#scanRoot").textContent = s.display || "";
  $("#scanFiles").textContent = (s.files || 0).toLocaleString("id-ID");
  $("#scanBytes").textContent = human(s.bytes);
  $("#scanTime").textContent = fmtDuration(s.elapsed || 0);
  $("#scanCur").textContent = s.current || "";
  const pct = Math.round((s.fraction || 0) * 100);
  $("#scanBar").style.width = `${Math.max(1, pct)}%`;
  $("#scanPct").textContent = `${pct}%`;
  // Haluskan sisa waktu agar angkanya tidak melompat-lompat.
  smoothEta = (s.eta == null) ? null : (smoothEta == null ? s.eta : smoothEta * 0.8 + s.eta * 0.2);
  $("#scanEta").textContent = fmtEta(smoothEta);
  $("#scanNote").textContent = ESTIMATE_NOTE[s.estimate] || "";
  if (s.state !== "running") {
    clearInterval(pollTimer);
    pollTimer = null;
    $("#scanOverlay").classList.add("hidden");
    if (s.state === "error") toast("Pemindaian gagal: " + s.error, "err");
    else if (s.state === "cancelled") toast("Pemindaian dibatalkan — hasil sebagian ditampilkan.");
    if (s.state === "done" || s.state === "cancelled") await afterScan();
  }
}
$("#scanCancel").addEventListener("click", () => api("/api/cancel", {}).catch(() => {}));

async function afterScan() {
  state.scanned = true;
  state.selected.clear();
  state.path = null;
  $("#list").innerHTML = "";
  $$("nav button").forEach(b => (b.disabled = false));
  await Promise.all([loadSummary(), loadRecs(), loadDisks()]);
  updateSelbar();
}

// ---------------------------------------------------------------- ringkasan
async function loadSummary() {
  const s = state.summary = await api("/api/summary");
  $("#summary").classList.remove("hidden");
  $("#sumSub").textContent = `${s.display} · ${human(s.scanned)} dalam ${s.files.toLocaleString("id-ID")} file · selesai dalam ${fmtDuration(s.elapsed)}`;
  const cats = s.categories.slice();
  if (s.wholeDisk && s.unscanned > 0) cats.push({ id: "unscanned", label: "Data sistem / tak terbaca", size: s.unscanned });
  drawDonut(cats);
  $("#insights").innerHTML = s.insights.map(i => `<li class="${esc(i.level)}">${esc(i.text)}</li>`).join("");
  $("#statSafe").textContent = human(s.safeTotal);
  $("#statCaution").textContent = human(s.cautionTotal);
}

function drawDonut(cats) {
  const svg = $("#donut");
  const total = cats.reduce((a, c) => a + c.size, 0) || 1;
  const r = 46, C = 2 * Math.PI * r;
  let off = 0, html = `<circle cx="60" cy="60" r="${r}" fill="none" stroke="var(--panel-2)" stroke-width="18"/>`;
  const shown = [];
  let rest = 0;
  cats.forEach((c, i) => { if (i < 9 && c.size / total > 0.004) shown.push(c); else rest += c.size; });
  if (rest) shown.push({ id: "other", label: "Lainnya (kecil)", size: rest });
  for (const c of shown) {
    const len = (c.size / total) * C;
    const color = c.id === "unscanned" ? "#cbd5e1" : (CAT_COLORS[c.id] || "#9ca3af");
    html += `<circle cx="60" cy="60" r="${r}" fill="none" stroke="${color}" stroke-width="18"
      stroke-dasharray="${Math.max(0, len - 0.6)} ${C}" stroke-dashoffset="${-off}" transform="rotate(-90 60 60)"><title>${esc(c.label)}: ${human(c.size)}</title></circle>`;
    off += len;
  }
  html += `<text x="60" y="57" text-anchor="middle" font-size="13" font-weight="700">${human(total)}</text>
           <text x="60" y="71" text-anchor="middle" font-size="7" opacity=".6">total</text>`;
  svg.innerHTML = html;
  $("#catLegend").innerHTML = shown.map(c => `
    <li><span class="sw" style="background:${c.id === "unscanned" ? "#cbd5e1" : (CAT_COLORS[c.id] || "#9ca3af")}"></span>
    <span>${esc(c.label)}</span><span class="sz">${human(c.size)} · ${Math.round(c.size / total * 100)}%</span></li>`).join("");
}

// ---------------------------------------------------------------- analisis
async function openFolder(path) {
  let data;
  try {
    data = await api("/api/node" + (path ? "?path=" + encodeURIComponent(path) : ""));
  } catch (e) { toast(e.message, "err"); return; }
  state.path = data.node.path;
  const crumbs = $("#crumbs");
  crumbs.innerHTML = "";
  data.crumbs.forEach((c, i) => {
    if (i) crumbs.insertAdjacentHTML("beforeend", `<span class="sep">/</span>`);
    const a = document.createElement("a");
    a.textContent = c.name;
    a.addEventListener("click", () => openFolder(c.path));
    crumbs.appendChild(a);
  });
  $("#upBtn").disabled = data.crumbs.length < 2;
  $("#upBtn").onclick = () => data.crumbs.length > 1 && openFolder(data.crumbs[data.crumbs.length - 2].path);

  const list = $("#list");
  list.innerHTML = "";
  if (!data.items.length) list.innerHTML = `<div class="empty">Folder ini kosong.</div>`;
  const max = data.items.length ? data.items[0].size || 1 : 1;
  for (const it of data.items) {
    const row = document.createElement("div");
    row.className = "row" + (it.other ? " other" : "");
    row.innerHTML = `
      <span class="ic">${it.other ? "…" : it.isDir ? (it.denied ? "🔒" : "📁") : "📄"}</span>
      <span class="nm" title="${esc(it.display)}">${esc(it.name)}${it.isDir && it.files ? `<small>${it.files.toLocaleString("id-ID")} file</small>` : ""}</span>
      <span class="bg"><div style="width:${Math.max(0.5, it.size / max * 100)}%"></div></span>
      <span class="sz">${human(it.size)}</span>
      <span class="st">${it.other ? "" : badge(it.rule)}</span>`;
    if (!it.other) {
      row.addEventListener("click", () => {
        $$(".row.sel").forEach(r => r.classList.remove("sel"));
        row.classList.add("sel");
        showDetail(it);
      });
      if (it.isDir) row.addEventListener("dblclick", () => openFolder(it.path));
    }
    list.appendChild(row);
  }
  showDetail(data.node, true);
}

function showDetail(it, isCurrent = false) {
  const r = it.rule;
  const d = $("#detail");
  const own = !r.inherited && r.id;
  let action = "";
  if (it.protected) {
    action = `<div class="note">Folder penting — dilindungi dari penghapusan oleh aplikasi ini.</div>`;
  } else if (r.safety === "jangan") {
    action = `<div class="note bad">Jangan dihapus manual. ${esc(r.how)}</div>`;
  } else if (r.partOf) {
    action = `<div class="note warn">Ini bagian dalam dari "${esc(r.title)}". Menghapus satu file di dalamnya bisa merusak keseluruhannya — buang seluruh foldernya saja.</div>`;
  } else if (!r.deletable) {
    action = `<div class="note warn">Bersihkan lewat caranya sendiri (lihat di atas), bukan dengan menghapus file.</div>`;
  } else {
    const contents = it.isDir && own && r.mode === "contents";
    action = `<button class="btn danger" id="dTrash">${contents ? "Kosongkan isinya" : "Buang ke Sampah"}</button>`;
  }
  d.innerHTML = `
    <div>
      <div class="muted small">${isCurrent ? "Folder ini" : it.isDir ? "Folder" : "File"}</div>
      <h2>${esc(it.name)}</h2>
      <div class="path">${esc(it.display)}</div>
    </div>
    <div style="display:flex;align-items:center;gap:10px;justify-content:space-between">
      <span class="big">${human(it.size)}</span>${badge(r)}
    </div>
    ${it.isDir ? `<div class="muted small">${(it.files || 0).toLocaleString("id-ID")} file${it.mtime ? " · diubah " + ago(it.mtime) : ""}</div>` : `<div class="muted small">Diubah ${ago(it.mtime)}</div>`}
    ${it.denied ? `<div class="note warn">Isi folder tidak bisa dibaca (izin ditolak). Ukuran sebenarnya bisa lebih besar.</div>` : ""}
    <dl>
      <div><dt>${r.id ? esc(r.title) + (r.inherited ? " (bagian dari)" : "") : "Apa ini?"}</dt><dd>${esc(r.why)}</dd></div>
      ${r.effect ? `<div><dt>Kalau dihapus</dt><dd>${esc(r.effect)}</dd></div>` : ""}
      ${r.how ? `<div><dt>Cara membersihkan yang benar</dt><dd>${esc(r.how)}</dd></div>` : ""}
      ${r.command ? `<div><dt>Perintah Terminal</dt><dd><div class="cmd"><code>${esc(r.command)}</code><button class="btn sm" id="dCopy">Salin</button></div></dd></div>` : ""}
    </dl>
    <div class="actions">
      ${it.isDir && !isCurrent ? `<button class="btn primary" id="dOpen">Buka folder</button>` : ""}
      <button class="btn" id="dReveal">Tampilkan di Finder</button>
    </div>
    ${action}`;
  $("#dOpen")?.addEventListener("click", () => openFolder(it.path));
  $("#dReveal").addEventListener("click", () => api("/api/reveal", { path: it.path }).catch(e => toast(e.message, "err")));
  $("#dCopy")?.addEventListener("click", () => { navigator.clipboard?.writeText(r.command); toast("Perintah disalin."); });
  $("#dTrash")?.addEventListener("click", () => {
    const contents = it.isDir && own && r.mode === "contents";
    confirmTrash([{ path: it.path, display: it.display, size: it.size, safety: r.safety, title: r.title, contents }]);
  });
}

// ---------------------------------------------------------------- rekomendasi
async function loadRecs() {
  const data = state.recs = await api("/api/recommendations");
  const tc = $("#trashCard");
  tc.innerHTML = data.trash > 0 ? `
    <div class="card trash-card">
      <div class="t-ico">🗑️</div>
      <div class="t-txt"><h3>Sampah berisi ${human(data.trash)}</h3>
      <p class="muted small">File di Sampah masih memakan ruang disk sampai dikosongkan. Mengosongkan Sampah bersifat permanen.</p></div>
      <button class="btn danger" id="emptyTrash">Kosongkan Sampah</button>
    </div>` : "";
  $("#emptyTrash")?.addEventListener("click", emptyTrash);

  const box = $("#recs");
  box.innerHTML = "";
  const trashable = data.groups.filter(g => g.kind === "trash");
  const manual = data.groups.filter(g => g.kind === "manual");
  const safeTotal = trashable.filter(g => g.rule.safety === "aman").reduce((a, g) => a + g.total, 0);
  $("#navRecs").textContent = safeTotal ? human(safeTotal) : "";
  if (!data.groups.length) box.innerHTML = `<div class="card empty">Tidak ada yang perlu dibersihkan di area ini. 🎉</div>`;
  if (trashable.length) box.insertAdjacentHTML("beforeend", `<h2 style="margin:8px 0 10px">Bisa dibuang dari sini</h2>`);
  trashable.forEach(g => box.appendChild(groupCard(g)));
  if (manual.length) {
    box.insertAdjacentHTML("beforeend", `<h2 style="margin:22px 0 4px">Perlu dibersihkan dari aplikasinya</h2>
      <p class="muted small" style="margin-bottom:10px">Item ini besar, tapi menghapus filenya langsung bisa merusak data. Ikuti cara yang disarankan.</p>`);
    manual.forEach(g => box.appendChild(groupCard(g)));
  }
}

function groupCard(g) {
  const r = g.rule;
  const el = document.createElement("div");
  el.className = "card group";
  const selectable = g.kind === "trash";
  el.innerHTML = `
    <div class="g-head">
      ${selectable ? `<input type="checkbox" class="g-check" aria-label="Pilih grup">` : `<span class="g-chev">▸</span>`}
      <div class="g-title">
        <h3>${esc(r.title)} ${badge(r)}</h3>
        <p>${esc(r.why)}</p>
      </div>
      <div class="g-size">${human(g.total)}<div class="muted small" style="font-weight:400;text-align:right">${g.items.length} lokasi</div></div>
      ${selectable ? `<span class="g-chev">▸</span>` : ""}
    </div>
    <div class="g-body">
      <div class="g-info">
        ${r.effect ? `<div><b>Kalau dihapus</b>${esc(r.effect)}</div>` : ""}
        ${r.how ? `<div><b>Cara yang benar</b>${esc(r.how)}</div>` : ""}
      </div>
      ${r.command ? `<div class="cmd" style="margin-bottom:12px"><code>${esc(r.command)}</code><button class="btn sm g-copy">Salin</button></div>` : ""}
      <div class="g-items"></div>
    </div>`;
  const items = $(".g-items", el);
  for (const it of g.items.slice(0, 500)) {
    const row = document.createElement("label");
    row.className = "g-item";
    row.dataset.path = it.path;
    row.innerHTML = `
      ${selectable ? `<input type="checkbox" class="i-check">` : `<span></span>`}
      <span class="p" title="${esc(it.display)}"><bdi>${esc(it.display)}</bdi></span>
      <span class="d">${ago(it.mtime)}</span>
      <span class="s">${human(it.size)}</span>
      <button class="linkbtn" title="Tampilkan di Finder">↗</button>`;
    const cb = $(".i-check", row);
    if (cb) {
      cb.checked = state.selected.has(it.path);
      cb.addEventListener("change", () => {
        toggleSel({ path: it.path, display: it.display, size: it.size, safety: r.safety, title: r.title }, cb.checked);
        syncGroupCheck(el);
      });
    }
    $(".linkbtn", row).addEventListener("click", e => { e.preventDefault(); api("/api/reveal", { path: it.path }); });
    items.appendChild(row);
  }
  if (g.items.length > 500) items.insertAdjacentHTML("beforeend", `<div class="muted small">…dan ${g.items.length - 500} lainnya</div>`);
  $(".g-head", el).addEventListener("click", e => {
    if (e.target.classList.contains("g-check")) return;
    el.classList.toggle("open");
  });
  const gc = $(".g-check", el);
  if (gc) {
    gc.addEventListener("change", () => {
      g.items.forEach(it => toggleSel({ path: it.path, display: it.display, size: it.size, safety: r.safety, title: r.title }, gc.checked));
      $$(".i-check", el).forEach(c => (c.checked = gc.checked));
      gc.indeterminate = false;
    });
    el._group = g;
    syncGroupCheck(el);
  }
  $(".g-copy", el)?.addEventListener("click", () => { navigator.clipboard?.writeText(r.command); toast("Perintah disalin."); });
  return el;
}

function syncGroupCheck(el) {
  const gc = $(".g-check", el);
  if (!gc || !el._group) return;
  const n = el._group.items.filter(it => state.selected.has(it.path)).length;
  gc.checked = n > 0 && n === el._group.items.length;
  gc.indeterminate = n > 0 && n < el._group.items.length;
}

$("#selectSafe").addEventListener("click", () => {
  if (!state.recs) return;
  for (const g of state.recs.groups) {
    if (g.kind !== "trash" || g.rule.safety !== "aman") continue;
    g.items.forEach(it => toggleSel({ path: it.path, display: it.display, size: it.size, safety: "aman", title: g.rule.title }, true));
  }
  $$("#recs .group").forEach(el => {
    $$(".g-item", el).forEach(row => {
      const cb = $(".i-check", row);
      if (cb) cb.checked = state.selected.has(row.dataset.path);
    });
    syncGroupCheck(el);
  });
});

// ---------------------------------------------------------------- file besar
async function loadLarge() {
  let data;
  try { data = await api("/api/largefiles"); } catch (e) { toast(e.message, "err"); return; }
  const tb = $("#largeTable tbody");
  tb.innerHTML = "";
  if (!data.items.length) tb.innerHTML = `<tr><td colspan="6" class="empty">Tidak ada file besar.</td></tr>`;
  for (const it of data.items) {
    const tr = document.createElement("tr");
    const can = it.rule.deletable && it.rule.safety !== "jangan" && !it.protected;
    tr.innerHTML = `
      <td>${can ? `<input type="checkbox">` : ""}</td>
      <td><div class="fname">${esc(it.name)}</div><div class="fpath">${esc(it.display)}</div></td>
      <td class="num">${human(it.size)}</td>
      <td class="num muted">${ago(it.mtime)}</td>
      <td title="${esc(it.rule.why)}">${badge(it.rule)}<div class="muted small">${esc(it.rule.title)}</div></td>
      <td><button class="linkbtn">Finder ↗</button></td>`;
    const cb = $("input", tr);
    if (cb) {
      cb.checked = state.selected.has(it.path);
      cb.addEventListener("change", () => toggleSel({ path: it.path, display: it.display, size: it.size, safety: it.rule.safety, title: it.rule.title }, cb.checked));
    }
    $(".linkbtn", tr).addEventListener("click", () => api("/api/reveal", { path: it.path }));
    tb.appendChild(tr);
  }
}

// ---------------------------------------------------------------- pilihan & buang
function toggleSel(item, on) {
  if (on) state.selected.set(item.path, item); else state.selected.delete(item.path);
  updateSelbar();
}
function updateSelbar() {
  const n = state.selected.size;
  const view = $(".view.active").id;
  const visible = n > 0 && (view === "view-recs" || view === "view-large");
  $("#selbar").classList.toggle("hidden", !visible);
  const total = [...state.selected.values()].reduce((a, s) => a + s.size, 0);
  $("#selInfo").textContent = `${n} item dipilih · ${human(total)}`;
}
$("#selClear").addEventListener("click", () => {
  state.selected.clear();
  $$(".i-check, .g-check, #largeTable input").forEach(c => { c.checked = false; c.indeterminate = false; });
  updateSelbar();
});
$("#selTrash").addEventListener("click", () => confirmTrash([...state.selected.values()]));

function confirmTrash(items) {
  if (!items.length) return;
  const total = items.reduce((a, s) => a + s.size, 0);
  const risky = items.filter(i => i.safety !== "aman");
  $("#cTitle").textContent = `Buang ${items.length} item (${human(total)}) ke Sampah?`;
  $("#cBody").innerHTML = `
    ${risky.length ? `<div class="note warn">${risky.length} item <b>bukan</b> berlabel "Aman dihapus". Pastikan Anda memang tidak membutuhkannya.</div>` : `<div class="note">Semua item berlabel aman dihapus.</div>`}
    <ul>${items.slice(0, 60).map(i => `<li>${esc(i.display)} — ${human(i.size)} ${i.contents ? "(isinya saja)" : ""} ${i.safety !== "aman" ? `<span class="badge ${esc(i.safety)}">${esc(i.safety === "hati" ? "Hati-hati" : i.safety === "periksa" ? "Periksa dulu" : "Tidak dikenali")}</span>` : ""}</li>`).join("")}
    ${items.length > 60 ? `<li>…dan ${items.length - 60} lainnya</li>` : ""}</ul>
    <p class="muted small">Item dipindah ke Sampah dan masih bisa dikembalikan. Ruang baru benar-benar kosong setelah Sampah dikosongkan.</p>`;
  $("#confirm").classList.remove("hidden");
  $("#cYes").onclick = async () => {
    $("#confirm").classList.add("hidden");
    await doTrash(items);
  };
}
$("#cNo").addEventListener("click", () => $("#confirm").classList.add("hidden"));

async function doTrash(items) {
  let res;
  try {
    res = await api("/api/trash", { items: items.map(i => ({ path: i.path, contents: !!i.contents })) });
  } catch (e) { toast(e.message, "err"); return; }
  if (res.done.length) toast(`${res.done.length} item dipindah ke Sampah (${human(res.freed)}). ${res.note}`, "ok");
  if (res.errors.length) {
    toast(`${res.errors.length} item gagal: ` + res.errors.slice(0, 3).map(e => `${e.display}: ${e.error}`).join(" · "), "err");
  }
  items.forEach(i => state.selected.delete(i.path));
  await refreshAll();
}

async function emptyTrash() {
  $("#cTitle").textContent = "Kosongkan Sampah?";
  $("#cBody").innerHTML = `<div class="note bad">Semua file di Sampah akan dihapus <b>permanen</b> dan tidak bisa dikembalikan.</div>`;
  $("#confirm").classList.remove("hidden");
  $("#cYes").onclick = async () => {
    $("#confirm").classList.add("hidden");
    try {
      const r = await api("/api/empty-trash", {});
      toast(r.message, r.ok ? "ok" : "err");
    } catch (e) { toast(e.message, "err"); }
    await refreshAll();
  };
}

async function refreshAll() {
  const tasks = [loadSummary(), loadRecs(), loadDisks()];
  if (state.path) tasks.push(openFolder(state.path).catch(() => openFolder(null)));
  if ($("#view-large").classList.contains("active")) tasks.push(loadLarge());
  await Promise.all(tasks.map(t => t.catch(e => toast(e.message, "err"))));
  updateSelbar();
}

// ---------------------------------------------------------------- mulai
// Detak jantung: memberi tahu server bahwa tab ini masih terbuka.
setInterval(() => api("/api/ping").catch(() => {}), 20000);

(async function init() {
  try {
    await loadDisks();
    const info = await api("/api/info");
    if (info.status.state === "running") {
      $("#scanOverlay").classList.remove("hidden");
      pollTimer = setInterval(pollScan, 300);
    } else if (info.status.state === "done" || info.status.state === "cancelled") {
      await afterScan();
    }
  } catch (e) {
    toast(e.message, "err");
  }
})();
