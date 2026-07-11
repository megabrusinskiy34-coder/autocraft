const API = window.location.origin;

// ── State ─────────────────────────────────────────────────────────────────
let allItems      = [];   // [{id,name,texture,namespace}]
let craftableMap  = {};   // id -> item
let customRecipes = [];
let craftQueue    = [];
let craftLog      = [];

// Builder state
let builderGrid   = new Array(9).fill(null);  // slot 0-8
let builderResult = null;
let pickerTarget  = null;  // slot index, or -1 for result, or 4 for press
let isPress       = false;

// ── Init ──────────────────────────────────────────────────────────────────
async function init() {
  await loadItems();
  await loadCustomRecipes();
  await loadQueue();
  await loadLog();
  buildGrid();
  connectSSE();
}

// ── SSE ───────────────────────────────────────────────────────────────────
function connectSSE() {
  const es = new EventSource(`${API}/api/events`);
  const dot = document.getElementById('sseStatus');
  const txt = document.getElementById('sseText');

  es.addEventListener('queue', e => {
    craftQueue = JSON.parse(e.data);
    renderQueue();
  });
  es.addEventListener('log', e => {
    craftLog = JSON.parse(e.data);
    renderLog();
  });
  es.addEventListener('customRecipes', e => {
    customRecipes = JSON.parse(e.data);
    renderRecipes();
    document.getElementById('customCount').textContent = customRecipes.length;
  });

  es.onopen = () => { dot.classList.add('online'); txt.textContent = 'LIVE'; };
  es.onerror = () => { dot.classList.remove('online'); txt.textContent = 'OFFLINE'; };
}

// ── Data loading ──────────────────────────────────────────────────────────
async function loadItems() {
  try {
    const r = await fetch(`${API}/api/items`);
    const d = await r.json();
    allItems = d.items || [];
    craftableMap = {};
    allItems.forEach(i => craftableMap[i.id] = i);
    buildPopupList(allItems);
  } catch(e) { console.error(e); }
}

async function loadCustomRecipes() {
  try {
    const r = await fetch(`${API}/api/custom-recipes`);
    const d = await r.json();
    customRecipes = d.recipes || [];
    renderRecipes();
    document.getElementById('customCount').textContent = customRecipes.length;
  } catch(e) { console.error(e); }
}

async function loadQueue() {
  try {
    const r = await fetch(`${API}/api/queue`);
    const d = await r.json();
    craftQueue = d.queue || [];
    renderQueue();
  } catch(e) {}
}

async function loadLog() {
  try {
    const r = await fetch(`${API}/api/log?limit=200`);
    const d = await r.json();
    craftLog = d.log || [];
    renderLog();
    document.getElementById('logCount').textContent = d.total || 0;
  } catch(e) {}
}

// ── Tab switching ─────────────────────────────────────────────────────────
function switchTab(name) {
  document.querySelectorAll('.tab').forEach((t,i) => {
    const names = ['builder','recipes','queue','history'];
    t.classList.toggle('active', names[i] === name);
  });
  document.querySelectorAll('.tab-content').forEach(c => {
    c.classList.toggle('active', c.id === 'tab-'+name);
  });
}

// ── Builder grid ──────────────────────────────────────────────────────────
function buildGrid() {
  const g = document.getElementById('craftGrid');
  g.innerHTML = '';
  for (let i = 0; i < 9; i++) {
    const slot = document.createElement('div');
    slot.className = 'craft-slot';
    slot.dataset.idx = i;
    slot.innerHTML = `<span class="slot-num">${i+1}</span>`;
    slot.addEventListener('click', () => openItemPicker(i, false));
    slot.addEventListener('contextmenu', e => { e.preventDefault(); clearSlot(i); });
    g.appendChild(slot);
  }
  refreshGrid();
}

function refreshGrid() {
  for (let i = 0; i < 9; i++) {
    const el = document.querySelector(`#craftGrid .craft-slot[data-idx="${i}"]`);
    if (!el) continue;
    const item = builderGrid[i];
    if (item) {
      const tex = craftableMap[item]?.texture;
      el.classList.add('filled');
      el.innerHTML = `<span class="slot-num">${i+1}</span>`;
      if (tex) {
        const img = document.createElement('img');
        img.src = `/${tex}`;
        img.onerror = () => el.innerHTML = `<span class="slot-num">${i+1}</span><span style="font-size:10px;text-align:center;padding:2px">${item.split(':')[1]||item}</span>`;
        el.appendChild(img);
      } else {
        const lbl = document.createElement('span');
        lbl.className = 'slot-label';
        lbl.textContent = (item.split(':')[1]||item).slice(0,6);
        el.appendChild(lbl);
      }
    } else {
      el.classList.remove('filled');
      el.innerHTML = `<span class="slot-num">${i+1}</span>`;
    }
  }
  updatePreview();
}

