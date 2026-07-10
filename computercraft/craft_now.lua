-- ══════════════════════════════════════════════════════════════════════════
-- CRAFT NOW - Immediately process one craft job from queue
-- Usage: craft_now
-- ══════════════════════════════════════════════════════════════════════════

local API_URL = "https://web-production-bf6e3.up.railway.app"
local HTTP_HEADERS = {
    ["Content-Type"] = "application/json",
    ["bypass-tunnel-reminder"] = "true",
    ["ngrok-skip-browser-warning"] = "true"
}

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

function findDepot(pattern)
    for _, name in ipairs(peripheral.getNames()) do
        if name:match(pattern) and not name:match("depot_4$") then
            return name, peripheral.wrap(name)
        end
    end
    return nil
end

-- ══════════════════════════════════════════════════════════════════════════
-- MAIN CRAFT FUNCTION (WITH DETAILED LOGGING)
-- ══════════════════════════════════════════════════════════════════════════

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
    
    if recipe.data then
        print("\n  Raw recipe data:")
        print("    Has pattern: " .. tostring(recipe.data.pattern ~= nil))
        print("    Has key: " .. tostring(recipe.data.key ~= nil))
        print("    Has result: " .. tostring(recipe.data.result ~= nil))
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
    else
        print("  ✗ ERROR: Unsupported recipe type: " .. recipe.type)
        return false, "Unsupported recipe type: " .. recipe.type
    end
    
    if not parseSuccess then
        print("  ✗ EXCEPTION during parsing: " .. tostring(parseError))
        return false, "Recipe parse failed: " .. tostring(parseError)
    end
    
    local itemCount = 0
    for i = 1, 9 do
        if grid[i] then itemCount = itemCount + 1 end
    end
    
    if itemCount == 0 then
        print("  ✗ ERROR: Recipe grid is empty!")
        return false, "Empty recipe grid"
    end
    
    print("  ✓ Grid parsed: " .. itemCount .. " slots filled")
    
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
    print("  Looking for: depot_1, depot_2, or depot_3")
    
    local allPeripherals = peripheral.getNames()
    local foundDepots = {}
    
    print("\n  All peripherals:")
    for _, name in ipairs(allPeripherals) do
        local ptype = peripheral.getType(name)
        print("    - " .. name .. " (" .. ptype .. ")")
        
        if name:match("depot_%d+$") then
            table.insert(foundDepots, name)
            print("      ^ DEPOT MATCH!")
        end
    end
    
    print("\n  Depots found: " .. #foundDepots)
    
    if #foundDepots == 0 then
        print("\n  ✗ ERROR: No depot found!")
        print("  Expected names: depot_5, depot_6, depot_7, or any depot_N")
        print("  Or with prefix like: create:depot_5")
        return false, "No depot found"
    end
    
    local depotName, depot = findDepot("depot_%d+$")
    if not depot then
        print("  ✗ ERROR: Cannot wrap depot peripheral!")
        return false, "Cannot wrap depot"
    end
    
    print("\n  ✓ Using depot: " .. depotName)
    
    -- Check depot
    local depotItems = depot.list()
    local depotUsed = 0
    for _ in pairs(depotItems) do depotUsed = depotUsed + 1 end
    print("  Depot contains: " .. depotUsed .. " items")
    
    if depotUsed > 0 then
        print("  ⚠ WARNING: Depot not empty!")
        for slot, item in pairs(depotItems) do
            print("    Slot " .. slot .. ": " .. item.name)
        end
    end
    
    -- Step 4: Transfer items
    print("\n[STEP 4] Transferring items to depot...")
    
    local itemsNeeded = {}
    for index = 1, 9 do
        if grid[index] then
            table.insert(itemsNeeded, {index = index, itemId = grid[index]})
        end
    end
    
    print("  Need " .. #itemsNeeded .. " items")
    
    for itemNum, item in ipairs(itemsNeeded) do
        print("\n  [" .. itemNum .. "/" .. #itemsNeeded .. "] " .. item.itemId)
        
        local storageName, slot, count = findItemInStorage(item.itemId)
        
        if not storageName then
            print("    ✗ Not found in storage!")
            return false, "Item not found: " .. item.itemId
        end
        
        print("    Found in: " .. storageName)
        print("    Slot: " .. slot .. ", Count: " .. count)
        
        local storage = peripheral.wrap(storageName)
        print("    Calling: storage.pushItems('" .. depotName .. "', " .. slot .. ", 1)")
        
        local success, moved = pcall(function()
            return storage.pushItems(depotName, slot, 1)
        end)
        
        if not success then
            print("    ✗ EXCEPTION: " .. tostring(moved))
            return false, "Transfer failed: " .. tostring(moved)
        end
        
        print("    Moved: " .. tostring(moved))
        
        if moved == 0 then
            print("    ✗ 0 items moved!")
            return false, "Failed to move " .. item.itemId
        end
        
        print("    ✓ Success!")
        sleep(0.5)
    end
    
    print("\n  ✓✓✓ All items transferred!")
    
    -- Step 5: Wait
    print("\n[STEP 5] Waiting for craft...")
    for i = 5, 1, -1 do
        print("  " .. i .. "...")
        sleep(1)
    end
    
    -- Step 6: Check output
    print("\n[STEP 6] Checking output...")
    local outputName, output = findDepot("depot_%d+$")
    
    if output then
        print("  ✓ Found: " .. outputName)
        local items = output.list()
        for slot, item in pairs(items) do
            print("    Slot " .. slot .. ": " .. item.name .. " x" .. item.count)
            if item.name == job.itemId then
                print("      ✓✓✓ THIS IS IT!")
            end
        end
    else
        print("  ⚠ depot_4 not found")
    end
    
    print("\n╔════════════════════════════════════════╗")
    print("║  ✓ CRAFT COMPLETED")
    print("╚════════════════════════════════════════╝\n")
    
    return true
end

-- ══════════════════════════════════════════════════════════════════════════
-- MAIN - Get next job and execute
-- ══════════════════════════════════════════════════════════════════════════

print("╔════════════════════════════════════════╗")
print("║  CRAFT NOW - Manual Craft Executor")
print("╚════════════════════════════════════════╝\n")

print("Checking queue...")
local success, response = pcall(function()
    return http.get(API_URL .. "/api/queue/next", HTTP_HEADERS)
end)

if not success or not response then
    print("✗ Failed to connect to API")
    print("URL: " .. API_URL)
    return
end

local data = textutils.unserialiseJSON(response.readAll())
response.close()

if not data.job then
    print("No jobs in queue!")
    print("\nGo to website and order a craft:")
    print(API_URL .. "/me.html")
    return
end

print("✓ Found job #" .. data.job.id)
print("")

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
    print("\n✓✓✓ JOB COMPLETED!")
else
    print("\n✗✗✗ JOB FAILED: " .. (error or "Unknown"))
end

print("\n" .. string.rep("=", 50))
print("Press any key to exit...")
os.pullEvent("key")
