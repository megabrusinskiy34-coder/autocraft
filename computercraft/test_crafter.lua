-- Test minecraft:crafter (vanilla 1.21 autocrafter)
-- Run this to check slots and transfers

print("=== MINECRAFT CRAFTER TEST ===\n")

local crafter = peripheral.wrap("left")
if not crafter then
    print("ERROR: 'left' not found!")
    return
end

print("Type: " .. tostring(peripheral.getType("left")))
print("Size: " .. crafter.size())
print("")

-- Show current contents
print("Current crafter contents:")
local items = crafter.list()
local found = 0
for slot, item in pairs(items) do
    print("  Slot " .. slot .. ": " .. item.name .. " x" .. item.count)
    found = found + 1
end
if found == 0 then print("  (empty)") end
print("")

-- Find chest_4
local buffer = peripheral.wrap("chest_4")
if not buffer then
    print("chest_4 not found!")
    return
end

print("chest_4 contents:")
for slot, item in pairs(buffer.list()) do
    print("  Slot " .. slot .. ": " .. item.name .. " x" .. item.count)
end
print("")

-- Test: put 1 item from chest_4 into crafter slot 5 (center)
local bufItems = buffer.list()
local firstSlot = nil
for s, _ in pairs(bufItems) do firstSlot = s; break end

if firstSlot then
    local item = bufItems[firstSlot]
    print("Testing: push " .. item.name .. " from chest_4 slot " .. firstSlot .. " -> crafter slot 5")
    
    -- crafter.pullItems(source, sourceSlot, count, targetSlot)
    local ok, moved = pcall(function()
        return crafter.pullItems("chest_4", firstSlot, 1, 5)
    end)
    print("  pullItems result: ok=" .. tostring(ok) .. " moved=" .. tostring(moved))
    
    if not (ok and moved and moved > 0) then
        -- try buffer pushItems
        ok, moved = pcall(function()
            return buffer.pushItems("left", firstSlot, 1, 5)
        end)
        print("  pushItems result: ok=" .. tostring(ok) .. " moved=" .. tostring(moved))
    end
    
    print("\nCrafter after transfer:")
    for slot, item in pairs(crafter.list()) do
        print("  Slot " .. slot .. ": " .. item.name .. " x" .. item.count)
    end
else
    print("chest_4 is empty, put some items in it first")
end

print("\n=== SLOT LAYOUT ===")
print("Crafter 3x3 slots:")
print("  [1][2][3]")
print("  [4][5][6]")
print("  [7][8][9]")
print("")

-- Find all peripherals to locate output container
print("All peripherals:")
for _, name in ipairs(peripheral.getNames()) do
    print("  " .. name .. " -> " .. peripheral.getType(name))
end