function clearSlot(i) {
  builderGrid[i] = null;
  refreshGrid();
}

function onTypeChange() {
  const t = document.getElementById('recipeType').value;
  const isP = t.startsWith('create:') && t !== 'create:mechanical_crafting';
  document.getElementById('gridSection').style.display = isP ? 'none' : '';
  document.getElementById('pressSection').style.display = isP ? '' : 'none';
  isPress = isP;
  updatePreview();
}

function updatePreview() {
  const type = document.getElementById('recipeType').value;
  const count = document.getElementById('resultCount').value;
  const result = builderResult;
  const grid = isPress ? null : builderGrid;

  let html = '';
  if (!result) { document.getElementById('recipePreview').innerHTML = '<span style="color:var(--parchment-faint)">Set result item</span>'; return; }

  html += `<div style="margin-bottom:6px"><span style="color:var(--parchment-faint)">Type: </span><span style="color:var(--brass-bright)">${type}</span></div>`;
  html += `<div><span style="color:var(--parchment-faint)">Result: </span><span style="color:var(--parchment)">${result} ×${count}</span></div>`;

  if (!isPress) {
    const filled = builderGrid.filter(Boolean).length;
    html += `<div style="margin-top:4px"><span style="color:var(--parchment-faint)">Ingredients: </span><span style="color:var(--parchment)">${filled} slots</span></div>`;
  } else {
    const ing = builderGrid[4];
    html += `<div style="margin-top:4px"><span style="color:var(--parchment-faint)">Input: </span><span style="color:var(--parchment)">${ing||'not set'}</span></div>`;
  }

  document.getElementById('recipePreview').innerHTML = html;
}

// ── Item picker ───────────────────────────────────────────────────────────
let popupItems = [];
function buildPopupList(items) { popupItems = items; }

function openItemPicker(slotIdx, forPress) {
  pickerTarget = slotIdx;
  document.getElementById('overlay').classList.add('show');
  document.getElementById('itemPopup').classList.add('show');
  document.getElementById('popupSearch').value = '';
  filterPopup();
  setTimeout(() => document.getElementById('popupSearch').focus(), 50);
}

function closeItemPicker() {
  document.getElementById('overlay').classList.remove('show');
  document.getElementById('itemPopup').classList.remove('show');
}

function filterPopup() {
  const q = document.getElementById('popupSearch').value.toLowerCase();
  const list = document.getElementById('popupList');
  const filtered = popupItems.filter(i =>
    !q || i.id.toLowerCase().includes(q) || i.name.toLowerCase().includes(q)
  ).slice(0, 80);

  list.innerHTML = '';
  filtered.forEach(item => {
    const el = document.createElement('div');
    el.className = 'popup-item';
    const tex = item.texture;
    el.innerHTML = `
      <div class="popup-item-icon">
        ${tex ? `<img src="/${tex}" onerror="this.parentElement.innerHTML='📦'">` : '📦'}
      </div>
      <div>
        <div class="popup-item-name">${item.name || item.id.split(':')[1]}</div>
        <div class="popup-item-id">${item.id}</div>
      </div>`;
    el.addEventListener('click', () => selectItem(item.id));
    list.appendChild(el);
  });
}

function selectItem(itemId) {
  closeItemPicker();
  if (pickerTarget === -1) {
    // result slot
    builderResult = itemId;
    const el = document.getElementById('resultSlot');
    const tex = craftableMap[itemId]?.texture;
    if (tex) {
      el.innerHTML = `<img src="/${tex}" style="width:100%;height:100%;image-rendering:pixelated">`;
    } else {
      el.innerHTML = `<span style="font-size:11px;text-align:center;padding:4px">${itemId.split(':')[1]}</span>`;
    }
    el.classList.add('filled');
    document.getElementById('resultSlot').classList.add('filled');
  } else {
    builderGrid[pickerTarget] = itemId;
    // also update press slot display
    if (pickerTarget === 4 && isPress) {
      const el = document.getElementById('pressSlot');
      const tex = craftableMap[itemId]?.texture;
      if (tex) el.innerHTML = `<img src="/${tex}" style="width:100%;height:100%;image-rendering:pixelated">`;
      else el.innerHTML = `<span style="font-size:10px">${itemId.split(':')[1]}</span>`;
    }
    refreshGrid();
  }
  updatePreview();
}

