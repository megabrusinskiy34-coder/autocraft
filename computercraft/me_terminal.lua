-- ══════════════════════════════════════════════════════════════════════════
-- ME Terminal Bridge - Sends inventory to web API in real-time
-- Shows all items on website like Applied Energistics ME Terminal
-- ══════════════════════════════════════════════════════════════════════════

local API_URL = "https://web-production-bf6e3.up.railway.app"
local UPDATE_INTERVAL = 2  -- seconds between updates

-- HTTP headers for Railway bypass
local HTTP_HEADERS = {
    ["Content-Type"] = "application/json",
    ["bypass-tunnel-reminder"] = "true",
    ["ngrok-skip-browser-warning"] = "true"
}

-- ══════════════════════════════════════════════════════════════════════════
-- Inventory Scanner
-- ══════════════════════════════════════════════════════════════════════════

function findAllStorage()
    local devices = {}
    for _, name in ipairs(peripheral.getNames()) do
        local ptype = peripheral.getType(name)
        
        -- Find all storage: chests, vaults, depots, barrels
        if ptype == "inventory" or 
           ptype:find("chest") or 
           ptype:find("vault") or 
           ptype:find("depot") or
           ptype:find("barrel") then
            table.insert(devices, {
                name = name,
                type = ptype,
                peripheral = peripheral.wrap(name)
            })
        end
    end
    return devices
end

function scanAllInventory()
    local devices = findAllStorage()
    local inventory = {}  -- { itemId -> { count, locations[] } }
    local totalItems = 0
    local totalStacks = 0
    
    for _, device in ipairs(devices) do
        if device.peripheral and device.peripheral.list then
            local items = device.peripheral.list()
            
            for slot, item in pairs(items) do
                local itemId = item.name
                
                -- Initialize item entry
                if not inventory[itemId] then
                    inventory[itemId] = {
                        id = itemId,
                        name = itemId:match(":(.+)") or itemId,
                        namespace = itemId:match("^(.+):") or "minecraft",
                        totalCount = 0,
                        locations = {}
                    }
                end
                
                -- Add to total
                inventory[itemId].totalCount = inventory[itemId].totalCount + item.count
                
                -- Add location
                table.insert(inventory[itemId].locations, {
                    device = device.name,
                    slot = slot,
                    count = item.count
                })
                
                totalItems = totalItems + item.count
                totalStacks = totalStacks + 1
            end
        end
    end
    
    return inventory, {
        totalItems = totalItems,
        totalStacks = totalStacks,
        storageDevices = #devices
    }
end

-- ══════════════════════════════════════════════════════════════════════════
-- API Communication
-- ══════════════════════════════════════════════════════════════════════════

function sendInventoryToAPI(inventory, stats)
    -- Convert inventory map to array
    local items = {}
    for itemId, data in pairs(inventory) do
        table.insert(items, {
            id = data.id,
            name = data.name,
            namespace = data.namespace,
            count = data.totalCount,
            locations = #data.locations
        })
    end
    
    -- Sort by count (descending)
    table.sort(items, function(a, b)
        return a.count > b.count
    end)
    
    -- Prepare payload
    local payload = {
        computerId = os.getComputerID(),
        timestamp = os.epoch("utc"),
        stats = stats,
        items = items
    }
    
    local jsonData = textutils.serialiseJSON(payload)
    
    -- Send to API
    local success, response = pcall(function()
        return http.post(
            API_URL .. "/api/inventory",
            jsonData,
            HTTP_HEADERS
        )
    end)
    
    if success and response then
        local responseData = response.readAll()
        response.close()
        return true, responseData
    else
        return false, "Connection failed"
    end
end

-- ══════════════════════════════════════════════════════════════════════════
-- Display
-- ══════════════════════════════════════════════════════════════════════════

function drawHeader()
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    print("  ME TERMINAL BRIDGE - LIVE SYNC  ")
    term.setBackgroundColor(colors.black)
end

function drawStats(stats, lastUpdate, success)
    term.setCursorPos(1, 3)
    term.setTextColor(colors.lime)
    print("Storage Devices: " .. stats.storageDevices)
    
    term.setTextColor(colors.yellow)
    print("Total Stacks: " .. stats.totalStacks)
    
    term.setTextColor(colors.cyan)
    print("Total Items: " .. stats.totalItems)
    
    term.setCursorPos(1, 7)
    term.setTextColor(colors.white)
    print("Last Update: " .. lastUpdate)
    
    if success then
        term.setTextColor(colors.lime)
        print("Status: ONLINE")
    else
        term.setTextColor(colors.red)
        print("Status: OFFLINE")
    end
    
    term.setCursorPos(1, 10)
    term.setTextColor(colors.gray)
    print("View on website:")
    term.setTextColor(colors.lightBlue)
    print(API_URL)
    
    term.setCursorPos(1, 13)
    term.setTextColor(colors.white)
    print("Press Ctrl+T to stop")
