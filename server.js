const express = require('express');
const cors = require('cors');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;

// ── Middleware ────────────────────────────────────────────────────────────
app.use(cors());
app.use(express.json());
app.use(express.static('public'));
app.use('/textures', express.static('output/textures'));

// ── Load data ─────────────────────────────────────────────────────────────
const recipesDB = JSON.parse(fs.readFileSync('./output/recipes_db.json', 'utf-8'));
const recipesIndex = JSON.parse(fs.readFileSync('./output/recipes_index.json', 'utf-8'));
const itemTextures = JSON.parse(fs.readFileSync('./output/item_textures.json', 'utf-8'));

console.log(`Loaded ${Object.keys(recipesDB).length} recipes`);
console.log(`Loaded ${Object.keys(itemTextures).length} item textures`);

// ── API Endpoints ─────────────────────────────────────────────────────────

// GET /api/items - list all craftable items with textures
app.get('/api/items', (req, res) => {
  try {
    const search = req.query.search?.toLowerCase() || '';
    const namespace = req.query.namespace || '';
    
    // Build list of items from recipes (output items)
    const items = new Set();
    const itemData = [];

    for (const [recipeId, recipe] of Object.entries(recipesDB)) {
      try {
        const data = recipe.data;
        
        // Extract result/output item
        let resultItem = null;
        
        if (data.result) {
          if (typeof data.result === 'string') {
            resultItem = data.result;
          } else if (data.result.item) {
            resultItem = data.result.item;
          } else if (data.result.id) {
            resultItem = data.result.id;
          }
        } else if (data.results && Array.isArray(data.results) && data.results.length > 0) {
          const first = data.results[0];
          if (typeof first === 'string') {
            resultItem = first;
          } else if (first.item) {
            resultItem = first.item;
          } else if (first.id) {
            resultItem = first.id;
          }
        }

        if (resultItem && !items.has(resultItem)) {
          items.add(resultItem);
          
          const itemNs = resultItem.split(':')[0] || 'minecraft';
          const itemName = resultItem.split(':')[1] || resultItem;
          
          // Filter
          if (namespace && itemNs !== namespace) continue;
          if (search && !resultItem.toLowerCase().includes(search)) continue;

          itemData.push({
            id: resultItem,
            name: itemName.replace(/_/g, ' '),
            namespace: itemNs,
            texture: itemTextures[resultItem] || null,
            recipeTypes: [recipe.type],
          });
        }
      } catch (err) {
        // Skip invalid recipe
        console.error(`Error processing recipe ${recipeId}:`, err.message);
      }
    }

    res.json({
      total: itemData.length,
      items: itemData.slice(0, 500), // limit for performance
    });
  } catch (error) {
    console.error('Error in /api/items:', error);
    res.status(500).json({ error: 'Internal server error', message: error.message });
  }
});

// GET /api/recipes/:itemId - get all recipes for an item
app.get('/api/recipes/:itemId', (req, res) => {
  const itemId = req.params.itemId.replace('__', ':'); // create__brass_ingot -> create:brass_ingot
  const recipes = [];

  for (const [recipeId, recipe] of Object.entries(recipesDB)) {
    const data = recipe.data;
    
    let resultItem = null;
    if (data.result) {
      resultItem = typeof data.result === 'string' ? data.result : (data.result.item || data.result.id);
    } else if (data.results?.[0]) {
      const r = data.results[0];
      resultItem = typeof r === 'string' ? r : (r.item || r.id);
    }

    if (resultItem === itemId) {
      recipes.push({
        id: recipeId,
        type: recipe.type,
        namespace: recipe.namespace,
        data: data,
      });
    }
  }

  res.json({ item: itemId, recipes });
});

// GET /api/recipe/:id - get full recipe by id
app.get('/api/recipe/:id', (req, res) => {
  const id = req.params.id;
  const recipe = recipesDB[id];
  if (recipe) {
    res.json(recipe);
  } else {
    res.status(404).json({ error: 'Recipe not found' });
  }
});

// GET /api/search - search items/recipes
app.get('/api/search', (req, res) => {
  const query = req.query.q?.toLowerCase() || '';
  if (!query) {
    return res.json({ items: [], recipes: [] });
  }

  const items = [];
  const recipes = [];

  // Search in item IDs
  for (const itemId of Object.keys(itemTextures)) {
    if (itemId.toLowerCase().includes(query)) {
      items.push({
        id: itemId,
        name: itemId.split(':')[1]?.replace(/_/g, ' ') || itemId,
        texture: itemTextures[itemId],
      });
      if (items.length >= 50) break;
    }
  }

  // Search in recipe IDs
  for (const [recipeId, recipe] of Object.entries(recipesDB)) {
    if (recipeId.toLowerCase().includes(query)) {
      recipes.push({
        id: recipeId,
        type: recipe.type,
        namespace: recipe.namespace,
      });
      if (recipes.length >= 50) break;
    }
  }

  res.json({ items, recipes });
});

// GET /api/stats - statistics
app.get('/api/stats', (req, res) => {
  res.json({
    totalRecipes: Object.keys(recipesDB).length,
    totalItems: Object.keys(itemTextures).length,
    recipeTypes: recipesIndex.by_type,
    namespaces: recipesIndex.by_namespace,
  });
});

// POST /api/inventory - receive inventory from ComputerCraft ME terminal
let liveInventory = null;
let lastInventoryUpdate = null;

app.post('/api/inventory', (req, res) => {
  try {
    const data = req.body;
    
    if (!data || !data.items) {
      return res.status(400).json({ error: 'Invalid data' });
    }
    
    // Store inventory
    liveInventory = {
      computerId: data.computerId,
      timestamp: data.timestamp,
      stats: data.stats,
      items: data.items
    };
    lastInventoryUpdate = Date.now();
    
    console.log(`[INVENTORY] Updated from Computer #${data.computerId}: ${data.items.length} unique items, ${data.stats.totalItems} total`);
    
    res.json({ ok: true, received: data.items.length });
  } catch (error) {
    console.error('Error in /api/inventory:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// GET /api/inventory - get live inventory from ComputerCraft
app.get('/api/inventory', (req, res) => {
  if (!liveInventory) {
    return res.json({
      online: false,
      message: 'No inventory data available. Run me_terminal.lua in ComputerCraft.'
    });
  }
  
  const age = Date.now() - lastInventoryUpdate;
  const isOnline = age < 10000; // Online if updated in last 10 seconds
  
  res.json({
    online: isOnline,
    age: age,
    lastUpdate: new Date(lastInventoryUpdate).toISOString(),
    ...liveInventory
  });
});

// ── Start server ──────────────────────────────────────────────────────────
app.listen(PORT, () => {
  console.log(`\n🚀 Create AutoCraft API running on http://localhost:${PORT}`);
  console.log(`📊 API endpoints:`);
  console.log(`   GET  /api/items?search=brass&namespace=create`);
  console.log(`   GET  /api/recipes/:itemId`);
  console.log(`   GET  /api/search?q=gear`);
  console.log(`   GET  /api/stats`);
  console.log(`   GET  /api/inventory (live from ComputerCraft)`);
  console.log(`   POST /api/inventory (from me_terminal.lua)\n`);
});
