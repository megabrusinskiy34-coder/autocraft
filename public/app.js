// ══════════════════════════════════════════════════════════════════════════
// Create AutoCraft - Frontend Logic
// ══════════════════════════════════════════════════════════════════════════

const API_BASE = window.location.origin;

let allItems = [];
let selectedItem = null;

// ── DOM Elements ──────────────────────────────────────────────────────────
const searchInput = document.getElementById('search-input');
const namespaceFilter = document.getElementById('namespace-filter');
const itemsGrid = document.getElementById('items-grid');
const recipeDetails = document.getElementById('recipe-details');
const itemCount = document.getElementById('item-count');
const recipeCount = document.getElementById('recipe-count');

// ── Init ──────────────────────────────────────────────────────────────────
async function init() {
  try {
    // Load stats
    const stats = await fetchJSON('/api/stats');
    itemCount.textContent = `${stats.totalItems} items`;
    recipeCount.textContent = `${stats.totalRecipes} recipes`;

    // Load items
    await loadItems();

    // Event listeners
    searchInput.addEventListener('input', debounce(filterItems, 300));
    namespaceFilter.addEventListener('change', filterItems);
  } catch (err) {
    console.error('Init error:', err);
    showError('Failed to load data from server');
  }
}

// ── API Helpers ───────────────────────────────────────────────────────────
async function fetchJSON(url) {
  const res = await fetch(API_BASE + url);
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.json();
}

// ── Load Items ────────────────────────────────────────────────────────────
async function loadItems() {
  try {
    itemsGrid.innerHTML = '<div class="ae2-loading">Loading items...</div>';
    const data = await fetchJSON('/api/items');
    allItems = data.items;
    renderItems(allItems);
  } catch (err) {
    console.error('Load items error:', err);
    itemsGrid.innerHTML = '<div class="ae2-loading">Error loading items</div>';
  }
}

// ── Filter Items ──────────────────────────────────────────────────────────
function filterItems() {
  const search = searchInput.value.toLowerCase();
  const namespace = namespaceFilter.value;

  const filtered = allItems.filter(item => {
    const matchSearch = !search || item.id.toLowerCase().includes(search);
    const matchNamespace = !namespace || item.namespace === namespace;
    return matchSearch && matchNamespace;
  });

  renderItems(filtered);
}

// ── Render Items Grid ─────────────────────────────────────────────────────
function renderItems(items) {
  if (items.length === 0) {
    itemsGrid.innerHTML = '<div class="ae2-loading">No items found</div>';
    return;
  }

  itemsGrid.innerHTML = items.map(item => `
    <div class="ae2-item" data-item-id="${item.id}" onclick="selectItem('${item.id}')">
      ${item.texture 
        ? `<img src="/${item.texture}" class="ae2-item-icon" alt="${item.name}">`
        : `<div class="ae2-item-icon missing">?</div>`
      }
      <div class="ae2-item-name">${item.name}</div>
    </div>
  `).join('');
}

// ── Select Item ───────────────────────────────────────────────────────────
async function selectItem(itemId) {
  selectedItem = itemId;

  // Update selected state
  document.querySelectorAll('.ae2-item').forEach(el => {
    el.classList.toggle('selected', el.dataset.itemId === itemId);
  });

  // Load recipes
  try {
    recipeDetails.innerHTML = '<div class="ae2-loading">Loading recipes...</div>';
    const data = await fetchJSON(`/api/recipes/${itemId.replace(':', '__')}`);
    renderRecipes(data);
  } catch (err) {
    console.error('Load recipes error:', err);
    recipeDetails.innerHTML = '<div class="ae2-loading">Error loading recipes</div>';
  }
}

// ── Render Recipes ────────────────────────────────────────────────────────
function renderRecipes(data) {
  if (!data.recipes || data.recipes.length === 0) {
    recipeDetails.innerHTML = `
      <div class="ae2-empty-state">
        <div class="ae2-empty-icon">⚠️</div>
        <p>No recipes found for <strong>${data.item}</strong></p>
      </div>
    `;
    return;
  }

  recipeDetails.innerHTML = data.recipes.map(recipe => `
    <div class="ae2-recipe-card">
      <div class="ae2-recipe-header">
        <span class="ae2-recipe-type">${formatRecipeType(recipe.type)}</span>
        <span class="ae2-recipe-id">${recipe.id}</span>
      </div>
      <div class="ae2-recipe-data">${JSON.stringify(recipe.data, null, 2)}</div>
    </div>
  `).join('');
}

// ── Helpers ───────────────────────────────────────────────────────────────
function formatRecipeType(type) {
  return type.split(':').pop().replace(/_/g, ' ');
}

function debounce(fn, delay) {
  let timeout;
  return (...args) => {
    clearTimeout(timeout);
    timeout = setTimeout(() => fn(...args), delay);
  };
}

function showError(msg) {
  itemsGrid.innerHTML = `<div class="ae2-loading" style="color: var(--ae2-warning)">${msg}</div>`;
}

// ── Start ─────────────────────────────────────────────────────────────────
init();
