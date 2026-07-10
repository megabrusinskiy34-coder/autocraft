-- Quick test script for your exact setup
-- 3 press depots (depot_1, depot_2, depot_3)
-- 9 mechanical crafters (mechanical_crafter_1..9)
-- 1 output depot (depot_4)

print("=== Testing Create AutoCraft Setup ===\n")

-- Find all connected peripherals
print("Scanning peripherals...")
local found = {}
for _, name in ipairs(peripheral.getNames()) do
    print("  " .. name .. " (" .. peripheral.getType(name) .. ")")
    table.insert(found, name)
end

print("\nTotal peripherals: " .. #found)
print("")

-- Test depot access
print("Testing depot_1...")
if peripheral.isPresent("create:depot_1") then
    local depot = peripheral.wrap("create:depot_1")
    print("  ✓ depot_1 accessible")
    
    local items = depot.list()
    if next(items) then
        print("  Items in depot_1:")
        for slot, item in pairs(items) do
            print("    [" .. slot .. "] " .. item.name .. " x" .. item.count)
        end
    else
        print("  (empty)")
    end
else
    print("  ✗ depot_1 not found")
end

print("\nTesting mechanical_crafter_1...")
if peripheral.isPresent("create:mechanical_crafter_1") then
    local crafter = peripheral.wrap("create:mechanical_crafter_1")
    print("  ✓ mechanical_crafter_1 accessible")
    
    local items = crafter.list()
    if next(items) then
        print("  Items in crafter:")
        for slot, item in pairs(items) do
            print("    [" .. slot .. "] " .. item.name .. " x" .. item.count)
        end
    else
        print("  (empty)")
    end
else
    print("  ✗ mechanical_crafter_1 not found")
end

print("\nTesting output depot_4...")
if peripheral.isPresent("create:depot_4") then
    local depot = peripheral.wrap("create:depot_4")
    print("  ✓ depot_4 accessible")
    
    local items = depot.list()
    if next(items) then
        print("  Items in output depot:")
        for slot, item in pairs(items) do
            print("    [" .. slot .. "] " .. item.name .. " x" .. item.count)
        end
    else
        print("  (empty)")
    end
else
    print("  ✗ depot_4 not found")
end

print("\nSetup test complete!")
print("\nNOTE: Make sure peripherals are named correctly:")
print("  - create:depot_1, create:depot_2, create:depot_3 (press inputs)")
print("  - create:mechanical_crafter_1..9 (3x3 grid)")
print("  - create:depot_4 (output)")