// ── Save recipe ───────────────────────────────────────────────────────────
async function saveRecipe() {
  if (!builderResult) { showToast('Set result item first', 'error'); return; }

  const type = document.getElementById('recipeType').value;
  const count = parseInt(document.getElementById('resultCount').value) || 1;
  const name = document.getElementById('recipeName').value.trim();

  // for press recipes, ingredient is in slot 4 (index 4)
  const grid = isPress
    ? builderGrid.map((v,i) => i === 4 ? v : null)
    : [...builderGrid];

  const filledSlots = grid.filter(Boolean).length;
  if (filledSlots === 0) { showToast('Add at least one ingredient', 'error'); return; }

  try {
    const r = await fetch(`${API}/api/custom-recipes`, {
      method: 'POST',
      headers: {'Content-Type':'application/json'},
      body: JSON.stringify({ resultItem: builderResult, resultCount: count, recipeType: type, grid, name })
    });
    const d = await r.json();
    if (d.success) {
      showToast(`Recipe saved: ${count}x ${builderResult}`, 'success');
      // reset builder
      builderGrid = new Array(9).fill(null);
      builderResult = null;
      document.getElementById('resultSlot').innerHTML = '<span style="font-size:24px">+</span>';
      document.getElementById('resultSlot').classList.remove('filled');
      document.getElementById('pressSlot').innerHTML = '<span style="font-size:20px">+</span>';
      document.getElementById('recipeName').value = '';
      refreshGrid();
    } else {
      showToast('Save failed: ' + d.message, 'error');
    }
  } catch(e) { showToast('Error: ' + e.message, 'error'); }
}

// ── Render recipes list ───────────────────────────────────────────────────
function renderRecipes() {
  const q = (document.getElementById('recipeSearch')?.value || '').toLowerCase();
  const list = document.getElementById('recipeList');
  const filtered = customRecipes.filter(r =>
    !q || r.resultItem.toLowerCase().includes(q) || r.name?.toLowerCase().includes(q)
  );

  if (filtered.length === 0) {
    list.innerHTML = '<div style="text-align:center;padding:40px;color:var(--parchment-faint);font-family:\'JetBrains Mono\',monospace;font-size:12px">No custom recipes yet. Use the builder to create one.</div>';
    return;
  }

  list.innerHTML = '';
  filtered.forEach(r => {
    const tex = craftableMap[r.resultItem]?.texture;
    const el = document.createElement('div');
    el.className = 'recipe-card';

    // mini grid
    let miniGrid = '';
    if (r.grid) {
      miniGrid = '<div class="recipe-mini-grid">';
      for (let i = 0; i < 9; i++) {
        const slot = r.grid[i];
        const stex = slot ? craftableMap[slot]?.texture : null;
        miniGrid += `<div class="recipe-mini-slot">${stex ? `<img src="/${stex}" onerror="this.style.display='none'">` : (slot ? '·' : '')}</div>`;
      }
      miniGrid += '</div>';
    }

    el.innerHTML = `
      <div class="recipe-card-icon">
        ${tex ? `<img src="/${tex}" onerror="this.parentElement.innerHTML='📦'">` : '📦'}
      </div>
      <div class="recipe-card-info">
        <div class="recipe-card-name">${r.name || r.resultItem.split(':')[1]}</div>
        <div class="recipe-card-id">${r.resultItem} × ${r.resultCount || 1}</div>
        <span class="recipe-card-type">${r.recipeType}</span>
      </div>
      ${miniGrid}
      <div style="display:flex;flex-direction:column;gap:6px">
        <button class="btn btn-primary btn-sm" onclick="craftCustom('${r.resultItem}')">⚙ Craft</button>
        <button class="btn btn-danger btn-sm" onclick="deleteRecipe('${encodeURIComponent(r.id)}')">✕ Delete</button>
      </div>`;
    list.appendChild(el);
  });
}

async function deleteRecipe(encodedId) {
  if (!confirm('Delete this recipe?')) return;
  const r = await fetch(`${API}/api/custom-recipes/${encodedId}`, { method: 'DELETE' });
  const d = await r.json();
  if (d.success) showToast('Recipe deleted', 'success');
  else showToast('Delete failed', 'error');
  await loadCustomRecipes();
}

async function craftCustom(itemId) {
  const amount = parseInt(prompt(`How many ${itemId}?`, '1')) || 1;
  const r = await fetch(`${API}/api/craft`, {
    method: 'POST',
    headers: {'Content-Type':'application/json'},
    body: JSON.stringify({ itemId, amount })
  });
  const d = await r.json();
  if (d.success) { showToast(`Queued ${amount}x ${itemId}`, 'success'); switchTab('queue'); }
  else showToast('Failed: ' + d.message, 'error');
}

