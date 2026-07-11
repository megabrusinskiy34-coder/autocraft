const API = window.location.origin;

// ─────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────
let itemsMap      = {};   // id → {id,name,texture,namespace,count}  (all known items)
let customRecipes = [];
let craftQueue    = [];
let craftLog      = [];
let liveInventory = [];   // items currently in storage (from /api/inventory)

// Builder
let builderGrid   = new Array(9).fill(null); // slot index 0-8 → itemId|null
let builderResult = null;
let isPress       = false;

// Drag
let dragItemId    = null;

// ─────────────────────────────────────────────────────────────────────────
// Boot
// ─────────────────────────────────────────────────────────────────────────
async function init() {
  // Load items from /api/items - has textures already baked in
  await loadCraftableItems();
  // Try to load live inventory for storage panel
  await loadInventory();
  await loadCustomRecipes();
  await loadQueue();
  await loadLog();
  buildGrid();
  renderStoragePanel();
  connectSSE();
}

// ─────────────────────────────────────────────────────────────────────────
// Item texture helper — ONE source of truth
// tex is stored as "textures/namespace__name.png"
// static files served at /textures/… by express
// ─────────────────────────────────────────────────────────────────────────
function texUrl(itemId) {
  const item = itemsMap[itemId];
  if (item && item.texture) return '/' + item.texture;
  return null;
}

function itemImg(itemId, size) {
  const url = texUrl(itemId);
  const sz  = size || '100%';
  if (url) {
    return `<img src="${url}" style="width:${sz};height:${sz};image-rendering:pixelated;display:block"
      onerror="this.style.display='none';this.nextSibling.style.display='flex'">
      <span style="display:none;width:100%;height:100%;align-items:center;justify-content:center;font-size:14px">📦</span>`;
  }
  return `<span style="display:flex;align-items:center;justify-content:center;width:100%;height:100%;font-size:14px">📦</span>`;
}

// ─────────────────────────────────────────────────────────────────────────
// Data loading
// ─────────────────────────────────────────────────────────────────────────
async function loadCraftableItems() {
  try {
    const r = await fetch(`${API}/api/items`);
    const d = await r.json();
    (d.items || []).forEach(i => {
      itemsMap[i.id] = { ...i, count: itemsMap[i.id]?.count || 0 };
    });
  } catch(e) { console.error('loadCraftableItems:', e); }
}

async function loadInventory() {
  try {
    const r = await fetch(`${API}/api/inventory`);
    const d = await r.json();
    if (d.online && d.items) {
      liveInventory = d.items;
      // Merge into itemsMap with counts + textures
      d.items.forEach(i => {
        if (!itemsMap[i.id]) {
          itemsMap[i.id] = {
            id: i.id,
            name: i.name || i.id.split(':')[1] || i.id,
            namespace: i.namespace || i.id.split(':')[0],
            texture: null,
            count: i.count
          };
        } else {
          itemsMap[i.id].count = i.count;
        }
      });
      renderStoragePanel();
    }
  } catch {}
}

async function loadCustomRecipes() {
  try {
    const r = await fetch(`${API}/api/custom-recipes`);
    const d = await r.json();
    customRecipes = d.recipes || [];
    renderRecipes();
    document.getElementById('customCount').textContent = customRecipes.length;
  } catch {}
}

async function loadQueue() {
  try {
    const r = await fetch(`${API}/api/queue`);
    const d = await r.json();
    craftQueue = d.queue || [];
    renderQueue();
  } catch {}
}

async function loadLog() {
  try {
    const r = await fetch(`${API}/api/log?limit=200`);
    const d = await r.json();
    craftLog = d.log || [];
    renderLog();
    document.getElementById('logCount').textContent = d.total || 0;
  } catch {}
}

// ─────────────────────────────────────────────────────────────────────────
// SSE — live updates
// ─────────────────────────────────────────────────────────────────────────
function connectSSE() {
  const es  = new EventSource(`${API}/api/events`);
  const dot = document.getElementById('sseStatus');
  const txt = document.getElementById('sseText');

  es.addEventListener('inventory', async () => {
    await loadInventory();
  });
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

  es.onopen  = () => { dot.classList.add('online');    txt.textContent = 'LIVE';       };
  es.onerror = () => { dot.classList.remove('online'); txt.textContent = 'OFFLINE'; };
}


