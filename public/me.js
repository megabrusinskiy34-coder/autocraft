const API_URL = window.location.origin;

let inventory = [];
let craftableItems = {};
let selectedItem = null;
let currentFilter = 'all';
let searchQuery = '';
let craftingQueue = [];

// ══════════════════════════════════════════════════════════════════════════
// Init
// ══════════════════════════════════════════════════════════════════════════

async function init() {
    console.log('Initializing ME Terminal...');
    
    // Load craftable items
    await loadCraftableItems();
    
    // Start live inventory updates
    startInventoryPolling();
    
    // Start queue polling
    startQueuePolling();
    
    // Setup event listeners
    setupEventListeners();
}

function setupEventListeners() {
    // Search
    document.getElementById('searchInput').addEventListener('input', (e) => {
        searchQuery = e.target.value.toLowerCase();
        renderInventory();
    });
    
    // Filters
    document.querySelectorAll('.filter-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            document.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            currentFilter = btn.dataset.filter;
            renderInventory();
        });
    });
}

// ══════════════════════════════════════════════════════════════════════════
// API Calls
// ══════════════════════════════════════════════════════════════════════════

async function loadCraftableItems() {
    try {
        const response = await fetch(`${API_URL}/api/items`);
        const data = await response.json();
        
        craftableItems = {};
        data.items.forEach(item => {
            craftableItems[item.id] = item;
        });
        
        console.log(`Loaded ${data.items.length} craftable items`);
    } catch (error) {
        console.error('Error loading craftable items:', error);
    }
}

async function loadInventory() {
    try {
        const response = await fetch(`${API_URL}/api/inventory`);
        const data = await response.json();
        
        if (data.online) {
            // Live inventory from ComputerCraft
            inventory = data.items || [];
            updateStatus(true, data);
            renderInventory();
        } else {
            // Fallback: show all craftable items from recipes
            console.log('CC offline, loading craftable items...');
            await loadCraftableItemsAsInventory();
            updateStatus(false);
        }
    } catch (error) {
        console.error('Error loading inventory:', error);
        // Fallback to craftable items
        await loadCraftableItemsAsInventory();
        updateStatus(false);
    }
}

async function loadCraftableItemsAsInventory() {
    try {
        const response = await fetch(`${API_URL}/api/items`);
        const data = await response.json();
        
        // Convert craftable items to inventory format
        inventory = data.items.map(item => ({
            id: item.id,
            name: item.name,
            namespace: item.namespace,
            count: 0, // Unknown count (not in storage)
            locations: 0
        }));
        
        renderInventory();
    } catch (error) {
        console.error('Error loading craftable items:', error);
    }
}

async function loadQueue() {
    try {
        const response = await fetch(`${API_URL}/api/queue`);
        const data = await response.json();
        craftingQueue = data.queue || [];
        renderQueue();
    } catch (error) {
        console.error('Error loading queue:', error);
    }
}

async function craftItem(itemId, amount) {
    try {
        const response = await fetch(`${API_URL}/api/craft`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ itemId, amount })
        });
        
        const data = await response.json();
        
        if (data.success) {
            showNotification(`Crafting ${amount}x ${itemId}`, 'success');
            loadQueue();
        } else {
            showNotification(`Failed: ${data.message}`, 'error');
        }
    } catch (error) {
        console.error('Error crafting item:', error);
        showNotification('Craft request failed', 'error');
    }
}

// ══════════════════════════════════════════════════════════════════════════
// Rendering
// ══════════════════════════════════════════════════════════════════════════

function renderInventory() {
    const grid = document.getElementById('itemGrid');
    
    // Filter items
    let filteredItems = inventory.filter(item => {
        // Search filter
        if (searchQuery && !item.id.toLowerCase().includes(searchQuery) && 
            !item.name.toLowerCase().includes(searchQuery)) {
            return false;
        }
        
        // Namespace filter
        if (currentFilter !== 'all' && currentFilter !== 'craftable') {
            if (item.namespace !== currentFilter) return false;
        }
        
        // Craftable filter
        if (currentFilter === 'craftable') {
            if (!craftableItems[item.id]) return false;
        }
        
        return true;
    });
    
    // Sort by count (descending)
    filteredItems.sort((a, b) => b.count - a.count);
    
    // Render
    grid.innerHTML = '';
    
    if (filteredItems.length === 0) {
        grid.innerHTML = '<div class="no-items">No items found</div>';
        document.getElementById('gridCount').textContent = '0 items';
        return;
    }
    
    filteredItems.forEach(item => {
        const card = createItemCard(item);
        grid.appendChild(card);
    });
    
    document.getElementById('gridCount').textContent = `${filteredItems.length} items`;
}

