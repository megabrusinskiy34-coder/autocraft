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
    local seen = {}  -- Track already added devices to avoid duplicates
    
    for _, name in ipairs(peripheral.getNames()) do
        -- Skip if already added
        if not seen[name] then
            local ptype = peripheral.getType(name)
            
            -- Find all storage BUT exclude depots (they are for crafting, not storage)
            if (ptype == "inventory" or 
               ptype:find("chest") or 
               ptype:find("vault") or 
               ptype:find("barrel")) and
               not name:match("depot") then  -- EXCLUDE DEPOTS!
                
                table.insert(devices, {
                    name = name,
                    type = ptype,
                    peripheral = peripheral.wrap(name)
                })
                seen[name] = true
            end
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
    
    -- Debug: log coal count if exists
    for _, item in ipairs(items) do
        if item.id == "minecraft:coal" then
            print("[DEBUG] Sending coal count: " .. item.count)
        end
    end
    
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
        
        -- Check for craft jobs every 2 updates (4 seconds) - MORE FREQUENT!
        updateCounter = updateCounter + 1
        if updateCounter >= 2 then
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
    -- If itemId is a tag (starts with #), search for matching items
    local isTag = itemId:sub(1, 1) == "#"
    local tagName = isTag and itemId:sub(2) or nil
    
    for _, storage in ipairs(findAllStorage()) do
        if storage.peripheral and storage.peripheral.list then
            for slot, item in pairs(storage.peripheral.list()) do
                if isTag then
                    -- For tags, convert to most common item format
                    -- c:ingots/iron -> minecraft:iron_ingot or create:iron_ingot
                    local simplifiedTag = tagName:gsub("^c:", ""):gsub("^forge:", "")
                    
                    -- Extract base name (e.g., "iron" from "ingots/iron")
                    local baseName = simplifiedTag:match("([^/]+)$") or simplifiedTag
                    
                    -- Build expected item patterns
                    -- For c:ingots/gold -> look for gold_ingot (not gold_wire, gold_block, etc)
                    local patterns = {}
                    
                    if simplifiedTag:match("^ingots/") then
                        -- ingots/iron -> iron_ingot
                        table.insert(patterns, baseName .. "_ingot")
                    elseif simplifiedTag:match("^plates/") or simplifiedTag:match("^sheets/") then
                        -- plates/iron -> iron_plate or iron_sheet
                        table.insert(patterns, baseName .. "_plate")
                        table.insert(patterns, baseName .. "_sheet")
                    elseif simplifiedTag:match("^nuggets/") then
                        -- nuggets/iron -> iron_nugget
                        table.insert(patterns, baseName .. "_nugget")
                    elseif simplifiedTag:match("^dusts/") then
                        -- dusts/iron -> iron_dust
                        table.insert(patterns, baseName .. "_dust")
                    elseif simplifiedTag:match("^gears/") then
                        -- gears/iron -> iron_gear
                        table.insert(patterns, baseName .. "_gear")
                    elseif simplifiedTag:match("^rods/") then
                        -- rods/iron -> iron_rod
                        table.insert(patterns, baseName .. "_rod")
                    else
                        -- Fallback: just look for baseName_something
                        table.insert(patterns, baseName)
                    end
                    
                    -- Check if item matches any pattern
                    for _, pattern in ipairs(patterns) do
                        if item.name:find(pattern) then
                            -- Extra validation: make sure it's not something else
                            -- e.g., gold_ingot is ok, but gold_wire is not
                            local itemBaseName = item.name:match(":(.+)") or item.name
                            
                            -- Check it matches the pattern closely
                            if itemBaseName == pattern or 
                               itemBaseName == "minecraft:" .. pattern or
                               itemBaseName == "create:" .. pattern or
                               itemBaseName:match(pattern .. "$") then
                                return storage.name, slot, item.count
                            end
                        end
                    end
                else
                    -- Direct item ID match
                    if item.name == itemId then
                        return storage.name, slot, item.count
                    end
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

-- Parse Create simple recipes (pressing, cutting, etc.)
-- These need only 1 ingredient in slot 5 (center)
function parseCreateSimpleRecipe(recipeData)
    local grid = {}
    
    -- Get ingredient
    local ingredients = recipeData.ingredients
    if not ingredients then
        return grid
    end
    
    -- Handle single ingredient or array
    local ingredient = nil
    if type(ingredients) == "table" then
        if #ingredients > 0 then
            ingredient = ingredients[1]
        else
            ingredient = ingredients
        end
    end
    
    if not ingredient then
        return grid
    end
    
    -- Extract item ID or tag
    local itemId = nil
    if type(ingredient) == "string" then
        itemId = ingredient
    elseif ingredient.item then
        itemId = ingredient.item
    elseif ingredient.tag then
        -- Tags need special handling - mark with # prefix
        itemId = "#" .. ingredient.tag
    elseif ingredient[1] then
        if ingredient[1].item then
            itemId = ingredient[1].item
        elseif ingredient[1].tag then
            itemId = "#" .. ingredient[1].tag
        end
    end
    
    if itemId then
        grid[5] = itemId  -- Center slot (position 5 in 3x3 grid)
    end
    
    return grid
end

-- Find depot by name pattern (excludes depot_4 which is for output)
function findDepot(pattern)
    for _, name in ipairs(peripheral.getNames()) do
        if name:match(pattern) and not name:match("depot_4$") then
            return name, peripheral.wrap(name)
        end
    end
    return nil
end

-- Execute craft job
function executeCraft(job)
    print("\n╔════════════════════════════════════════╗")
    print("║  CRAFT JOB #" .. job.id)
    print("║  Item: " .. job.itemId)
    print("║  Amount: " .. job.amount)
    print("╚════════════════════════════════════════╝")
    
    -- Step 1: Get recipe
    print("\n[STEP 1] Fetching recipe from API...")
    print("  URL: " .. API_URL .. "/api/recipes/" .. job.itemId:gsub(":", "__"))
    
    local success, recipe = pcall(function()
        return getRecipe(job.itemId)
    end)
    
    if not success then
        print("  ✗ EXCEPTION: " .. tostring(recipe))
        return false, "Recipe fetch crashed: " .. tostring(recipe)
    end
    
    if not recipe then
        print("  ✗ ERROR: No recipe found for " .. job.itemId)
        print("  Possible reasons:")
        print("    - Item doesn't exist in database")
        print("    - API connection failed")
        print("    - Item ID typo")
        
        -- Try HTTP test
        print("\n  Testing HTTP connection...")
        local httpTest = pcall(function()
            local resp = http.get(API_URL .. "/api/stats", HTTP_HEADERS)
            if resp then
                print("  ✓ HTTP works, but recipe not found")
                resp.close()
            else
                print("  ✗ HTTP failed")
            end
        end)
        
        return false, "No recipe found"
    end
    
    print("  ✓ Recipe found!")
    print("  Type: " .. recipe.type)
    print("  Recipe ID: " .. (recipe.id or "unknown"))
    
    -- Debug: print raw recipe data
    if recipe.data then
        print("\n  Raw recipe data:")
        print("    Has pattern: " .. tostring(recipe.data.pattern ~= nil))
        print("    Has key: " .. tostring(recipe.data.key ~= nil))
        print("    Has result: " .. tostring(recipe.data.result ~= nil))
        print("    Has results: " .. tostring(recipe.data.results ~= nil))
    end
    
    -- Step 2: Parse recipe
    print("\n[STEP 2] Parsing recipe...")
    local grid = {}
    local parseSuccess, parseError
    
    if recipe.type == "minecraft:crafting_shaped" then
        print("  Format: Shaped Crafting (3x3)")
        parseSuccess, parseError = pcall(function()
            grid = parseShapedRecipe(recipe.data)
        end)
    elseif recipe.type == "create:mechanical_crafting" then
        print("  Format: Mechanical Crafting")
        parseSuccess, parseError = pcall(function()
            grid = parseMechanicalRecipe(recipe.data)
        end)
    elseif recipe.type == "create:pressing" or 
           recipe.type == "create:cutting" or
           recipe.type == "create:milling" or
           recipe.type == "create:crushing" or
           recipe.type == "create:sandpaper_polishing" or
           recipe.type == "create:deploying" then
        print("  Format: Create Simple Recipe (" .. recipe.type .. ")")
        print("  NOTE: This uses mechanical press/saw/etc - not crafter!")
        print("  Putting ingredient in depot center (slot 5)")
        parseSuccess, parseError = pcall(function()
            grid = parseCreateSimpleRecipe(recipe.data)
        end)
    else
        print("  ✗ ERROR: Unsupported recipe type: " .. recipe.type)
        print("  Supported types:")
        print("    - minecraft:crafting_shaped")
        print("    - create:mechanical_crafting")
        print("    - create:pressing, cutting, milling, crushing")
        return false, "Unsupported recipe type: " .. recipe.type
    end
    
    if not parseSuccess then
        print("  ✗ EXCEPTION during parsing: " .. tostring(parseError))
        return false, "Recipe parse failed: " .. tostring(parseError)
    end
    
    -- Validate grid
    local itemCount = 0
    for i = 1, 9 do
        if grid[i] then itemCount = itemCount + 1 end
    end
    
    if itemCount == 0 then
        print("  ✗ ERROR: Recipe grid is empty after parsing!")
        print("  This means recipe.data.pattern or recipe.data.key is malformed")
        return false, "Empty recipe grid"
    end
    
    print("  ✓ Grid parsed: " .. itemCount .. " slots filled")
    
    -- Show grid
    print("\n  Recipe Grid (3x3):")
    for row = 1, 3 do
        local line = "    "
        for col = 1, 3 do
            local index = (row - 1) * 3 + col
            local item = grid[index]
            if item then
                local shortName = item:match(":(.+)") or item
                line = line .. "[" .. shortName:sub(1, 8) .. "] "
            else
                line = line .. "[   -   ] "
            end
        end
        print(line)
    end
    
    -- Step 3: Find depot
    print("\n[STEP 3] Finding depot...")
    print("  Looking for: depot_5, depot_6, depot_7 (or any depot_N)")
    print("  Pattern match: 'depot_%d+$'")
    print("\n  Available peripherals:")
    
    local allPeripherals = peripheral.getNames()
    local foundDepots = {}
    
    for _, name in ipairs(allPeripherals) do
        local ptype = peripheral.getType(name)
        print("    - " .. name .. " (type: " .. ptype .. ")")
        
        -- Check if it matches depot pattern (depot_N where N is any number)
        if name:match("depot_%d+$") then
            table.insert(foundDepots, name)
            print("      ^ MATCHES depot pattern!")
        end
    end
    
    print("\n  Depots matching pattern: " .. #foundDepots)
    for _, d in ipairs(foundDepots) do
        print("    - " .. d)
    end
    
    if #foundDepots == 0 then
        print("\n  ✗ ERROR: No depot found!")
        print("  Troubleshooting:")
        print("    1. Check peripheral names above")
        print("    2. Depot must be named like 'depot_5', 'depot_6', etc")
        print("    3. Or contain these names (e.g., 'create:depot_5')")
        print("    4. Connected via Wired Modem")
        print("    5. Modem is activated (right-click)")
        print("\n  If your depot has 'create:' prefix, pattern still works")
        return false, "No depot found"
    end
    
    local depotName, depot = findDepot("depot_%d+$")
    if not depot then
        print("  ✗ ERROR: Found depot names but cannot wrap peripheral!")
        return false, "Cannot wrap depot"
    end
    
    print("\n  ✓ Selected depot: " .. depotName)
    print("  Depot type: " .. peripheral.getType(depotName))
    
    -- Check depot methods
    print("\n  Testing depot methods...")
    local methods = peripheral.getMethods(depotName) or {}
    local hasSize = false
    local hasList = false
    local hasPushItems = false
    
    for _, method in ipairs(methods) do
        if method == "size" then hasSize = true end
        if method == "list" then hasList = true end
        if method == "pushItems" then hasPushItems = true end
    end
    
    print("    size() available: " .. tostring(hasSize))
    print("    list() available: " .. tostring(hasList))
    print("    pushItems() available: " .. tostring(hasPushItems))
    
    if not hasList then
        print("\n  ✗ ERROR: Depot doesn't have list() method!")
        print("  This peripheral may not be a valid inventory")
        return false, "Depot is not an inventory"
    end
    
    -- Check depot capacity
    if hasSize then
        local depotSize = depot.size()
        print("    Depot capacity: " .. depotSize .. " slots")
    end
    
    -- Check current contents
    local currentItems = depot.list()
    local itemCount = 0
    for _ in pairs(currentItems) do itemCount = itemCount + 1 end
    print("    Current items in depot: " .. itemCount)
    
    if itemCount > 0 then
        print("    ⚠ WARNING: Depot is not empty!")
        for slot, item in pairs(currentItems) do
            print("      Slot " .. slot .. ": " .. item.name .. " x" .. item.count)
        end
    end
    
    -- Step 4: Find and transfer items
    print("\n[STEP 4] Finding and transferring items...")
    
    local itemsNeeded = {}
    for index = 1, 9 do
        if grid[index] then
            table.insert(itemsNeeded, {index = index, itemId = grid[index]})
        end
    end
    
    print("  Items needed: " .. #itemsNeeded)
    
    if #itemsNeeded == 0 then
        print("  ✗ ERROR: Recipe grid has no items!")
        return false, "Empty recipe"
    end
    
    -- Get list of all storage devices
    local storageDevices = findAllStorage()
    print("  Storage devices available: " .. #storageDevices)
    for _, storage in ipairs(storageDevices) do
        print("    - " .. storage.name .. " (" .. storage.type .. ")")
    end
    
    for itemNum, item in ipairs(itemsNeeded) do
        print("\n  [" .. itemNum .. "/" .. #itemsNeeded .. "] Processing slot " .. item.index .. ": " .. item.itemId)
        
        -- Check if it's a tag
        if item.itemId:sub(1, 1) == "#" then
            print("    This is a TAG: " .. item.itemId:sub(2))
            print("    Searching for items matching this tag...")
        else
            print("    Looking for exact item: " .. item.itemId)
        end
        
        print("    Searching in storage...")
        
        -- Use findItemInStorage which supports tags!
        local storageName, slot, count = findItemInStorage(item.itemId)
        
        if not storageName then
            print("    ✗ ERROR: Item not found in any storage!")
            
            if item.itemId:sub(1, 1) == "#" then
                print("    Tag was: " .. item.itemId:sub(2))
                local baseName = item.itemId:match("([^/]+)$") or "unknown"
                print("    Looking for items containing: " .. baseName)
            end
            
            print("\n    Detailed storage contents:")
            for _, storage in ipairs(storageDevices) do
                print("      " .. storage.name .. ":")
                if storage.peripheral and storage.peripheral.list then
                    local items = storage.peripheral.list()
                    local count = 0
                    for _ in pairs(items) do count = count + 1 end
                    
                    if count == 0 then
                        print("        (empty)")
                    else
                        print("        Contains " .. count .. " different items:")
                        local shown = 0
                        for _, i in pairs(items) do
                            if shown < 5 then
                                print("          - " .. i.name .. " x" .. i.count)
                                shown = shown + 1
                            end
                        end
                        if count > 5 then
                            print("          ... and " .. (count - 5) .. " more")
                        end
                    end
                else
                    print("        (cannot list items)")
                end
            end
            
            return false, "Item not found: " .. item.itemId
        end
        
        print("    ✓ Found in: " .. storageName)
        print("    Slot: " .. slot)
        print("    Available: " .. count .. "x")
        
        -- Get actual item details
        local storage = peripheral.wrap(storageName)
        if storage then
            local itemDetails = storage.getItemDetail(slot)
            if itemDetails then
                print("    ACTUAL ITEM: " .. itemDetails.name .. " x" .. itemDetails.count)
            end
        end
        
        -- Transfer item
        print("    Attempting transfer...")
        print("      Source: " .. storageName)
        print("      Target: " .. depotName)
        
        -- Extract short names (without prefix) for pushItems/pullItems
        local storageShortName = storageName:match("([^:]+)$") or storageName
        local depotShortName = depotName:match("([^:]+)$") or depotName
        
        local storage = peripheral.wrap(storageName)
        if not storage then
            print("    ✗ ERROR: Cannot wrap storage peripheral")
            return false, "Cannot access storage: " .. storageName
        end
        
        -- Find intermediary chest (buffer)
        local bufferName = nil
        for _, name in ipairs(peripheral.getNames()) do
            local ptype = peripheral.getType(name)
            -- Look for regular chest as buffer
            if ptype == "minecraft:chest" or name:match("chest") and not name:match("vault") then
                bufferName = name
                break
            end
        end
        
        local success, result
        local moved = 0
        
        -- METHOD 1: Try direct transfer (4 variations)
        print("\n    Method 1: Direct transfer")
        
        -- Try short name push
        success, result = pcall(function()
            return storage.pushItems(depotShortName, slot, 1)
        end)
        
        if success and result and result > 0 then
            moved = result
            print("    ✓ Direct push (short name) worked!")
        else
            -- Try full name push
            success, result = pcall(function()
                return storage.pushItems(depotName, slot, 1)
            end)
            
            if success and result and result > 0 then
                moved = result
                print("    ✓ Direct push (full name) worked!")
            else
                -- Try short name pull
                success, result = pcall(function()
                    return depot.pullItems(storageShortName, slot, 1)
                end)
                
                if success and result and result > 0 then
                    moved = result
                    print("    ✓ Direct pull (short name) worked!")
                else
                    -- Try full name pull
                    success, result = pcall(function()
                        return depot.pullItems(storageName, slot, 1)
                    end)
                    
                    if success and result and result > 0 then
                        moved = result
                        print("    ✓ Direct pull (full name) worked!")
                    else
                        print("    ✗ All direct methods failed")
                        
                        -- METHOD 2: Use buffer chest
                        if bufferName then
                            print("\n    Method 2: Using buffer chest: " .. bufferName)
                            local buffer = peripheral.wrap(bufferName)
                            local bufferShortName = bufferName:match("([^:]+)$") or bufferName
                            
                            -- Step 1: Storage -> Buffer (try both push and pull)
                            print("      Step 1: " .. storageName .. " -> " .. bufferName)
                            
                            -- Try: storage pushes to buffer
                            success, result = pcall(function()
                                return storage.pushItems(bufferShortName, slot, 1)
                            end)
                            
                            if not success or not result or result == 0 then
                                -- Try full name
                                success, result = pcall(function()
                                    return storage.pushItems(bufferName, slot, 1)
                                end)
                            end
                            
                            -- If push failed, try: buffer pulls from storage
                            if not success or not result or result == 0 then
                                print("      Push failed, trying pull...")
                                
                                -- WORKING METHOD: Use short names without prefix
                                local storageSimpleName = storageName:match("item_vault_%d+") or 
                                                         storageName:match("chest_%d+") or
                                                         storageShortName
                                
                                print("      Trying: buffer.pullItems('" .. storageSimpleName .. "', " .. slot .. ", 1)")
                                success, result = pcall(function()
                                    return buffer.pullItems(storageSimpleName, slot, 1)
                                end)
                                
                                if not success or not result or result == 0 then
                                    print("      Failed, trying full name...")
                                    success, result = pcall(function()
                                        return buffer.pullItems(storageName, slot, 1)
                                    end)
                                end
                            end
                            
                            if success and result and result > 0 then
                                print("      ✓ Moved to buffer: " .. result)
                                
                                -- Find item in buffer
                                local bufferSlot = nil
                                for s, i in pairs(buffer.list()) do
                                    if i.name == item.itemId or (item.itemId:sub(1,1) == "#" and i.name:find(item.itemId:match("([^/]+)$"))) then
                                        bufferSlot = s
                                        break
                                    end
                                end
                                
                                if bufferSlot then
                                    -- Step 2: Buffer -> Depot (try both push and pull)
                                    print("      Step 2: " .. bufferName .. " -> " .. depotName)
                                    
                                    -- Try: buffer pushes to depot
                                    success, result = pcall(function()
                                        return buffer.pushItems(depotShortName, bufferSlot, 1)
                                    end)
                                    
                                    if not success or not result or result == 0 then
                                        success, result = pcall(function()
                                            return buffer.pushItems(depotName, bufferSlot, 1)
                                        end)
                                    end
                                    
                                    -- If push failed, try: depot pulls from buffer
                                    if not success or not result or result == 0 then
                                        print("      Push failed, trying pull...")
                                        success, result = pcall(function()
                                            return depot.pullItems(bufferShortName, bufferSlot, 1)
                                        end)
                                        
                                        if not success or not result or result == 0 then
                                            success, result = pcall(function()
                                                return depot.pullItems(bufferName, bufferSlot, 1)
                                            end)
                                        end
                                    end
                                    
                                    if success and result and result > 0 then
                                        moved = result
                                        print("      ✓ Moved to depot: " .. result)
                                    else
                                        print("      ✗ Failed: " .. tostring(result))
                                        return false, "Buffer->Depot transfer failed"
                                    end
                                else
                                    print("      ✗ Item not found in buffer")
                                    return false, "Item lost in buffer"
                                end
                            else
                                print("      ✗ Failed: " .. tostring(result))
                                return false, "Storage->Buffer transfer failed"
                            end
                        else
                            print("\n    ✗ No buffer chest found!")
                            print("    Solution: Place a minecraft:chest next to computer")
                            print("    Connect it to wired modem network")
                            return false, "Cannot transfer - no route available"
                        end
                    end
                end
            end
        end
        
        if moved == 0 then
            print("    ✗ 0 items moved")
            return false, "Failed to move item"
        end
        
        print("    ✓ SUCCESS: Moved " .. moved .. "x " .. item.itemId)
        print("    Waiting 0.5s before next item...")
        sleep(0.5)
    end
    
    print("\n  ✓✓✓ All " .. #itemsNeeded .. " items transferred successfully!")
    
    -- Step 5: Wait for craft
    print("\n[STEP 5] Waiting for craft to complete...")
    print("  Mechanical crafters should now process the items")
    print("  Waiting 5 seconds...")
    
    for i = 5, 1, -1 do
        print("  " .. i .. "...")
        sleep(1)
    end
    
    print("  ✓ Wait complete")
    
    -- Step 6: Check output
    print("\n[STEP 6] Checking output...")
    print("  Looking for output depot...")
    
    local outputName, output = findDepot("depot_%d+$")
    
    if not output then
        print("  ⚠ Output depot not found")
        print("  Available depots:")
        for _, name in ipairs(peripheral.getNames()) do
            if name:match("depot") then
                print("    - " .. name)
            end
        end
        print("\n  Cannot verify output, but craft may have succeeded")
        print("  Check your mechanical crafter output manually")
    else
        print("  ✓ Found output depot: " .. outputName)
        
        local outputItems = output.list()
        local outputCount = 0
        for _ in pairs(outputItems) do outputCount = outputCount + 1 end
        
        print("  Output depot contains: " .. outputCount .. " items")
        
        if outputCount > 0 then
            print("  ✓ Output detected!")
            
            -- Find vault to return items to
            local returnVault = nil
            local returnVaultName = nil
            for _, name in ipairs(peripheral.getNames()) do
                if name:match("item_vault") then
                    returnVaultName = name
                    returnVault = peripheral.wrap(name)
                    break
                end
            end
            
            for slot, item in pairs(outputItems) do
                print("    - Slot " .. slot .. ": " .. item.name .. " x" .. item.count)
                
                -- Check if this is the item we wanted to craft
                if item.name == job.itemId then
                    print("      ✓✓✓ THIS IS THE CRAFTED ITEM!")
                end
                
                -- Try to return to vault
                if returnVault and returnVaultName then
                    print("      Returning to vault...")
                    
                    local vaultShortName = returnVaultName:match("item_vault_%d+") or returnVaultName:match("([^:]+)$")
                    
                    -- Try: vault pulls from depot
                    local success, moved = pcall(function()
                        return returnVault.pullItems(outputName:match("([^:]+)$") or outputName, slot, item.count)
                    end)
                    
                    if not success or not moved or moved == 0 then
                        -- Try: depot pushes to vault  
                        success, moved = pcall(function()
                            return output.pushItems(vaultShortName, slot, item.count)
                        end)
                    end
                    
                    if success and moved and moved > 0 then
                        print("      ✓ Returned " .. moved .. " to vault")
                    else
                        print("      ⚠ Could not return to vault (manual pickup needed)")
                    end
                end
            end
        else
            print("  ⚠ No items in output depot")
            print("  Possible reasons:")
            print("    - Craft is still processing")
            print("    - Items went to different location")
            print("    - Mechanical crafter configuration issue")
            print("    - Recipe failed to execute")
        end
    end
    
    print("\n╔════════════════════════════════════════╗")
    print("║  ✓ CRAFT SEQUENCE COMPLETED")
    print("║  All steps executed without errors")
    print("║  Check output manually if needed")
    print("╚════════════════════════════════════════╝\n")
    
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
        print("\n" .. string.rep("=", 50))
        print("  NEW CRAFT JOB DETECTED!")
        print(string.rep("=", 50))
        print("  Job ID: " .. data.job.id)
        print("  Item: " .. data.job.itemId) 
        print("  Amount: " .. data.job.amount)
        print(string.rep("=", 50) .. "\n")
        
        print("CRAFT PLAN:")
        print("  1. Fetch recipe from API")
        print("  2. Parse recipe into 3x3 grid")
        print("  3. Find depot (depot_1/2/3)")
        print("  4. Find items in storage (item_vault_5/6)")
        print("  5. Transfer items using peripheral.pushItems()")
        print("  6. Wait for mechanical crafters")
        print("  7. Check output in depot_4")
        print("")
        print("Starting in 3 seconds...")
        sleep(3)
        
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
            print("\n" .. string.rep("█", 50))
            print("  ✓✓✓ JOB #" .. data.job.id .. " COMPLETED!")
            print(string.rep("█", 50) .. "\n")
        else
            print("\n" .. string.rep("!", 50))
            print("  ✗✗✗ JOB #" .. data.job.id .. " FAILED!")
            print("  ERROR: " .. (error or "Unknown"))
            print(string.rep("!", 50) .. "\n")
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