// ── Render queue ──────────────────────────────────────────────────────────
function renderQueue() {
  const tbody = document.getElementById('queueBody');
  const empty = document.getElementById('queueEmpty');
  const badge = document.getElementById('queueBadge');
  badge.textContent = craftQueue.length;
  document.getElementById('hGear').classList.toggle('busy', craftQueue.some(j => j.status === 'crafting'));

  if (craftQueue.length === 0) {
    tbody.innerHTML = '';
    empty.style.display = '';
    document.querySelector('#queueTable').style.display = 'none';
    return;
  }
  empty.style.display = 'none';
  document.querySelector('#queueTable').style.display = '';

  tbody.innerHTML = '';
  craftQueue.forEach(job => {
    const tex = craftableMap[job.itemId]?.texture;
    const age = job.startedAt ? Math.round((Date.now() - job.startedAt)/1000)+'s' : '—';
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td><div style="width:32px;height:32px;background:var(--bg-panel-raised);border:1px solid var(--rivet);border-radius:3px;display:flex;align-items:center;justify-content:center">
        ${tex ? `<img src="/${tex}" style="width:100%;height:100%;image-rendering:pixelated" onerror="this.parentElement.innerHTML='📦'">` : '📦'}
      </div></td>
      <td style="color:var(--parchment)">${job.itemId}</td>
      <td>×${job.amount}</td>
      <td><span class="log-status ${job.status}">${job.status.toUpperCase()}</span></td>
      <td>${age}</td>
      <td>${job.status === 'pending' ? `<button class="btn btn-danger btn-sm" onclick="cancelJob(${job.id})">Cancel</button>` : '—'}</td>`;
    tbody.appendChild(tr);
  });
}

async function cancelJob(id) {
  const r = await fetch(`${API}/api/queue/${id}/cancel`, { method: 'POST', headers: {'Content-Type':'application/json'}, body: '{}' });
  const d = await r.json();
  if (d.success) showToast('Job cancelled', 'success');
  await loadQueue();
}

// ── Render log ────────────────────────────────────────────────────────────
function renderLog() {
  const list = document.getElementById('logList');
  const badge = document.getElementById('historyBadge');
  badge.textContent = craftLog.length;
  document.getElementById('logCount').textContent = craftLog.length;

  if (craftLog.length === 0) {
    list.innerHTML = '<div style="text-align:center;padding:40px;color:var(--parchment-faint);font-family:\'JetBrains Mono\',monospace;font-size:12px">No craft history yet</div>';
    return;
  }

  list.innerHTML = '';
  craftLog.slice(0, 100).forEach(entry => {
    const tex = craftableMap[entry.itemId]?.texture;
    const ts = new Date(entry.completedAt || entry.failedAt || entry.cancelledAt || Date.now());
    const timeStr = ts.toLocaleTimeString();
    const dur = entry.durationMs ? ` · ${(entry.durationMs/1000).toFixed(1)}s` : '';

    const el = document.createElement('div');
    el.className = `log-entry ${entry.status}`;
    el.innerHTML = `
      <div class="log-icon">
        ${tex ? `<img src="/${tex}" onerror="this.parentElement.innerHTML='📦'">` : '📦'}
      </div>
      <div style="flex:1">
        <div style="color:var(--parchment);font-size:12px">${entry.itemId}</div>
        <div style="color:var(--parchment-faint);font-size:10px">×${entry.amount} · ${timeStr}${dur}</div>
        ${entry.error ? `<div style="color:var(--rust);font-size:10px">Error: ${entry.error}</div>` : ''}
      </div>
      <span class="log-status ${entry.status}">${entry.status.toUpperCase()}</span>`;
    list.appendChild(el);
  });
}

async function clearLog() {
  if (!confirm('Clear all craft history?')) return;
  await fetch(`${API}/api/log`, { method: 'DELETE' });
  craftLog = [];
  renderLog();
  showToast('Log cleared', 'success');
}

// ── Toast ─────────────────────────────────────────────────────────────────
function showToast(msg, type) {
  const c = document.getElementById('toastContainer');
  const t = document.createElement('div');
  t.className = `toast ${type}`;
  t.textContent = msg;
  c.appendChild(t);
  setTimeout(() => { t.classList.add('leaving'); setTimeout(() => t.remove(), 200); }, 3200);
}

document.addEventListener('keydown', e => { if (e.key === 'Escape') closeItemPicker(); });
init();
