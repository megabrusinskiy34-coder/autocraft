-- ══════════════════════════════════════════════════════════════════════════
-- CRAFT DEBUG - Craft with log file output
-- Usage: craft_debug
-- Logs saved to: craft_log.txt
-- ══════════════════════════════════════════════════════════════════════════

local API_URL = "https://web-production-bf6e3.up.railway.app"
local HTTP_HEADERS = {
    ["Content-Type"] = "application/json",
    ["bypass-tunnel-reminder"] = "true",
    ["ngrok-skip-browser-warning"] = "true"
}

-- Log file
local logFile = fs.open("craft_log.txt", "w")
local function log(msg)
    print(msg)
    if logFile then
        logFile.writeLine(msg)
        logFile.flush()
    end
end

log("╔════════════════════════════════════════╗")
log("║  CRAFT DEBUG - With Log File")
log("╚════════════════════════════════════════╝")
log("")
log("Log will be saved to: craft_log.txt")
log("")

-- ══════════════════════════════════════════════════════════════════════════
-- Helper Functions
-- ══════════════════════════════════════════════════════════════════════════

function findAllStorage()
    local devices = {}
    for _, name in ipairs(peripheral.getNames()) do
        local ptype = peripheral.getType(name)
        
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
function parseCreateSimpleRecipe(recipeData)
    local grid = {}
    
    local ingredients = recipeData.ingredients
    if not ingredients then
        return grid
    end
    
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
    
    local itemId = nil
    if type(ingredient) == "string" then
        itemId = ingredient
    elseif ingredient.item then
        itemId = ingredient.item
    elseif ingredient.tag then
        itemId = ingredient.tag
    elseif ingredient[1] and ingredient[1].item then
        itemId = ingredient[1].item
    end
    
    if itemId then
        grid[5] = itemId  -- Center slot
    end
    
    return grid
end

function findDepot(pattern)
    for _, name in ipairs(peripheral.getNames()) do
        if name:match(pattern) then
            return name, peripheral.wrap(name)
        end
    end
    return nil
end

-- ══════════════════════════════════════════════════════════════════════════
-- CRAFT FUNCTION
-- ══════════════════════════════════════════════════════════════════════════

