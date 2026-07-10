-- ══════════════════════════════════════════════════════════════════════════
-- Depot Monitor - Real-time inventory tracking with API integration
-- ══════════════════════════════════════════════════════════════════════════

local API_URL = "https://web-production-bf6e3.up.railway.app"
local DEPOT_SIDE = "bottom"
local MONITOR_SIDE = "right"  -- Optional: monitor for display
local UPDATE_INTERVAL = 2

-- HTTP headers for Railway bypass
local HTTP_HEADERS = {
    ["Content-Type"] = "application/json",
    ["bypass-tunnel-reminder"] = "true",
    ["ngrok-skip-browser-warning"] = "true"
}

-- Get all connected depots/chests via wired modem network
function findStorageDevices()
    local devices = {}
    for _, name in ipairs(peripheral.getNames()) do
        local ptype = peripheral.getType(name)
        if ptype == "inventory" or ptype:find("chest") or ptype:find("depot") then
            table.insert(devices, name)
        end
    end
    return devices
end

-- Scan all storage and build inventory map
function scanInventory()
    local inventory = {}
    local devices = findStorageDevices()
    
    for _, device in ipairs(devices) do
        local inv = peripheral.wrap(device)
        if inv and inv.list then
            for slot, item in pairs(inv.list()) do
                local itemId = item.name
                if not inventory[itemId] then
                    inventory[itemId] = {
                        id = itemId,
                        totalCount = 0,
                        locations = {}
                    }
                end
                inventory[itemId].totalCount = inventory[itemId].totalCount + item.count
                table.insert(inventory[itemId].locations, {
                    device = device,
                    slot = slot,
                    count = item.count
                })
            end
        end
    end
    
    return inventory
end

-- Get item details from API
function getItemDetails(itemId)
    local safeId = itemId:gsub(":", "__")
    local response = http.get(API_URL .. "/api/recipes/" .. safeId, HTTP_HEADERS)
    if response then
        local data = textutils.unserialiseJSON(response.readAll())
        response.close()
        return data
    end
    return nil
end

-- Display on monitor or terminal
function displayInventory(output, inventory)
    output.clear()
    output.setCursorPos(1, 1)
    output.setTextColor(colors.white)
    output.setBackgroundColor(colors.black)
    
    output.write("=== STORAGE INVENTORY ===")
    output.setCursorPos(1, 2)
    output.write("Items: " .. #inventory)
    
    local y = 4
    for itemId, data in pairs(inventory) do
        if y > 20 then break end  -- Limit display
        
        output.setCursorPos(1, y)
        local name = itemId:match(":(.+)") or itemId
        output.write(string.format("%s: %d", name:sub(1, 20), data.totalCount))
        y = y + 1
    end
end

-- Monitor loop
function monitorLoop()
    local output = term
    if peripheral.isPresent(MONITOR_SIDE) then
        output = peripheral.wrap(MONITOR_SIDE)
    end
    
    while true do
        local inventory = scanInventory()
        displayInventory(output, inventory)
        sleep(UPDATE_INTERVAL)
    end
end

print("Starting Depot Monitor...")
print("Connected storage devices: " .. #findStorageDevices())
sleep(1)

monitorLoop()