function createItemCard(item) {
    const card = document.createElement('div');
    card.className = 'item-card';
    if (selectedItem && selectedItem.id === item.id) {
        card.classList.add('selected');
    }
    
    const icon = document.createElement('div');
    icon.className = 'item-icon';
    
    // Get texture from craftable items
    const texture = craftableItems[item.id]?.texture;
    if (texture) {
        const img = document.createElement('img');
        img.src = `/textures/${texture}`;
        img.onerror = () => { 
            icon.innerHTML = '📦';
            icon.classList.add('missing');
        };
        icon.appendChild(img);
    } else {
        icon.textContent = '📦';
        icon.classList.add('missing');
    }
    
    // Only show count badge if item is in storage (count > 0)
    if (item.count > 0) {
        const count = document.createElement('div');
        count.className = 'item-count';
        count.textContent = formatCount(item.count);
        icon.appendChild(count);
    }
    
    const name = document.createElement('div');
    name.className = 'item-name';
    name.textContent = item.name;
    name.title = item.id; // Show full ID on hover
    
    card.appendChild(icon);
    card.appendChild(name);
    
    card.addEventListener('click', () => {
        selectedItem = item;
        showItemDetails(item);
        document.querySelectorAll('.item-card').forEach(c => c.classList.remove('selected'));
        card.classList.add('selected');
    });
    
    return card;
}

function showItemDetails(item) {
    const content = document.getElementById('detailsContent');
    
    const texture = craftableItems[item.id]?.texture;
    const isCraftable = !!craftableItems[item.id];
    const inStorage = item.count > 0;
    
    content.innerHTML = `
        <div class="item-details">
            <div class="detail-icon">
                ${texture ? `<img src="/textures/${texture}" onerror="this.parentElement.innerHTML='📦'">` : '📦'}
            </div>
            <div class="detail-name">${item.name}</div>
            <div class="detail-id">${item.id}</div>
            
            <div class="detail-stats">
                <div class="stat-row">
                    <span class="stat-label">In Storage:</span>
                    <span class="stat-value">${inStorage ? item.count : 'Not in storage'}</span>
                </div>
                ${inStorage ? `
                <div class="stat-row">
                    <span class="stat-label">Locations:</span>
                    <span class="stat-value">${item.locations}</span>
                </div>
                ` : ''}
                <div class="stat-row">
                    <span class="stat-label">Namespace:</span>
                    <span class="stat-value">${item.namespace}</span>
                </div>
                <div class="stat-row">
                    <span class="stat-label">Craftable:</span>
                    <span class="stat-value">${isCraftable ? 'Yes' : 'No'}</span>
                </div>
            </div>
            
            <button class="craft-btn" ${!isCraftable ? 'disabled' : ''} onclick="openCraftModal('${item.id}')">
                ${isCraftable ? '⚙️ Craft Item' : '❌ Not Craftable'}
            </button>
        </div>
    `;
}

function renderQueue() {
    const queueList = document.getElementById('queueList');
    const queueCount = document.getElementById('queueCount');
    
    if (craftingQueue.length === 0) {
        queueList.innerHTML = '<div class="queue-empty">No crafting jobs</div>';
        queueCount.textContent = '0 active';
        return;
    }
    
    queueList.innerHTML = '';
    
    craftingQueue.forEach(job => {
        const item = document.createElement('div');
        item.className = 'queue-item';
        if (job.status === 'crafting') {
            item.classList.add('active');
        }
        
        const texture = craftableItems[job.itemId]?.texture;
        
        item.innerHTML = `
            <div class="queue-icon">
                ${texture ? `<img src="/textures/${texture}">` : '📦'}
            </div>
            <div class="queue-info">
                <div class="queue-item-name">${job.itemId.split(':')[1] || job.itemId}</div>
                <div class="queue-status">${job.status.toUpperCase()} - ${job.amount}x</div>
            </div>
            ${job.status === 'pending' ? `<button class="queue-cancel-btn" onclick="cancelCraft(${job.id})">✕</button>` : ''}
        `;
        
        queueList.appendChild(item);
    });
    
    queueCount.textContent = `${craftingQueue.length} active`;
}

async function cancelCraft(jobId) {
    try {
        const response = await fetch(`${API_URL}/api/queue/${jobId}/cancel`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' }
        });
        
        const data = await response.json();
        
        if (data.success) {
            showNotification(`Craft job #${jobId} cancelled`, 'success');
            loadQueue();
        } else {
            showNotification(`Failed to cancel: ${data.message}`, 'error');
        }
    } catch (error) {
        console.error('Error cancelling craft:', error);
        showNotification('Failed to cancel craft', 'error');
    }
}

