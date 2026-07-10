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
-- Craft Queue Handler
-- ══════════════════════════════════════════════════════════════════════════

-- Find all mechanical crafters
function findCrafters()
    local crafters = {}
    for _, name in ipairs(peripheral.getNames()) do
        if name:match("mechanical_crafter_%d+$") then
            local num = tonumber(name:match("%d+"))
            table.insert(crafters, {
                name = name,
                peripheral = peripheral.wrap(name),
                slot = num
            })
        end
    end
    table.sort(crafters, function(a, b) return a.slot < b.slot end)
    return crafters
end

-- Find output depot
function findOutputDepot()
    for _, name in ipairs(peripheral.getNames()) do
        if name:match("depot_4$") then
            return {name = name, peripheral = peripheral.wrap(name)}
        end
    end
    return nil
end

-- Find item in storage
function findItemInStorage(itemId)
    for _, storage in ipairs(findAllStorage()) do
        if storage.peripheral and storage.peripheral.list then
            for slot, item in pairs(storage.peripheral.list()) do
                if item.name == itemId then
                    return storage, slot, item.count
                end
            end
        end
    end
    return nil
end

-- Transfer item from storage to target
function transferItem(itemId, targetName, targetSlot, amount)
    local storage, slot, available = findItemInStorage(itemId)
    if not storage then
        return false, "Item not found: " .. itemId
    end
    
    local count = math.min(amount or 1, available)
    local moved = storage.peripheral.pushItems(targetName, slot, count, targetSlot)
    
    if moved > 0 then
        return true, moved
    else
        return false, "Transfer failed"
    end
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

-- Execute craft
function executeCraft(job)
    print("[CRAFT] Starting job #" .. job.id .. ": " .. job.amount .. "x " .. job.itemId)
    
    -- Get recipe
    local recipe = getRecipe(job.itemId)
    if not recipe then
        print("[CRAFT] No recipe found!")
        return false, "No recipe found"
    end
    
    print("[CRAFT] Recipe type: " .. recipe.type)
    
    -- Parse grid
    local grid = {}
    if recipe.type == "minecraft:crafting_shaped" then
        grid = parseShapedRecipe(recipe.data)
    elseif recipe.type == "create:mechanical_crafting" then
        grid = parseMechanicalRecipe(recipe.data)
    else
        print("[CRAFT] Unsupported recipe type: " .. recipe.type)
        return false, "Unsupported recipe type"
    end
    
    -- Find crafters
    local crafters = findCrafters()
    if #crafters < 9 then
        print("[CRAFT] Not enough crafters! Found: " .. #crafters)
        return false, "Not enough crafters"
    end
    
    -- Transfer items to crafters
    print("[CRAFT] Transferring items...")
    for index = 1, 9 do
        local itemId = grid[index]
        if itemId and crafters[index] then
            local crafterName = crafters[index].name
            print("  [" .. index .. "] " .. itemId .. " -> " .. crafterName)
            
            local success, msg = transferItem(itemId, crafterName, 1, 1)
            if not success then
                print("  ERROR: " .. msg)
                return false, msg
            end
        end
    end
    
    print("[CRAFT] Items placed, waiting for craft...")
    sleep(5)
    
    -- Check output
    local outputDepot = findOutputDepot()
    if outputDepot then
        local items = outputDepot.peripheral.list()
        if next(items) then
            print("[CRAFT] ✓ Craft complete!")
            return true
        else
            print("[CRAFT] ⚠ No output in depot_4")
            return false, "No output"
        end
    else
        print("[CRAFT] ⚠ Output depot not found")
        return false, "No output depot"
    end
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
        print("\n[CRAFT] New job #" .. data.job.id .. ": " .. data.job.amount .. "x " .. data.job.itemId)
        
        -- Execute craft
        local success, error = executeCraft(data.job)
        
        -- Report result
        local endpoint = success and "/api/queue/" .. data.job.id .. "/complete" 
                                  or "/api/queue/" .. data.job.id .. "/fail"
        
        local payload = success and {} or {error = error or "Unknown error"}
        local jsonData = textutils.serialiseJSON(payload)
        
        pcall(function()
            local resp = http.post(API_URL .. endpoint, jsonData, HTTP_HEADERS)
            if resp then resp.close() end
        end)
        
        if success then
            print("[CRAFT] ✓ Job #" .. data.job.id .. " completed!")
        else
            print("[CRAFT] ✗ Job #" .. data.job.id .. " failed: " .. (error or "Unknown"))
        end
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