// ─────────────────────────────────────────────────────────────────────────
// Tab switching
// ─────────────────────────────────────────────────────────────────────────
function switchTab(name) {
  document.querySelectorAll('.tab').forEach((t,i) => {
    t.classList.toggle('active', ['builder','recipes','queue','history'][i] === name);
  });
  document.querySelectorAll('.tab-content').forEach(c => {
    c.classList.toggle('active', c.id === 'tab-'+name);
  });
}

// ─────────────────────────────────────────────────────────────────────────
// Storage panel (left side of builder)
// Drag items from here into craft grid slots
// ─────────────────────────────────────────────────────────────────────────
function renderStoragePanel() {
  const panel = document.getElementById('storagePanel');
  const search = (document.getElementById('storageSearch')?.value || '').toLowerCase();
  if (!panel) return;

  // Sort by count desc, filter by search
  let items = Object.values(itemsMap).filter(i => i.count > 0);
  if (items.length === 0) {
    // Fallback: show all craftable items
    items = Object.values(itemsMap);
  }

  if (search) {
    items = items.filter(i => i.id.toLowerCase().includes(search) ||
                               (i.name||'').toLowerCase().includes(search));
  }

  items.sort((a, b) => (b.count||0) - (a.count||0) || a.id.localeCompare(b.id));
  items = items.slice(0, 200);

  panel.innerHTML = '';
  items.forEach(item => {
    const el = document.createElement('div');
    el.className = 'storage-item';
    el.title = item.id + (item.count ? ` (${item.count})` : '');
    el.draggable = true;
    el.innerHTML = `
      <div class="storage-item-icon">${itemImg(item.id)}</div>
      ${item.count > 0 ? `<div class="storage-item-count">${fmtCount(item.count)}</div>` : ''}
      <div class="storage-item-name">${(item.name||item.id.split(':')[1]||item.id).slice(0,9)}</div>`;

    // Drag start
    el.addEventListener('dragstart', e => {
      dragItemId = item.id;
      e.dataTransfer.effectAllowed = 'copy';
      el.style.opacity = '0.5';
    });
    el.addEventListener('dragend', () => { el.style.opacity = ''; dragItemId = null; });

    // Click also selects (for touch / no-drag)
    el.addEventListener('click', () => openClickPicker(item.id));

    panel.appendChild(el);
  });
}

function fmtCount(n) {
  if (n >= 1000000) return (n/1000000).toFixed(1)+'M';
  if (n >= 1000)    return (n/1000).toFixed(1)+'K';
  return String(n);
}

// When user clicks a storage item → select which slot to put it in
let pendingClickItem = null;
function openClickPicker(itemId) {
  pendingClickItem = itemId;
  showToast(`Selected: ${itemId.split(':')[1]} — now click a recipe slot`, 'success');
}

// ─────────────────────────────────────────────────────────────────────────
// Craft Grid
// ─────────────────────────────────────────────────────────────────────────
function buildGrid() {
  const g = document.getElementById('craftGrid');
  g.innerHTML = '';
  for (let i = 0; i < 9; i++) {
    const slot = document.createElement('div');
    slot.className = 'craft-slot';
    slot.dataset.idx = i;
    slot.innerHTML = `<span class="slot-num">${i+1}</span>`;

    // Drop target
    slot.addEventListener('dragover',  e => { e.preventDefault(); e.dataTransfer.dropEffect='copy'; slot.classList.add('drag-over'); });
    slot.addEventListener('dragleave', () => slot.classList.remove('drag-over'));
    slot.addEventListener('drop',      e => { e.preventDefault(); slot.classList.remove('drag-over'); if (dragItemId) setSlot(i, dragItemId); });

    // Click: either place pending item or open search popup
    slot.addEventListener('click', () => {
      if (pendingClickItem) { setSlot(i, pendingClickItem); pendingClickItem = null; }
      else openSlotPicker(i);
    });

    // Right-click clears
    slot.addEventListener('contextmenu', e => { e.preventDefault(); setSlot(i, null); });
    g.appendChild(slot);
  }
  refreshGrid();
}

function setSlot(i, itemId) {
  builderGrid[i] = itemId;
  refreshGrid();
}

