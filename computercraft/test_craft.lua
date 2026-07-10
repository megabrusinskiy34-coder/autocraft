-- ══════════════════════════════════════════════════════════════════════════
-- TEST CRAFT - Shows detailed diagnostics without running main loop
-- ══════════════════════════════════════════════════════════════════════════

local API_URL = "https://web-production-bf6e3.up.railway.app"
local HTTP_HEADERS = {
    ["Content-Type"] = "application/json",
    ["bypass-tunnel-reminder"] = "true",
    ["ngrok-skip-browser-warning"] = "true"
}

print("╔════════════════════════════════════════╗")
print("║  CRAFT SYSTEM DIAGNOSTICS TEST")
print("╚════════════════════════════════════════╝\n")

-- Test 1: List all peripherals
print("\n[TEST 1] Listing all peripherals...")
local allPeripherals = peripheral.getNames()
print("  Found " .. #allPeripherals .. " peripherals:")

for _, name in ipairs(allPeripherals) do
    local ptype = peripheral.getType(name)
    print("    - " .. name .. " (type: " .. ptype .. ")")
    
    -- Check if it's a depot
    if name:match("depot") then
        print("      ^ This is a DEPOT!")
        local p = peripheral.wrap(name)
        if p and p.list then
            local items = p.list()
            local count = 0
            for _ in pairs(items) do count = count + 1 end
            print("      Contains " .. count .. " items")
        end
    end
    
    -- Check if it's storage
    if name:match("vault") or name:match("chest") then
        print("      ^ This is STORAGE!")
        local p = peripheral.wrap(name)
        if p and p.list then
            local items = p.list()
            local count = 0
            for _ in pairs(items) do count = count + 1 end
            print("      Contains " .. count .. " item stacks")
        end
    end
end

-- Test 2: Check API connection
print("\n[TEST 2] Testing API connection...")
print("  URL: " .. API_URL)

local success, response = pcall(function()
    return http.get(API_URL .. "/api/stats", HTTP_HEADERS)
end)

if success and response then
    print("  ✓ API is reachable!")
    local data = textutils.unserialiseJSON(response.readAll())
    response.close()
    print("  Total recipes: " .. (data.totalRecipes or "unknown"))
    print("  Total items: " .. (data.totalItems or "unknown"))
else
    print("  ✗ API connection failed!")
end

-- Test 3: Check craft queue
print("\n[TEST 3] Checking craft queue...")

local success, response = pcall(function()
    return http.get(API_URL .. "/api/queue", HTTP_HEADERS)
end)

if success and response then
    local data = textutils.unserialiseJSON(response.readAll())
    response.close()
    
    print("  Queue size: " .. (data.total or 0))
    
    if data.queue and #data.queue > 0 then
        print("  Jobs in queue:")
        for _, job in ipairs(data.queue) do
            print("    #" .. job.id .. ": " .. job.itemId .. " (" .. job.status .. ")")
        end
    else
        print("  No jobs in queue")
    end
else
    print("  ✗ Failed to check queue")
end

-- Test 4: Get a sample recipe
print("\n[TEST 4] Testing recipe fetch...")
print("  Trying to fetch recipe for: create:brass_ingot")

local success, response = pcall(function()
    return http.get(API_URL .. "/api/recipes/create__brass_ingot", HTTP_HEADERS)
end)

if success and response then
    local data = textutils.unserialiseJSON(response.readAll())
    response.close()
    
    if data.recipes and #data.recipes > 0 then
        print("  ✓ Recipe found!")
        print("  Recipe type: " .. data.recipes[1].type)
        print("  Recipe has pattern: " .. tostring(data.recipes[1].data.pattern ~= nil))
        print("  Recipe has key: " .. tostring(data.recipes[1].data.key ~= nil))
    else
        print("  ✗ No recipe found")
    end
else
    print("  ✗ Recipe fetch failed")
end

print("\n╔════════════════════════════════════════╗")
print("║  DIAGNOSTICS COMPLETE")
print("╚════════════════════════════════════════╝")
print("\nIf you see problems above, the craft will fail.")
print("Run 'me_terminal' to start the actual ME Terminal.")
