-- Quick API test script
local API_URL = "https://web-production-bf6e3.up.railway.app"

-- HTTP headers for Railway bypass
local HTTP_HEADERS = {
    ["Content-Type"] = "application/json",
    ["bypass-tunnel-reminder"] = "true",
    ["ngrok-skip-browser-warning"] = "true"
}

print("Testing Create AutoCraft API...")
print("URL: " .. API_URL)
print()

-- Test 1: Stats
print("[1/3] Getting stats...")
local response = http.get(API_URL .. "/api/stats", HTTP_HEADERS)
if response then
    local data = textutils.unserialiseJSON(response.readAll())
    response.close()
    print("  Items: " .. data.totalItems)
    print("  Recipes: " .. data.totalRecipes)
else
    print("  FAILED - Server not reachable")
    return
end

-- Test 2: Search
print()
print("[2/3] Searching for 'brass'...")
response = http.get(API_URL .. "/api/search?q=brass", HTTP_HEADERS)
if response then
    local data = textutils.unserialiseJSON(response.readAll())
    response.close()
    if data.items and #data.items > 0 then
        print("  Found " .. #data.items .. " items")
        print("  First: " .. data.items[1].id)
    end
end

-- Test 3: Get recipe
print()
print("[3/3] Getting brass_ingot recipe...")
response = http.get(API_URL .. "/api/recipes/create__brass_ingot", HTTP_HEADERS)
if response then
    local data = textutils.unserialiseJSON(response.readAll())
    response.close()
    if data.recipes and #data.recipes > 0 then
        print("  Found " .. #data.recipes .. " recipes")
        print("  Type: " .. data.recipes[1].type)
    end
end

print()
print("Test complete!")