function refreshGrid() {
  for (let i = 0; i < 9; i++) {
    const el = document.querySelector(`#craftGrid .craft-slot[data-idx="${i}"]`);
    if (!el) continue;
    const id = builderGrid[i];
    el.classList.toggle('filled', !!id);
    if (id) {
      el.innerHTML = `<span class="slot-num">${i+1}</span>${itemImg(id)}`;
    } else {
      el.innerHTML = `<span class="slot-num">${i+1}</span>`;
    }
    // re-attach drag events (innerHTML wipes them on parent)
    el.addEventListener('dragover',  e => { e.preventDefault(); el.classList.add('drag-over'); });
    el.addEventListener('dragleave', () => el.classList.remove('drag-over'));
    el.addEventListener('drop',      e => { e.preventDefault(); el.classList.remove('drag-over'); if (dragItemId) setSlot(i, dragItemId); });
  }
  updatePreview();
}

function onTypeChange() {
  const t = document.getElementById('recipeType').value;
  const isP = t.startsWith('create:') && t !== 'create:mechanical_crafting';
  document.getElementById('gridSection').style.display   = isP ? 'none' : '';
  document.getElementById('pressSection').style.display  = isP ? '' : 'none';
  isPress = isP;
  updatePreview();
}

function updatePreview() {
  const type  = document.getElementById('recipeType').value;
  const count = document.getElementById('resultCount').value;
  if (!builderResult) {
    document.getElementById('recipePreview').innerHTML =
      '<span style="color:var(--parchment-faint)">Set result item →</span>';
    return;
  }
  const filled = isPress ? (builderGrid[4] ? 1 : 0) : builderGrid.filter(Boolean).length;
  document.getElementById('recipePreview').innerHTML = `
    <div style="margin-bottom:4px"><span style="color:var(--parchment-faint)">Type: </span><span style="color:var(--brass-bright)">${type}</span></div>
    <div><span style="color:var(--parchment-faint)">Result: </span><span style="color:var(--parchment)">${builderResult} ×${count}</span></div>
    <div style="margin-top:4px"><span style="color:var(--parchment-faint)">Slots: </span><span style="color:var(--parchment)">${filled}</span></div>`;
}


// ─────────────────────────────────────────────────────────────────────────
// Slot picker popup (search all items to place in a slot)
// ─────────────────────────────────────────────────────────────────────────
let pickerTarget = null;

function openSlotPicker(slotIdx) {
  pickerTarget = slotIdx;
  document.getElementById('overlay').classList.add('show');
  document.getElementById('itemPopup').classList.add('show');
  document.getElementById('popupSearch').value = '';
  filterPopup();
  setTimeout(() => document.getElementById('popupSearch').focus(), 50);
}

function openResultPicker() {
  pickerTarget = -1;
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
  const q    = document.getElementById('popupSearch').value.toLowerCase().trim();
  const list = document.getElementById('popupList');

  let items = Object.values(itemsMap);
  if (q) {
    items = items.filter(i => i.id.toLowerCase().includes(q) || (i.name||'').toLowerCase().includes(q));
    items.sort((a,b) => {
      const an = (a.name||'').toLowerCase(), bn = (b.name||'').toLowerCase();
      return (an.startsWith(q)?0:1) - (bn.startsWith(q)?0:1) || an.localeCompare(bn);
    });
  } else {
    // Default: in-storage items first, then rest alphabetically
    items.sort((a,b) => (b.count||0)-(a.count||0) || a.id.localeCompare(b.id));
  }

  items = items.slice(0, 120);
  list.innerHTML = '';

  if (!items.length) {
    list.innerHTML = '<div style="padding:20px;text-align:center;color:var(--parchment-faint);font-size:11px;font-family:\'JetBrains Mono\',monospace">Nothing found</div>';
    return;
  }

  items.forEach(item => {
    const el  = document.createElement('div');
    el.className = 'popup-item';
    el.innerHTML = `
      <div class="popup-item-icon">${itemImg(item.id, '32px')}</div>
      <div>
        <div class="popup-item-name">${item.name || item.id.split(':')[1] || item.id}</div>
        <div class="popup-item-id">${item.id}${item.count>0?' · '+fmtCount(item.count):''}</div>
      </div>`;
    el.addEventListener('click', () => pickItem(item.id));
    list.appendChild(el);
  });
}

