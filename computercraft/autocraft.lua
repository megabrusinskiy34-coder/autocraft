-- ══════════════════════════════════════════════════════════════════════════
-- Create AutoCraft System for ComputerCraft
-- Connects to web API and manages Create depot crafting
-- ══════════════════════════════════════════════════════════════════════════

-- CONFIGURATION
local API_URL = "https://web-production-bf6e3.up.railway.app"  -- Change to your Railway URL
local DEPOT_SIDE = "bottom"  -- Depot connected via wired modem
local ASSEMBLER_SIDE = "top"  -- Mechanical arm or deployer
local REFRESH_INTERVAL = 5  -- seconds

-- ══════════════════════════════════════════════════════════════════════════
-- API Functions
-- ══════════════════════════════════════════════════════════════════════════

function apiGet(endpoint)
    local response = http.get(API_URL .. endpoint)
    if not response then
        return nil, "Connection failed"
    end
    local data = response.readAll()
    response.close()
    return textutils.unserialiseJSON(data)
end

function getItemRecipes(itemId)
    -- itemId format: "create:brass_ingot"
    local safeId = itemId:gsub(":", "__")
    return apiGet("/api/recipes/" .. safeId)
end

function searchItems(query)
    return apiGet("/api/search?q=" .. textutils.urlEncode(query))
end

function getAllItems(namespace)
    local endpoint = "/api/items"
    if namespace then
        endpoint = endpoint .. "?namespace=" .. namespace
    end
    return apiGet(endpoint)
end

-- ══════════════════════════════════════════════════════════════════════════
-- Depot Management
-- ══════════════════════════════════════════════════════════════════════════

function getDepotInventory()
    local depot = peripheral.wrap(DEPOT_SIDE)
    if not depot then
        return nil, "Depot not found on " .. DEPOT_SIDE
    end
    
    local items = {}
    for slot, item in pairs(depot.list()) do
        table.insert(items, {
            slot = slot,
            name = item.name,
            count = item.count,
            displayName = item.displayName or item.name
        })
    end
    return items
end

function getItemInDepot(slot)
    local depot = peripheral.wrap(DEPOT_SIDE)
    if not depot then return nil end
    return depot.getItemDetail(slot or 1)
end

function pushItemToDepot(fromSide, fromSlot, amount)
    local depot = peripheral.wrap(DEPOT_SIDE)
    if not depot then return false end
    
    local source = peripheral.wrap(fromSide)
    if not source then return false end
    
    return source.pushItems(DEPOT_SIDE, fromSlot, amount)
end

function pullItemFromDepot(toSide, slot, amount)
    local depot = peripheral.wrap(DEPOT_SIDE)
    if not depot then return false end
    
    return depot.pushItems(toSide, slot or 1, amount)
end

-- ══════════════════════════════════════════════════════════════════════════
-- Recipe Processing
-- ══════════════════════════════════════════════════════════════════════════

function findRecipeForItem(itemId)
    print("Searching recipes for: " .. itemId)
    local data = getItemRecipes(itemId)
    
    if not data or not data.recipes or #data.recipes == 0 then
        return nil, "No recipes found"
    end
    
    -- Return first recipe (you can filter by type here)
    return data.recipes[1]
end

function parseRecipeIngredients(recipe)
    local ingredients = {}
    local recipeData = recipe.data
    
    -- Handle different recipe formats
    if recipeData.ingredients then
        for _, ing in ipairs(recipeData.ingredients) do
            if type(ing) == "table" then
                if ing.item then
                    table.insert(ingredients, ing.item)
                elseif ing.tag then
                    table.insert(ingredients, "tag:" .. ing.tag)
                end
            elseif type(ing) == "string" then
                table.insert(ingredients, ing)
            end
        end
    end
    
    return ingredients
end

-- ══════════════════════════════════════════════════════════════════════════
-- UI Functions
-- ══════════════════════════════════════════════════════════════════════════

function clearScreen()
    term.clear()
    term.setCursorPos(1, 1)
end

function drawHeader()
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.clearLine()
    term.setCursorPos(1, 1)
    print("  CREATE AUTOCRAFT SYSTEM  ")
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