function executeCraft(job)
    log("\n╔════════════════════════════════════════╗")
    log("║  CRAFT JOB #" .. job.id)
    log("║  Item: " .. job.itemId)
    log("║  Amount: " .. job.amount)
    log("╚════════════════════════════════════════╝")
    
    -- Step 1: Get recipe
    log("\n[STEP 1] Fetching recipe...")
    log("  URL: " .. API_URL .. "/api/recipes/" .. job.itemId:gsub(":", "__"))
    
    local success, recipe = pcall(function()
        return getRecipe(job.itemId)
    end)
    
    if not success then
        log("  ✗ EXCEPTION: " .. tostring(recipe))
        return false, "Recipe fetch crashed"
    end
    
    if not recipe then
        log("  ✗ ERROR: No recipe found")
        return false, "No recipe found"
    end
    
    log("  ✓ Recipe found: " .. recipe.type)
    
    -- Step 2: Parse recipe
    log("\n[STEP 2] Parsing recipe...")
    local grid = {}
    local parseSuccess, parseError
    
    if recipe.type == "minecraft:crafting_shaped" then
        log("  Format: Shaped Crafting")
        parseSuccess, parseError = pcall(function()
            grid = parseShapedRecipe(recipe.data)
        end)
    elseif recipe.type == "create:mechanical_crafting" then
        log("  Format: Mechanical Crafting")
        parseSuccess, parseError = pcall(function()
            grid = parseMechanicalRecipe(recipe.data)
        end)
    elseif recipe.type == "create:pressing" or 
           recipe.type == "create:cutting" or
           recipe.type == "create:milling" or
           recipe.type == "create:crushing" or
           recipe.type == "create:sandpaper_polishing" or
           recipe.type == "create:deploying" then
        log("  Format: Create Simple (" .. recipe.type .. ")")
        log("  NOTE: Uses mechanical press/saw - not crafter!")
        parseSuccess, parseError = pcall(function()
            grid = parseCreateSimpleRecipe(recipe.data)
        end)
    else
        log("  ✗ ERROR: Unsupported type: " .. recipe.type)
        return false, "Unsupported recipe type"
    end
    
    if not parseSuccess then
        log("  ✗ Parse failed: " .. tostring(parseError))
        return false, "Parse failed"
    end
    
    local itemCount = 0
    for i = 1, 9 do
        if grid[i] then itemCount = itemCount + 1 end
    end
    
    log("  ✓ Grid has " .. itemCount .. " items")
    
    log("\n  Recipe Grid:")
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
        log(line)
    end
    
    -- Step 3: Find depot
    log("\n[STEP 3] Finding depot...")
    
    local allPeripherals = peripheral.getNames()
    log("  Total peripherals: " .. #allPeripherals)
    
    for _, name in ipairs(allPeripherals) do
        local ptype = peripheral.getType(name)
        log("    " .. name .. " (" .. ptype .. ")")
    end
    
    local depotName, depot = findDepot("depot_[123]$")
    
    if not depot then
        log("  ✗ ERROR: No depot found!")
        log("  Need: depot_1, depot_2, or depot_3")
        return false, "No depot"
    end
    
    log("  ✓ Using: " .. depotName)
    
    -- Step 4: Transfer items
    log("\n[STEP 4] Transferring items...")
    
    local itemsNeeded = {}
    for index = 1, 9 do
        if grid[index] then
            table.insert(itemsNeeded, {index = index, itemId = grid[index]})
        end
    end
    
    log("  Need " .. #itemsNeeded .. " items")
    
    for itemNum, item in ipairs(itemsNeeded) do
        log("\n  [" .. itemNum .. "/" .. #itemsNeeded .. "] " .. item.itemId)
        
        local storageName, slot, count = findItemInStorage(item.itemId)
        
        if not storageName then
            log("    ✗ Not found in storage!")
            
            -- Show what IS in storage
            log("\n    Storage contents:")
            for _, storage in ipairs(findAllStorage()) do
                log("      " .. storage.name .. ":")
                if storage.peripheral and storage.peripheral.list then
                    local items = storage.peripheral.list()
                    local count = 0
                    for _, i in pairs(items) do
                        if count < 3 then
                            log("        - " .. i.name)
                            count = count + 1
                        end
                    end
                end
            end
            
            return false, "Item not found: " .. item.itemId
        end
        
        log("    Found: " .. storageName .. " slot " .. slot)
        
        local storage = peripheral.wrap(storageName)
        local success, moved = pcall(function()
            return storage.pushItems(depotName, slot, 1)
        end)
        
        if not success then
            log("    ✗ pushItems EXCEPTION: " .. tostring(moved))
            return false, "Transfer exception"
        end
        
        log("    pushItems returned: " .. tostring(moved))
        
        if moved == 0 then
            log("    ✗ 0 items moved!")
            
            -- Check depot
            local depotItems = depot.list()
            log("    Depot contents:")
            for s, i in pairs(depotItems) do
                log("      Slot " .. s .. ": " .. i.name)
            end
            
            return false, "Transfer failed"
        end
        
        log("    ✓ Moved 1 item")
        sleep(0.5)
    end
    
    log("\n  ✓✓✓ All items transferred!")
    
    -- Step 5: Wait
    log("\n[STEP 5] Waiting 5 seconds...")
    for i = 5, 1, -1 do
        log("  " .. i .. "...")
        sleep(1)
    end
    
    -- Step 6: Check output
    log("\n[STEP 6] Checking output...")
    local outputName, output = findDepot("depot_4$")
    
    if output then
        log("  ✓ Found output: " .. outputName)
        local items = output.list()
        local found = false
        for slot, item in pairs(items) do
            log("    " .. item.name .. " x" .. item.count)
            if item.name == job.itemId then
                found = true
            end
        end
        
        if found then
            log("  ✓✓✓ Crafted item found!")
        end
    else
        log("  ⚠ depot_4 not found")
    end
    
    log("\n╔════════════════════════════════════════╗")
    log("║  ✓ CRAFT COMPLETED")
    log("╚════════════════════════════════════════╝")
    
    return true
end

-- ══════════════════════════════════════════════════════════════════════════
-- MAIN
-- ══════════════════════════════════════════════════════════════════════════

log("Getting next job from queue...")

local success, response = pcall(function()
    return http.get(API_URL .. "/api/queue/next", HTTP_HEADERS)
end)

if not success or not response then
    log("✗ API connection failed")
    if logFile then logFile.close() end
    return
end

local data = textutils.unserialiseJSON(response.readAll())
response.close()

if not data.job then
    log("No jobs in queue")
    log("\nOrder craft at: " .. API_URL .. "/me.html")
    if logFile then logFile.close() end
    return
end

log("✓ Job #" .. data.job.id .. " - " .. data.job.itemId)
log("")

-- Execute
local success, error = executeCraft(data.job)

-- Report to server
local endpoint = success and "/api/queue/" .. data.job.id .. "/complete" 
                          or "/api/queue/" .. data.job.id .. "/fail"

local payload = success and {} or {error = error or "Unknown"}
local jsonData = textutils.serialiseJSON(payload)

pcall(function()
    local resp = http.post(API_URL .. endpoint, jsonData, HTTP_HEADERS)
    if resp then resp.close() end
end)

if success then
    log("\n✓✓✓ SUCCESS!")
else
    log("\n✗✗✗ FAILED: " .. (error or "Unknown"))
end

log("\n" .. string.rep("=", 50))
log("Log saved to: craft_log.txt")
log("Read with: edit craft_log.txt")
log("\nPress any key to exit...")

if logFile then
    logFile.close()
end

os.pullEvent("key")