function pickItem(itemId) {
  closeItemPicker();
  if (pickerTarget === -1) {
    builderResult = itemId;
    const el = document.getElementById('resultSlot');
    el.innerHTML = itemImg(itemId);
    el.classList.add('filled');
  } else if (pickerTarget !== null) {
    if (pickerTarget === 4 && isPress) {
      builderGrid[4] = itemId;
      const el = document.getElementById('pressSlot');
      el.innerHTML = itemImg(itemId);
    } else {
      setSlot(pickerTarget, itemId);
    }
  }
  updatePreview();
}

// ─────────────────────────────────────────────────────────────────────────
// Save recipe
// ─────────────────────────────────────────────────────────────────────────
async function saveRecipe() {
  if (!builderResult) { showToast('Set result item first', 'error'); return; }
  const type  = document.getElementById('recipeType').value;
  const count = parseInt(document.getElementById('resultCount').value) || 1;
  const name  = document.getElementById('recipeName').value.trim();
  const grid  = isPress ? builderGrid.map((v,i) => i===4?v:null) : [...builderGrid];

  if (!grid.some(Boolean)) { showToast('Add at least one ingredient', 'error'); return; }

  const r = await fetch(`${API}/api/custom-recipes`, {
    method: 'POST',
    headers: {'Content-Type':'application/json'},
    body: JSON.stringify({ resultItem: builderResult, resultCount: count, recipeType: type, grid, name })
  });
  const d = await r.json();
  if (d.success) {
    showToast(`Saved: ${count}× ${builderResult}`, 'success');
    builderGrid   = new Array(9).fill(null);
    builderResult = null;
    document.getElementById('resultSlot').innerHTML  = '<span style="font-size:24px">+</span>';
    document.getElementById('resultSlot').classList.remove('filled');
    document.getElementById('pressSlot').innerHTML   = '<span style="font-size:20px">+</span>';
    document.getElementById('recipeName').value      = '';
    refreshGrid();
  } else {
    showToast('Failed: ' + d.message, 'error');
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Render: Custom Recipes list
// ─────────────────────────────────────────────────────────────────────────
function renderRecipes() {
  const q    = (document.getElementById('recipeSearch')?.value || '').toLowerCase();
  const list = document.getElementById('recipeList');
  const filtered = customRecipes.filter(r =>
    !q || r.resultItem.toLowerCase().includes(q) || (r.name||'').toLowerCase().includes(q));

  if (!filtered.length) {
    list.innerHTML = '<div style="text-align:center;padding:40px;color:var(--parchment-faint);font-family:\'JetBrains Mono\',monospace;font-size:12px">No custom recipes. Use Builder tab.</div>';
    return;
  }

  list.innerHTML = '';
  filtered.forEach(r => {
    const el = document.createElement('div');
    el.className = 'recipe-card';

    let miniGrid = '';
    if (r.grid) {
      miniGrid = '<div class="recipe-mini-grid">';
      for (let i = 0; i < 9; i++) {
        const slot = r.grid[i];
        miniGrid += `<div class="recipe-mini-slot">${slot ? itemImg(slot, '18px') : ''}</div>`;
      }
      miniGrid += '</div>';
    }

    el.innerHTML = `
      <div class="recipe-card-icon">${itemImg(r.resultItem)}</div>
      <div class="recipe-card-info">
        <div class="recipe-card-name">${r.name || r.resultItem.split(':')[1]}</div>
        <div class="recipe-card-id">${r.resultItem} × ${r.resultCount||1}</div>
        <span class="recipe-card-type">${r.recipeType}</span>
      </div>
      ${miniGrid}
      <div style="display:flex;flex-direction:column;gap:6px">
        <button class="btn btn-primary btn-sm" onclick="craftCustom('${r.resultItem}')">⚙ Craft</button>
        <button class="btn btn-danger btn-sm" onclick="deleteRecipe('${encodeURIComponent(r.id)}')">✕</button>
      </div>`;
    list.appendChild(el);
  });
}

async function deleteRecipe(enc) {
  if (!confirm('Delete?')) return;
  const r = await fetch(`${API}/api/custom-recipes/${enc}`, { method: 'DELETE' });
  if ((await r.json()).success) showToast('Deleted', 'success');
  else showToast('Delete failed', 'error');
}

async function craftCustom(itemId) {
  const amount = parseInt(prompt(`How many ${itemId.split(':')[1]}?`, '1')) || 1;
  const r = await fetch(`${API}/api/craft`, {
    method: 'POST', headers: {'Content-Type':'application/json'},
    body: JSON.stringify({ itemId, amount })
  });
  const d = await r.json();
  if (d.success) { showToast(`Queued ${amount}× ${itemId}`, 'success'); switchTab('queue'); }
  else showToast('Failed: ' + d.message, 'error');
}

// ─────────────────────────────────────────────────────────────────────────
// Render: Queue
// ─────────────────────────────────────────────────────────────────────────
function renderQueue() {
  const tbody = document.getElementById('queueBody');
  const empty = document.getElementById('queueEmpty');
  const badge = document.getElementById('queueBadge');
  badge.textContent = craftQueue.length;
  document.getElementById('hGear').classList.toggle('busy', craftQueue.some(j=>j.status==='crafting'));

  const table = document.getElementById('queueTable');
  if (!craftQueue.length) { tbody.innerHTML=''; empty.style.display=''; table.style.display='none'; return; }
  empty.style.display='none'; table.style.display='';
  tbody.innerHTML = '';
  craftQueue.forEach(job => {
    const age = job.startedAt ? Math.round((Date.now()-job.startedAt)/1000)+'s' : '—';
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td><div style="width:32px;height:32px;background:var(--bg-panel-raised);border:1px solid var(--rivet);border-radius:3px;overflow:hidden;display:flex;align-items:center;justify-content:center">
        ${itemImg(job.itemId, '32px')}</div></td>
      <td style="color:var(--parchment)">${job.itemId}</td>
      <td>×${job.amount}</td>
      <td><span class="log-status ${job.status}">${job.status.toUpperCase()}</span></td>
      <td>${age}</td>
      <td>${job.status==='pending'?`<button class="btn btn-danger btn-sm" onclick="cancelJob(${job.id})">Cancel</button>`:'—'}</td>`;
    tbody.appendChild(tr);
  });
}

async function cancelJob(id) {
  await fetch(`${API}/api/queue/${id}/cancel`,{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'});
  await loadQueue();
}

// ─────────────────────────────────────────────────────────────────────────
// Render: Log
// ─────────────────────────────────────────────────────────────────────────
function renderLog() {
  const list  = document.getElementById('logList');
  const badge = document.getElementById('historyBadge');
  const q     = (document.getElementById('historySearch')?.value || '').toLowerCase();

  badge.textContent = craftLog.length;
  document.getElementById('logCount').textContent = craftLog.length;

  let filtered = q ? craftLog.filter(e=>e.itemId?.toLowerCase().includes(q)) : craftLog;

  if (!filtered.length) {
    list.innerHTML='<div style="text-align:center;padding:40px;color:var(--parchment-faint);font-family:\'JetBrains Mono\',monospace;font-size:12px">No history</div>';
    return;
  }
  list.innerHTML = '';
  filtered.slice(0,100).forEach(entry => {
    const ts  = new Date(entry.completedAt||entry.failedAt||entry.cancelledAt||Date.now());
    const dur = entry.durationMs ? ` · ${(entry.durationMs/1000).toFixed(1)}s` : '';
    const el  = document.createElement('div');
    el.className = `log-entry ${entry.status}`;
    el.innerHTML = `
      <div class="log-icon" style="overflow:hidden">${itemImg(entry.itemId, '32px')}</div>
      <div style="flex:1">
        <div style="color:var(--parchment);font-size:12px">${entry.itemId}</div>
        <div style="color:var(--parchment-faint);font-size:10px">×${entry.amount} · ${ts.toLocaleTimeString()}${dur}</div>
        ${entry.error?`<div style="color:var(--rust);font-size:10px">${entry.error}</div>`:''}
      </div>
      <span class="log-status ${entry.status}">${entry.status.toUpperCase()}</span>`;
    list.appendChild(el);
  });
}

async function clearLog() {
  if (!confirm('Clear all history?')) return;
  await fetch(`${API}/api/log`,{method:'DELETE'});
  craftLog = []; renderLog();
  showToast('Cleared','success');
}

// ─────────────────────────────────────────────────────────────────────────
// Toast
// ─────────────────────────────────────────────────────────────────────────
function showToast(msg, type) {
  const c = document.getElementById('toastContainer');
  const t = document.createElement('div');
  t.className = `toast ${type}`; t.textContent = msg;
  c.appendChild(t);
  setTimeout(()=>{ t.classList.add('leaving'); setTimeout(()=>t.remove(),200); },3200);
}

document.addEventListener('keydown', e => { if (e.key==='Escape') closeItemPicker(); });
init();