function updateStatus(online, data = null) {
    const indicator = document.getElementById('statusIndicator');
    const statusText = document.getElementById('statusText');
    const itemCount = document.getElementById('itemCount');
    const storageCount = document.getElementById('storageCount');
    
    if (online) {
        indicator.classList.add('online');
        statusText.textContent = 'ONLINE';
        
        if (data) {
            itemCount.textContent = data.items?.length || 0;
            storageCount.textContent = data.stats?.storageDevices || 0;
        }
    } else {
        indicator.classList.remove('online');
        statusText.textContent = 'OFFLINE';
    }
}

// ══════════════════════════════════════════════════════════════════════════
// Craft Modal
// ══════════════════════════════════════════════════════════════════════════

async function openCraftModal(itemId) {
    const modal = document.getElementById('craftModal');
    const body = document.getElementById('craftModalBody');
    
    body.innerHTML = '<div style="text-align:center;padding:40px;">Loading recipes...</div>';
    modal.classList.add('show');
    
    try {
        const safeId = itemId.replace(':', '__');
        const response = await fetch(`${API_URL}/api/recipes/${safeId}`);
        const data = await response.json();
        
        if (!data.recipes || data.recipes.length === 0) {
            body.innerHTML = '<div style="text-align:center;padding:40px;color:#e74c3c;">No recipes found</div>';
            return;
        }
        
        const recipe = data.recipes[0];
        const texture = craftableItems[itemId]?.texture;
        
        body.innerHTML = `
            <div style="text-align:center;margin-bottom:20px;">
                <div style="width:96px;height:96px;margin:0 auto 15px;background:#2d3748;border-radius:8px;display:flex;align-items:center;justify-content:center;">
                    ${texture ? `<img src="/textures/${texture}" style="width:100%;height:100%;image-rendering:pixelated;">` : '📦'}
                </div>
                <h3 style="color:#4a90e2;margin-bottom:5px;">${itemId.split(':')[1] || itemId}</h3>
                <p style="color:#707070;font-size:12px;">${itemId}</p>
            </div>
            
            <div style="background:#0f1419;padding:15px;border-radius:6px;margin-bottom:20px;">
                <div style="color:#a0a0a0;font-size:13px;margin-bottom:5px;">Recipe Type:</div>
                <div style="color:#4a90e2;font-weight:600;">${recipe.type}</div>
            </div>
            
            <div style="margin-bottom:20px;">
                <label style="display:block;color:#a0a0a0;font-size:13px;margin-bottom:8px;">Amount:</label>
                <input type="number" id="craftAmount" value="1" min="1" max="64" 
                    style="width:100%;padding:10px;background:#0f1419;border:2px solid #2d3748;border-radius:6px;color:#e0e0e0;font-size:14px;">
            </div>
            
            <button onclick="submitCraft('${itemId}')" class="craft-btn">
                ⚙️ Start Crafting
            </button>
        `;
    } catch (error) {
        body.innerHTML = '<div style="text-align:center;padding:40px;color:#e74c3c;">Error loading recipe</div>';
    }
}

function closeCraftModal() {
    document.getElementById('craftModal').classList.remove('show');
}

async function submitCraft(itemId) {
    const amount = parseInt(document.getElementById('craftAmount').value) || 1;
    closeCraftModal();
    await craftItem(itemId, amount);
}

// ══════════════════════════════════════════════════════════════════════════
// Polling
// ══════════════════════════════════════════════════════════════════════════

function startInventoryPolling() {
    loadInventory();
    setInterval(loadInventory, 2000); // Every 2 seconds
}

function startQueuePolling() {
    loadQueue();
    setInterval(loadQueue, 1000); // Every 1 second
}

// ══════════════════════════════════════════════════════════════════════════
// Utilities
// ══════════════════════════════════════════════════════════════════════════

function formatCount(count) {
    if (count >= 1000000) return (count / 1000000).toFixed(1) + 'M';
    if (count >= 1000) return (count / 1000).toFixed(1) + 'K';
    return count.toString();
}

function showNotification(message, type) {
    // TODO: Implement toast notification
    console.log(`[${type.toUpperCase()}] ${message}`);
}

// Close modal on escape
document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
        closeCraftModal();
    }
});

// Close modal on background click
document.getElementById('craftModal').addEventListener('click', (e) => {
    if (e.target.id === 'craftModal') {
        closeCraftModal();
    }
});

// ══════════════════════════════════════════════════════════════════════════
// Start
// ══════════════════════════════════════════════════════════════════════════

init();
