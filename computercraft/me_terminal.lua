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
        
        -- Wait for next update
        sleep(UPDATE_INTERVAL)
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
