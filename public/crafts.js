const API = window.location.origin;

// ── State ─────────────────────────────────────────────────────────────────
let allItems      = [];   // [{id,name,texture,namespace}] — ALL items with textures
let craftableMap  = {};   // id -> item
let customRecipes = [];
let craftQueue    = [];
let craftLog      = [];

// Builder state
let builderGrid   = new Array(9).fill(null);
let builderResult = null;
let pickerTarget  = null;
let isPress       = false;

// ── Init ──────────────────────────────────────────────────────────────────
async function init() {
  await loadItems();       // loads ALL items (craftable + inventory)
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
  es.addEventListener('inventory', async () => {
    // Re-merge inventory items into allItems for up-to-date icons
    await mergeInventoryItems();
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

// Load ALL craftable items with textures from recipes
async function loadItems() {
  try {
    // Load textures map (all ~1600+ items)
    let texMap = {};
    try {
      const tr = await fetch(`${API}/api/textures`);
      if (tr.ok) texMap = await tr.json();
    } catch {}

    // Load craftable items from recipes
    const r = await fetch(`${API}/api/items`);
    const d = await r.json();
    const base = d.items || [];

    craftableMap = {};
    base.forEach(i => {
      // Attach texture from texMap if not already present
      if (!i.texture && texMap[i.id]) i.texture = texMap[i.id];
      craftableMap[i.id] = i;
    });

    // Also build allItems from full texMap so picker shows ALL items
    const texItems = Object.entries(texMap).map(([id, tex]) => ({
      id,
      name: id.split(':')[1]?.replace(/_/g, ' ') || id,
      namespace: id.split(':')[0] || 'minecraft',
      texture: tex,
      recipeTypes: craftableMap[id]?.recipeTypes || []
    }));

    allItems = texItems;

    // Make sure craftable items are in allItems too
    base.forEach(i => {
      if (!allItems.find(a => a.id === i.id)) allItems.push(i);
    });

    // Sort alphabetically
    allItems.sort((a, b) => a.id.localeCompare(b.id));

    // Merge live inventory
    await mergeInventoryItems();
  } catch(e) { console.error('loadItems failed:', e); }
}

// Merge items visible in live inventory (they may not be in recipes)
async function mergeInventoryItems() {
  try {
    const r = await fetch(`${API}/api/inventory`);
    const d = await r.json();
    if (!d.online || !d.items) return;

    d.items.forEach(invItem => {
      if (!craftableMap[invItem.id]) {
        // Add to map with texture lookup from existing items or null
        const existing = allItems.find(i => i.id === invItem.id);
        if (!existing) {
          const newItem = {
            id: invItem.id,
            name: invItem.name || invItem.id.split(':')[1] || invItem.id,
            namespace: invItem.namespace || invItem.id.split(':')[0],
            texture: null,
            recipeTypes: []
          };
          allItems.push(newItem);
          craftableMap[invItem.id] = newItem;
        }
      }
    });
  } catch {}
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
      el.classList.add('filled');
      el.innerHTML = `<span class="slot-num">${i+1}</span>${renderItemIcon(item, '100%')}`;
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

function openItemPicker(slotIdx) {
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
  const q = document.getElementById('popupSearch').value.toLowerCase().trim();
  const list = document.getElementById('popupList');

  // Search across ALL items - sort: query match in name first, then id
  let filtered = allItems;
  if (q) {
    filtered = allItems.filter(i =>
      i.id.toLowerCase().includes(q) || (i.name||'').toLowerCase().includes(q)
    );
    // sort: name starts with query first
    filtered.sort((a, b) => {
      const an = (a.name||'').toLowerCase(), bn = (b.name||'').toLowerCase();
      const as = an.startsWith(q) ? 0 : 1;
      const bs = bn.startsWith(q) ? 0 : 1;
      return as - bs || an.localeCompare(bn);
    });
  }

  filtered = filtered.slice(0, 100);
  list.innerHTML = '';

  if (filtered.length === 0) {
    list.innerHTML = '<div style="padding:20px;text-align:center;color:var(--parchment-faint);font-family:\'JetBrains Mono\',monospace;font-size:11px">No items found</div>';
    return;
  }

  filtered.forEach(item => {
    const el = document.createElement('div');
    el.className = 'popup-item';
    const tex = item.texture;
    el.innerHTML = `
      <div class="popup-item-icon">
        ${tex ? `<img src="/${tex}" onerror="this.parentElement.innerHTML='<span style=font-size:16px>📦</span>'">` : '<span style="font-size:16px">📦</span>'}
      </div>
      <div>
        <div class="popup-item-name">${item.name || item.id.split(':')[1] || item.id}</div>
        <div class="popup-item-id">${item.id}</div>
      </div>`;
    el.addEventListener('click', () => selectItem(item.id));
    list.appendChild(el);
  });
}

function getTexture(itemId) {
  return craftableMap[itemId]?.texture || null;
}

function renderItemIcon(itemId, size) {
  const tex = getTexture(itemId);
  const s = size || '100%';
  if (tex) return `<img src="/${tex}" style="width:${s};height:${s};image-rendering:pixelated" onerror="this.parentElement.innerHTML='<span style=font-size:18px>📦</span>'">`;
  return `<span style="font-size:18px">📦</span>`;
}

function selectItem(itemId) {
  closeItemPicker();
  if (pickerTarget === -1) {
    builderResult = itemId;
    const el = document.getElementById('resultSlot');
    el.innerHTML = renderItemIcon(itemId, '100%');
    el.classList.add('filled');
  } else {
    builderGrid[pickerTarget] = itemId;
    if (pickerTarget === 4 && isPress) {
      const el = document.getElementById('pressSlot');
      el.innerHTML = renderItemIcon(itemId, '100%');
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
    const el = document.createElement('div');
    el.className = 'recipe-card';

    // mini grid
    let miniGrid = '';
    if (r.grid) {
      miniGrid = '<div class="recipe-mini-grid">';
      for (let i = 0; i < 9; i++) {
        const slot = r.grid[i];
        const stex = slot ? getTexture(slot) : null;
        miniGrid += `<div class="recipe-mini-slot">${stex ? `<img src="/${stex}" onerror="this.style.display='none'">` : (slot ? '<span style="font-size:8px;color:var(--parchment-faint)">·</span>' : '')}</div>`;
      }
      miniGrid += '</div>';
    }

    el.innerHTML = `
      <div class="recipe-card-icon">${renderItemIcon(r.resultItem, '100%')}</div>
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
    const age = job.startedAt ? Math.round((Date.now() - job.startedAt)/1000)+'s' : '—';
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td><div style="width:32px;height:32px;background:var(--bg-panel-raised);border:1px solid var(--rivet);border-radius:3px;display:flex;align-items:center;justify-content:center;overflow:hidden">
        ${renderItemIcon(job.itemId, '32px')}
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
  const q = (document.getElementById('historySearch')?.value || '').toLowerCase();

  badge.textContent = craftLog.length;
  document.getElementById('logCount').textContent = craftLog.length;

  let filtered = craftLog;
  if (q) filtered = craftLog.filter(e => e.itemId?.toLowerCase().includes(q));

  if (filtered.length === 0) {
    list.innerHTML = '<div style="text-align:center;padding:40px;color:var(--parchment-faint);font-family:\'JetBrains Mono\',monospace;font-size:12px">No craft history yet</div>';
    return;
  }

  list.innerHTML = '';
  filtered.slice(0, 100).forEach(entry => {
    const ts = new Date(entry.completedAt || entry.failedAt || entry.cancelledAt || Date.now());
    const timeStr = ts.toLocaleTimeString();
    const dur = entry.durationMs ? ` · ${(entry.durationMs/1000).toFixed(1)}s` : '';

    const el = document.createElement('div');
    el.className = `log-entry ${entry.status}`;
    el.innerHTML = `
      <div class="log-icon" style="overflow:hidden">${renderItemIcon(entry.itemId, '32px')}</div>
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