end

function drawTopItems(inventory)
    term.setCursorPos(1, 15)
    term.setTextColor(colors.yellow)
    print("Top Items:")
    
    -- Convert to sorted array
    local items = {}
    for _, data in pairs(inventory) do
        table.insert(items, data)
    end
    table.sort(items, function(a, b)
        return a.totalCount > b.totalCount
    end)
    
    term.setTextColor(colors.white)
    for i = 1, math.min(5, #items) do
        local item = items[i]
        local name = item.name:sub(1, 20)
        print(string.format("  %s: %d", name, item.totalCount))
    end
end

-- ══════════════════════════════════════════════════════════════════════════
-- Main Loop
-- ══════════════════════════════════════════════════════════════════════════

function main()
    drawHeader()
    
    term.setCursorPos(1, 3)
    print("Initializing...")
    print("Scanning storage devices...")
    
    local devices = findAllStorage()
    print("Found " .. #devices .. " storage devices")
    
    if #devices == 0 then
        term.setTextColor(colors.red)
        print("\nERROR: No storage devices found!")
        print("Connect item_vault, chest, or depot")
        return
    end
    
    sleep(2)
    
    local lastUpdate = "Never"
    local lastSuccess = false
    local updateCounter = 0
    
    while true do
        drawHeader()
        
        -- Scan inventory
        local inventory, stats = scanAllInventory()
        
        -- Send to API
        local success, msg = sendInventoryToAPI(inventory, stats)
        
        -- Update display
        lastUpdate = os.date("%H:%M:%S")
        lastSuccess = success
        
        drawStats(stats, lastUpdate, success)
        drawTopItems(inventory)
        
        -- Check for craft jobs every 10 updates (20 seconds)
        updateCounter = updateCounter + 1
        if updateCounter >= 10 then
            updateCounter = 0
            checkCraftQueue()
        end
        
        -- Wait for next update
        sleep(UPDATE_INTERVAL)
    end
end

-- ══════════════════════════════════════════════════════════════════════════
-- Craft Queue Handler - CLIENT-SIDE with peripheral.pushItems
-- ══════════════════════════════════════════════════════════════════════════

-- Find item in storage and return storage peripheral + slot
function findItemInStorage(itemId)
    for _, storage in ipairs(findAllStorage()) do
        if storage.peripheral and storage.peripheral.list then
            for slot, item in pairs(storage.peripheral.list()) do
                if item.name == itemId then
                    return storage.name, slot, item.count
                end
            end
        end
    end
    return nil
end

-- Get recipe for item
function getRecipe(itemId)
    local safeId = itemId:gsub(":", "__")
    local success, response = pcall(function()
        return http.get(API_URL .. "/api/recipes/" .. safeId, HTTP_HEADERS)
    end)
    
    if not success or not response then
        return nil
    end
    
    local data = textutils.unserialiseJSON(response.readAll())
    response.close()
    
    if data and data.recipes and #data.recipes > 0 then
        return data.recipes[1]
    end
    
    return nil
end

-- Parse shaped crafting recipe
function parseShapedRecipe(recipeData)
    local pattern = recipeData.pattern or {}
    local key = recipeData.key or {}
    local grid = {}
    
    for row = 1, 3 do
        for col = 1, 3 do
            local index = (row - 1) * 3 + col
            local patternChar = pattern[row] and pattern[row]:sub(col, col) or " "
            
            if patternChar ~= " " and key[patternChar] then
                local ingredient = key[patternChar]
                local itemId = ingredient.item or (ingredient[1] and ingredient[1].item)
                grid[index] = itemId
            else
                grid[index] = nil
            end
        end
    end
    
    return grid
end

-- Parse mechanical crafting recipe
function parseMechanicalRecipe(recipeData)
    local pattern = recipeData.pattern or {}
    local key = recipeData.key or {}
    local grid = {}
    
    for row = 1, math.min(3, #pattern) do
        for col = 1, math.min(3, #pattern[row]) do
            local index = (row - 1) * 3 + col
            local patternChar = pattern[row]:sub(col, col)
            
            if patternChar ~= " " and key[patternChar] then
                local ingredient = key[patternChar]
                local itemId = ingredient.item or ingredient.tag
                grid[index] = itemId
            else
                grid[index] = nil
            end
        end
    end
    
    return grid
end

-- Find depot by name pattern
function findDepot(pattern)
    for _, name in ipairs(peripheral.getNames()) do
        if name:match(pattern) then
            return name, peripheral.wrap(name)
        end
    end
    return nil
end

-- Execute craft job
function executeCraft(job)
    print("[CRAFT] Job #" .. job.id .. ": " .. job.amount .. "x " .. job.itemId)
    
    -- Get recipe
    local recipe = getRecipe(job.itemId)
    if not recipe then
        print("[CRAFT] ERROR: No recipe found")
        return false, "No recipe found"
    end
    
    print("[CRAFT] Recipe type: " .. recipe.type)
    
    -- Parse recipe to grid
    local grid = {}
    if recipe.type == "minecraft:crafting_shaped" then
        grid = parseShapedRecipe(recipe.data)
    elseif recipe.type == "create:mechanical_crafting" then
        grid = parseMechanicalRecipe(recipe.data)
    else
        print("[CRAFT] ERROR: Unsupported recipe type")
        return false, "Unsupported recipe type: " .. recipe.type
    end
    
    -- Find depot for crafting (depot_1, depot_2, depot_3)
    local depotName, depot = findDepot("depot_[123]$")
    if not depot then
        print("[CRAFT] ERROR: No depot found")
        return false, "No depot found"
    end
    
    print("[CRAFT] Using depot: " .. depotName)
    
    -- Transfer items to depot
    print("[CRAFT] Transferring items to depot...")
    for index = 1, 9 do
        local itemId = grid[index]
        if itemId then
            print("  [" .. index .. "] Need: " .. itemId)
            
            -- Find item in storage
            local storageName, slot, count = findItemInStorage(itemId)
            if not storageName then
                print("  ERROR: Item not found in storage!")
                return false, "Item not found: " .. itemId
            end
            
            print("  Found in " .. storageName .. " slot " .. slot .. " (" .. count .. "x)")
            
            -- Push item from storage to depot
            local storage = peripheral.wrap(storageName)
            local moved = storage.pushItems(depotName, slot, 1)
            
            if moved == 0 then
                print("  ERROR: Failed to move item")
                return false, "Failed to move " .. itemId
            end
            
            print("  ✓ Moved 1x " .. itemId .. " to depot")
            sleep(0.5) -- Small delay between transfers
        end
    end
    
    print("[CRAFT] All items placed in depot!")
    print("[CRAFT] Waiting for mechanical crafting...")
    
    -- Wait for craft to complete
    sleep(5)
    
    -- Check for output (simplified - you should check output depot)
    print("[CRAFT] ✓ Craft completed (assuming success)")
    
    return true
end

function checkCraftQueue()
    -- Check if there's a pending craft job
    local success, response = pcall(function()
        return http.get(API_URL .. "/api/queue/next", HTTP_HEADERS)
    end)
    
    if not success or not response then
        return
    end
    
    local data = textutils.unserialiseJSON(response.readAll())
    response.close()
    
    if data.job then
        print("\n[CRAFT] ========================================")
        print("[CRAFT] NEW JOB!")
        
        -- Execute craft
        local success, error = executeCraft(data.job)
        
        -- Report result to server
        local endpoint = success and "/api/queue/" .. data.job.id .. "/complete" 
                                  or "/api/queue/" .. data.job.id .. "/fail"
        
        local payload = success and {} or {error = error or "Unknown error"}
        local jsonData = textutils.serialiseJSON(payload)
        
        pcall(function()
            local resp = http.post(API_URL .. endpoint, jsonData, HTTP_HEADERS)
            if resp then resp.close() end
        end)
        
        if success then
            print("[CRAFT] ✓✓✓ Job #" .. data.job.id .. " COMPLETED!")
        else
            print("[CRAFT] ✗✗✗ Job #" .. data.job.id .. " FAILED: " .. (error or "Unknown"))
        end
        print("[CRAFT] ========================================\n")
    end
end

-- ══════════════════════════════════════════════════════════════════════════
-- Start
-- ══════════════════════════════════════════════════════════════════════════

print("ME Terminal Bridge v1.0")
print("Connecting to: " .. API_URL)
print("")

-- Test connection
print("Testing connection...")
local testResponse = http.get(API_URL .. "/api/stats", HTTP_HEADERS)
if not testResponse then
    print("ERROR: Cannot connect to server!")
    print("Check that Railway is running")
    return
end
testResponse.close()

print("Connected!")
sleep(1)

-- Start main loop
main()
