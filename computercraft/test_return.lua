-- ══════════════════════════════════════════════════════════════════════════
-- TEST RETURN - Test moving items from depot back to vault
-- ══════════════════════════════════════════════════════════════════════════

print("╔════════════════════════════════════════╗")
print("║  RETURN TEST")
print("║  Moving items from depot to vault")
print("╚════════════════════════════════════════╝\n")

-- Find depot with items
local depotName = nil
local depot = nil
local itemSlot = nil
local itemData = nil

print("Step 1: Finding depot with items...")
for _, name in ipairs(peripheral.getNames()) do
    if name:match("depot") and not name:match("depot_4") then
        local p = peripheral.wrap(name)
        if p and p.list then
            local items = p.list()
            for slot, item in pairs(items) do
                depotName = name
                depot = p
                itemSlot = slot
                itemData = item
                break
            end
        end
        if depot then break end
    end
end

if not depot or not itemSlot then
    print("✗ No items found in any depot")
    print("Put something in depot_5, depot_6, or depot_7 first")
    return
end

print("✓ Found: " .. itemData.name .. " x" .. itemData.count)
print("  In: " .. depotName .. " slot " .. itemSlot)
print("")

-- Find vault
print("Step 2: Finding vault...")
local vaultName = nil
local vault = nil

for _, name in ipairs(peripheral.getNames()) do
    if name:match("item_vault") then
        vaultName = name
        vault = peripheral.wrap(name)
        print("✓ Found: " .. name)
        break
    end
end

if not vault then
    print("✗ No vault found")
    return
end

print("")

-- Find buffer chest
print("Step 3: Finding buffer chest...")
local bufferName = nil
local buffer = nil

for _, name in ipairs(peripheral.getNames()) do
    local ptype = peripheral.getType(name)
    if ptype == "minecraft:chest" or (name:match("chest") and not name:match("vault")) then
        bufferName = name
        buffer = peripheral.wrap(name)
        print("✓ Found: " .. name)
        break
    end
end

if not buffer then
    print("✗ No buffer chest found")
    return
end

print("")

-- Extract short names
local depotShort = depotName:match("depot_%d+") or depotName:match("([^:]+)$")
local vaultShort = vaultName:match("item_vault_%d+") or vaultName:match("([^:]+)$")
local bufferShort = bufferName:match("chest_%d+") or bufferName:match("([^:]+)$")

print("Short names:")
print("  Depot: " .. depotShort)
print("  Vault: " .. vaultShort)
print("  Buffer: " .. bufferShort)
print("")

-- Try methods
print("Step 4: Testing return methods...\n")

print("[Method 1] vault.pullItems(depot, slot, count)")
local success, moved = pcall(function()
    return vault.pullItems(depotShort, itemSlot, itemData.count)
end)
print("  Result: " .. tostring(moved))

if success and moved and moved > 0 then
    print("  ✓✓✓ SUCCESS!")
    return
else
    print("  ✗ Failed")
end

print("")
print("[Method 2] depot.pushItems(vault, slot, count)")
success, moved = pcall(function()
    return depot.pushItems(vaultShort, itemSlot, itemData.count)
end)
print("  Result: " .. tostring(moved))

if success and moved and moved > 0 then
    print("  ✓✓✓ SUCCESS!")
    return
else
    print("  ✗ Failed")
end

print("")
print("[Method 3] Via buffer: depot -> chest -> vault")
print("  Step 1: buffer.pullItems(depot, slot, count)")
success, moved = pcall(function()
    return buffer.pullItems(depotShort, itemSlot, itemData.count)
end)
print("  Moved to buffer: " .. tostring(moved))

if not success or not moved or moved == 0 then
    print("  ✗ Failed to move to buffer")
    print("  Error: " .. tostring(moved))
    return
end

-- Find in buffer
local bufferSlot = nil
for slot, item in pairs(buffer.list()) do
    if item.name == itemData.name then
        bufferSlot = slot
        break
    end
end

if not bufferSlot then
    print("  ✗ Item not found in buffer")
    return
end

print("  Found in buffer slot: " .. bufferSlot)
print("  Step 2: vault.pullItems(buffer, slot, count)")
success, moved = pcall(function()
    return vault.pullItems(bufferShort, bufferSlot, itemData.count)
end)
print("  Moved to vault: " .. tostring(moved))

if success and moved and moved > 0 then
    print("\n  ✓✓✓ SUCCESS! Returned " .. moved .. " items to vault")
else
    print("\n  ✗ Failed to move from buffer to vault")
    print("  Error: " .. tostring(moved))
end
