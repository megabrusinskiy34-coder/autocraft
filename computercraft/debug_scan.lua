-- ══════════════════════════════════════════════════════════════════════════
-- DEBUG SCAN - Check what's being counted in inventory scan
-- ══════════════════════════════════════════════════════════════════════════

print("╔════════════════════════════════════════╗")
print("║  INVENTORY SCAN DEBUG")
print("╚════════════════════════════════════════╝\n")

-- Find all storage
print("Step 1: Finding storage devices...")
local devices = {}
for _, name in ipairs(peripheral.getNames()) do
    local ptype = peripheral.getType(name)
    
    if (ptype == "inventory" or 
       ptype:find("chest") or 
       ptype:find("vault") or 
       ptype:find("barrel")) and
       not name:match("depot") then
        
        table.insert(devices, {
            name = name,
            type = ptype,
            peripheral = peripheral.wrap(name)
        })
        print("  Found: " .. name .. " (" .. ptype .. ")")
    end
end

print("\nTotal storage devices: " .. #devices)
print("")

-- Scan each device
print("Step 2: Scanning each device...\n")

local coalTotal = 0
local coalLocations = {}

for _, device in ipairs(devices) do
    print("═════════════════════════════════════════")
    print("Device: " .. device.name)
    print("═════════════════════════════════════════")
    
    if device.peripheral and device.peripheral.list then
        local items = device.peripheral.list()
        
        local slotCount = 0
        local itemCount = 0
        
        for slot, item in pairs(items) do
            slotCount = slotCount + 1
            itemCount = itemCount + item.count
            
            -- Track coal specifically
            if item.name == "minecraft:coal" then
                coalTotal = coalTotal + item.count
                table.insert(coalLocations, {
                    device = device.name,
                    slot = slot,
                    count = item.count
                })
                print("  COAL in slot " .. slot .. ": " .. item.count)
            end
        end
        
        print("  Total slots: " .. slotCount)
        print("  Total items: " .. itemCount)
    else
        print("  Cannot list items")
    end
    print("")
end

print("╔════════════════════════════════════════╗")
print("║  COAL SUMMARY")
print("╚════════════════════════════════════════╝")
print("Total coal counted: " .. coalTotal)
print("Found in " .. #coalLocations .. " locations:")
for _, loc in ipairs(coalLocations) do
    print("  " .. loc.device .. " slot " .. loc.slot .. ": " .. loc.count)
end

print("\nIf this shows 20k but you have 9.9k:")
print("- Check if coal is in multiple devices")
print("- Check if slots are being counted twice")
print("- Check item.count values above")