function drawMenu()
    clearScreen()
    drawHeader()
    print("")
    print("1. View Depot Inventory")
    print("2. Search Item")
    print("3. Craft Item")
    print("4. Browse All Items")
    print("5. System Stats")
    print("0. Exit")
    print("")
    write("Choose option: ")
end

function viewDepotInventory()
    clearScreen()
    drawHeader()
    print("\n=== Depot Inventory ===\n")
    
    local items, err = getDepotInventory()
    if not items then
        print("Error: " .. (err or "Unknown"))
        sleep(2)
        return
    end
    
    if #items == 0 then
        print("Depot is empty")
    else
        for _, item in ipairs(items) do
            print(string.format("[%d] %s x%d", item.slot, item.displayName, item.count))
        end
    end
    
    print("\nPress any key to continue...")
    os.pullEvent("key")
end

function searchItemMenu()
    clearScreen()
    drawHeader()
    print("\n=== Search Item ===\n")
    write("Enter search query: ")
    local query = read()
    
    print("\nSearching...")
    local result = searchItems(query)
    
    if not result or not result.items or #result.items == 0 then
        print("No items found")
        sleep(2)
        return
    end
    
    print("\nResults:")
    for i, item in ipairs(result.items) do
        print(string.format("%d. %s (%s)", i, item.name, item.id))
    end
    
    print("\nPress any key to continue...")
    os.pullEvent("key")
end

function craftItemMenu()
    clearScreen()
    drawHeader()
    print("\n=== Craft Item ===\n")
    write("Enter item ID (e.g. create:brass_ingot): ")
    local itemId = read()
    
    print("\nLooking up recipe...")
    local recipe, err = findRecipeForItem(itemId)
    
    if not recipe then
        print("Error: " .. (err or "Unknown"))
        sleep(2)
        return
    end
    
    print("\nRecipe Type: " .. recipe.type)
    print("Recipe ID: " .. recipe.id)
    
    local ingredients = parseRecipeIngredients(recipe)
    if #ingredients > 0 then
        print("\nIngredients:")
        for _, ing in ipairs(ingredients) do
            print("  - " .. ing)
        end
    end
    
    print("\n[Recipe data available in API]")
    print("\nPress any key to continue...")
    os.pullEvent("key")
end

function showStats()
    clearScreen()
    drawHeader()
    print("\n=== System Stats ===\n")
    
    print("Loading...")
    local stats = apiGet("/api/stats")
    
    if not stats then
        print("Error: Could not connect to API")
        sleep(2)
        return
    end
    
    print("Total Items: " .. stats.totalItems)
    print("Total Recipes: " .. stats.totalRecipes)
    print("\nTop Recipe Types:")
    
    local sorted = {}
    for rtype, count in pairs(stats.recipeTypes) do
        table.insert(sorted, {type = rtype, count = count})
    end
    table.sort(sorted, function(a, b) return a.count > b.count end)
    
    for i = 1, math.min(5, #sorted) do
        print(string.format("  %s: %d", sorted[i].type, sorted[i].count))
    end
    
    print("\nPress any key to continue...")
    os.pullEvent("key")
end

-- ══════════════════════════════════════════════════════════════════════════
-- Main Loop
-- ══════════════════════════════════════════════════════════════════════════

function main()
    while true do
        drawMenu()
        local choice = read()
        
        if choice == "1" then
            viewDepotInventory()
        elseif choice == "2" then
            searchItemMenu()
        elseif choice == "3" then
            craftItemMenu()
        elseif choice == "4" then
            -- Browse items (TODO)
            print("Coming soon...")
            sleep(1)
        elseif choice == "5" then
            showStats()
        elseif choice == "0" then
            clearScreen()
            print("Goodbye!")
            break
        end
    end
end

-- ══════════════════════════════════════════════════════════════════════════
-- Start
-- ══════════════════════════════════════════════════════════════════════════

print("Initializing Create AutoCraft System...")
print("Connecting to API: " .. API_URL)

-- Test connection
local testResult = apiGet("/api/stats")
if not testResult then
    print("ERROR: Could not connect to API server")
    print("Make sure the server is running and API_URL is correct")
    return
end

print("Connected! Found " .. testResult.totalRecipes .. " recipes")
sleep(1)

main()
