-- ══════════════════════════════════════════════════════════════════════════
-- ME Terminal Bridge v3.0  (event-loop, no sleep polling)
--
-- Hardware:
--   Storage:          item_vault_5 / 6 / 7
--   Buffer chest:     chest_4
--   Vanilla crafter:  left  (minecraft:crafter)
--   Redstone side:    REDSTONE_SIDE  → triggers crafter
--   Output barrel:    barrel_1  (hopper below crafter)
--   Press depots:     depot_5 / 6 / 7
-- ══════════════════════════════════════════════════════════════════════════

local API_URL = "https://web-production-bf6e3.up.railway.app"

local HEADERS = {
    ["Content-Type"]               = "application/json",
    ["bypass-tunnel-reminder"]     = "true",
    ["ngrok-skip-browser-warning"] = "true",
}

local CRAFTER_NAME   = "left"
local BUFFER_NAME    = "chest_4"
local OUTPUT_NAME    = "barrel_1"
local REDSTONE_SIDE  = "right"   -- change if needed
local PRESS_DEPOTS   = {"depot_5","depot_6","depot_7"}
local VAULT_NAMES    = {"item_vault_5","item_vault_6","item_vault_7"}
local SYNC_INTERVAL  = 2   -- seconds between inventory pushes

-- Devices excluded from storage scan
local EXCLUDED = {
    [CRAFTER_NAME] = true,
    [BUFFER_NAME]  = true,
    [OUTPUT_NAME]  = true,
}
for _, d in ipairs(PRESS_DEPOTS) do EXCLUDED[d] = true end


-- ══════════════════════════════════════════════════════════════════════════
-- Storage helpers
-- ══════════════════════════════════════════════════════════════════════════

function findAllStorage()
    local devices, seen = {}, {}
    for _, name in ipairs(peripheral.getNames()) do
        if not seen[name] and not EXCLUDED[name] and not name:match("^depot_") then
            local pt = peripheral.getType(name)
            if pt and (pt:find("vault") or pt:find("chest") or
                       pt:find("barrel") or pt == "inventory") then
                local p = peripheral.wrap(name)
                if p and p.list then
                    table.insert(devices, {name=name, type=pt, p=p})
                    seen[name] = true
                end
            end
        end
    end
    return devices
end

function scanInventory()
    local inv = {}
    local totalItems, totalStacks = 0, 0
    local devs = findAllStorage()
    for _, d in ipairs(devs) do
        local ok, items = pcall(function() return d.p.list() end)
        if ok and items then
            for slot, item in pairs(items) do
                local id = item.name
                if not inv[id] then
                    inv[id] = { id=id,
                        name      = id:match(":(.+)") or id,
                        namespace = id:match("^(.+):") or "minecraft",
                        totalCount=0, locations={} }
                end
                inv[id].totalCount = inv[id].totalCount + item.count
                table.insert(inv[id].locations, {device=d.name, slot=slot, count=item.count})
                totalItems  = totalItems  + item.count
                totalStacks = totalStacks + 1
            end
        end
    end
    return inv, {totalItems=totalItems, totalStacks=totalStacks, storageDevices=#devs}
end

-- ══════════════════════════════════════════════════════════════════════════
-- HTTP helpers
-- ══════════════════════════════════════════════════════════════════════════

function httpGet(path)
    local ok, r = pcall(http.get, API_URL..path, HEADERS)
    if not ok or not r then return nil end
    local body = r.readAll(); r.close()
    return textutils.unserialiseJSON(body)
end

function httpPost(path, data)
    local body = type(data) == "string" and data or textutils.serialiseJSON(data)
    local ok, r = pcall(http.post, API_URL..path, body, HEADERS)
    if ok and r then local b = r.readAll(); r.close(); return textutils.unserialiseJSON(b) end
    return nil
end

function pushInventory(inv, stats)
    local items = {}
    for _, d in pairs(inv) do
        table.insert(items, {id=d.id, name=d.name, namespace=d.namespace,
                             count=d.totalCount, locations=#d.locations})
    end
    table.sort(items, function(a,b) return a.count > b.count end)
    httpPost("/api/inventory", {
        computerId = os.getComputerID(),
        timestamp  = os.epoch("utc"),
        stats      = stats,
        items      = items
    })
end

function getNextJob()
    local d = httpGet("/api/queue/next")
    return d and d.job
end

function reportDone(id, ok, err)
    local ep = ok and "/api/queue/"..id.."/complete" or "/api/queue/"..id.."/fail"
    httpPost(ep, ok and {} or {error=err or "unknown"})
end


-- ══════════════════════════════════════════════════════════════════════════
-- Recipe fetching + parsing
-- ══════════════════════════════════════════════════════════════════════════

function getRecipe(itemId)
    local d = httpGet("/api/recipes/"..itemId:gsub(":", "__"))
    if d and d.recipes and #d.recipes > 0 then return d.recipes[1] end
    return nil
end

local function extractIng(ing)
    if type(ing) == "string" then return ing end
    if type(ing) ~= "table"  then return nil end
    if ing.item then return ing.item end
    if ing.tag  then return "#"..ing.tag end
    if ing[1]   then return extractIng(ing[1]) end
    return nil
end

-- Returns grid[1..9], mode ("crafter"|"press")
function parseGrid(recipe)
    local t    = recipe.type
    local data = recipe.data or {}

    if t == "minecraft:crafting_shaped" or t == "create:mechanical_crafting" then
        local pat = data.pattern or {}
        local key = data.key     or {}
        local grid = {}
        for row = 1, 3 do
            for col = 1, 3 do
                local idx = (row-1)*3+col
                local ch  = pat[row] and pat[row]:sub(col,col) or " "
                if ch ~= " " and key[ch] then grid[idx] = extractIng(key[ch]) end
            end
        end
        return grid, "crafter"

    elseif recipe.custom then          -- custom recipe stored on server
        local raw  = recipe.grid or {}
        local grid = {}
        for i = 1, 9 do
            local v = raw[i]
            grid[i] = (v ~= nil and v ~= "") and v or nil
        end
        return grid, "crafter"

    elseif t == "create:pressing" or t == "create:cutting"
        or t == "create:milling" or t == "create:crushing"
        or t == "create:sandpaper_polishing" or t == "create:deploying" then
        local ings = data.ingredients or {}
        local grid = {}; grid[5] = extractIng(ings[1] or ings)
        return grid, "press"
    end

    return nil, "unknown"
end

-- ══════════════════════════════════════════════════════════════════════════
-- Item search  (tag resolution + priority)
-- ══════════════════════════════════════════════════════════════════════════

function findItem(itemId)
    local isTag = itemId:sub(1,1) == "#"
    local tag   = isTag and itemId:sub(2) or nil
    local best  = nil

    for _, dev in ipairs(findAllStorage()) do
        local ok, items = pcall(function() return dev.p.list() end)
        if ok and items then
            for slot, item in pairs(items) do
                if not isTag then
                    if item.name == itemId then return dev.name, slot, item.count end
                else
                    local sim  = tag:gsub("^c:",""):gsub("^forge:","")
                    local base = sim:match("([^/]+)$") or sim
                    local pats = {base}
                    if sim:match("^ingots/")  then pats={base.."_ingot"}
                    elseif sim:match("^plates/") or sim:match("^sheets/") then pats={base.."_plate",base.."_sheet"}
                    elseif sim:match("^nuggets/") then pats={base.."_nugget"}
                    elseif sim:match("^dusts/")   then pats={base.."_dust"}
                    elseif sim:match("^gears/")   then pats={base.."_gear"}
                    elseif sim:match("^rods/")    then pats={base.."_rod"} end
                    local ibase = item.name:match(":(.+)") or item.name
                    for _, pat in ipairs(pats) do
                        if ibase == pat or ibase:match(pat.."$") then
                            local prio = item.name:match("^minecraft:") and 1
                                      or item.name:match("^create:")    and 2 or 10
                            if not best or prio < best.prio then
                                best = {storage=dev.name, slot=slot, count=item.count, prio=prio}
                            end
                            break
                        end
                    end
                end
            end
        end
    end
    if best then return best.storage, best.slot, best.count end
    return nil
end


-- ══════════════════════════════════════════════════════════════════════════
-- Transfer helpers  (via buffer chest — the only reliable method)
-- ══════════════════════════════════════════════════════════════════════════

function moveViaBuffer(srcName, srcSlot, qty, targetName, targetSlot)
    local buf = peripheral.wrap(BUFFER_NAME)
    if not buf then return false, "no buffer" end

    local short = srcName:match("item_vault_%d+")
               or srcName:match("chest_%d+")
               or srcName:match("([^:]+)$") or srcName

    -- vault → buffer
    local ok, n = pcall(function() return buf.pullItems(short,   srcSlot, qty) end)
    if not ok or not n or n==0 then
        ok, n = pcall(function() return buf.pullItems(srcName, srcSlot, qty) end)
    end
    if not ok or not n or n==0 then return false, "vault→buffer failed" end

    sleep(0.05)
    local bs = nil
    for s in pairs(buf.list()) do bs = s; break end
    if not bs then return false, "item lost in buffer" end

    -- buffer → target
    local ok2, n2
    if targetSlot then
        ok2,n2 = pcall(function() return buf.pushItems(targetName, bs, n, targetSlot) end)
    else
        ok2,n2 = pcall(function() return buf.pushItems(targetName, bs, n) end)
    end
    if not ok2 or not n2 or n2==0 then return false, "buffer→target failed" end
    return true, n2
end

function flushToVault(periphName)
    local p = peripheral.wrap(periphName)
    if not p or not p.list then return end
    local buf = peripheral.wrap(BUFFER_NAME)
    if not buf then return end
    local pShort = periphName:match("depot_%d+")
                or periphName:match("barrel_%d+")
                or periphName:match("([^:]+)$") or periphName
    for slot, item in pairs(p.list()) do
        local ok,n = pcall(function() return buf.pullItems(pShort, slot, item.count) end)
        if ok and n and n>0 then
            sleep(0.05)
            for bs in pairs(buf.list()) do
                for _, vn in ipairs(VAULT_NAMES) do
                    local vault = peripheral.wrap(vn)
                    if vault then
                        pcall(function() vault.pullItems(BUFFER_NAME, bs, n) end)
                    end
                end
                break
            end
        end
        sleep(0.05)
    end
end

function clearCrafter()
    local cr = peripheral.wrap(CRAFTER_NAME)
    if not cr then return end
    for slot in pairs(cr.list()) do
        pcall(function() cr.pushItems(BUFFER_NAME, slot, 64) end)
        sleep(0.05)
        local buf = peripheral.wrap(BUFFER_NAME)
        if buf then
            for bs in pairs(buf.list()) do
                for _, vn in ipairs(VAULT_NAMES) do
                    local v = peripheral.wrap(vn)
                    if v then pcall(function() v.pullItems(BUFFER_NAME, bs, 64) end) end
                end
                break
            end
        end
    end
end


-- ══════════════════════════════════════════════════════════════════════════
-- Crafting execution
-- ══════════════════════════════════════════════════════════════════════════

function runCrafterRecipe(job, grid)
    local crafter = peripheral.wrap(CRAFTER_NAME)
    if not crafter then return false, "crafter not found" end
    local output = peripheral.wrap(OUTPUT_NAME)
    if not output then return false, "output barrel not found" end

    local totalCrafted = 0

    for pass = 1, job.amount do
        term.setTextColor(colors.yellow)
        print("  Pass "..pass.."/"..job.amount)
        term.setTextColor(colors.white)

        clearCrafter()

        -- Fill slots 1-9
        for slotIdx = 1, 9 do
            if grid[slotIdx] then
                local itemId = grid[slotIdx]
                local src, srcSlot, avail = findItem(itemId)
                if not src then
                    return false, "missing: "..itemId
                end
                print("    ["..slotIdx.."] "..itemId:match(":(.+)").." <- "..src)
                local ok, n = moveViaBuffer(src, srcSlot, 1, CRAFTER_NAME, slotIdx)
                if not ok then return false, "slot "..slotIdx.." failed: "..(n or "?") end
                sleep(0.1)
            end
        end

        -- Redstone pulse → crafter fires
        print("  Redstone pulse ("..REDSTONE_SIDE..")...")
        redstone.setOutput(REDSTONE_SIDE, true)
        sleep(0.4)
        redstone.setOutput(REDSTONE_SIDE, false)

        -- Wait up to 5s for result in barrel_1
        local got = false
        for t = 1, 10 do
            sleep(0.5)
            for _, itm in pairs(output.list()) do
                if itm.name == job.itemId then
                    totalCrafted = totalCrafted + itm.count
                    term.setTextColor(colors.lime)
                    print("  Got "..itm.count.."x "..itm.name)
                    term.setTextColor(colors.white)
                    got = true; break
                end
            end
            if got then break end
        end

        if not got then
            print("  [WARN] No output after 5s — wrong RS side or recipe issue?")
        end

        -- Flush barrel → vault
        flushToVault(OUTPUT_NAME)
        sleep(0.1)
    end

    print("  Total crafted: "..totalCrafted.."x "..job.itemId)
    return true
end

function runPressRecipe(job, grid)
    local itemId = grid[5]
    if not itemId then return false, "no ingredient" end

    -- Find a free press depot
    local depotName = nil
    for _, dn in ipairs(PRESS_DEPOTS) do
        local p = peripheral.wrap(dn)
        if p and p.list then
            local empty = true
            for _ in pairs(p.list()) do empty=false; break end
            if empty then depotName=dn; break end
        end
    end
    if not depotName then return false, "no free press depot" end

    print("  Depot: "..depotName)

    for pass = 1, job.amount do
        print("  Pass "..pass.."/"..job.amount)
        local src, srcSlot = findItem(itemId)
        if not src then return false, "missing: "..itemId end

        local ok, n = moveViaBuffer(src, srcSlot, 1, depotName)
        if not ok then return false, "transfer failed: "..(n or "?") end

        -- Wait for press to process
        local depot = peripheral.wrap(depotName)
        local done  = false
        for t = 1, 20 do
            sleep(0.5)
            if depot and depot.list then
                for _, itm in pairs(depot.list()) do
                    if itm.name == job.itemId then
                        term.setTextColor(colors.lime)
                        print("  Got "..itm.count.."x "..itm.name)
                        term.setTextColor(colors.white)
                        done=true; break
                    end
                end
            end
            if done then break end
        end

        flushToVault(depotName)
        sleep(0.1)
    end

    return true
end

function executeJob(job)
    term.setTextColor(colors.cyan)
    print("\n>>> JOB #"..job.id.." — "..job.amount.."x "..job.itemId)
    term.setTextColor(colors.white)

    local recipe = getRecipe(job.itemId)
    if not recipe then
        return false, "no recipe for "..job.itemId
    end
    print("  Recipe: "..recipe.type)

    local grid, mode = parseGrid(recipe)
    if not grid or mode == "unknown" then
        return false, "unsupported recipe type: "..recipe.type
    end

    -- Show grid
    for row = 1, 3 do
        local line = "  "
        for col = 1, 3 do
            local v = grid[(row-1)*3+col]
            line = line.."["..(v and (v:match(":(.+)") or v):sub(1,6) or "  --  ").."]"
        end
        print(line)
    end

    if mode == "crafter" then
        return runCrafterRecipe(job, grid)
    else
        return runPressRecipe(job, grid)
    end
end


-- ══════════════════════════════════════════════════════════════════════════
-- Display
-- ══════════════════════════════════════════════════════════════════════════

local lastStats = {totalItems=0, totalStacks=0, storageDevices=0}
local lastOnline = false
local craftCount = 0

function redraw()
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1,1)

    -- Header bar
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write("  ME TERMINAL v3.0 — EVENT LOOP  ")
    term.setBackgroundColor(colors.black)

    term.setCursorPos(1,3)
    term.setTextColor(colors.yellow)
    print("Storage : "..lastStats.storageDevices.." devices")
    term.setTextColor(colors.cyan)
    print("Items   : "..lastStats.totalItems.." total  |  "..lastStats.totalStacks.." stacks")

    term.setCursorPos(1,6)
    if lastOnline then
        term.setTextColor(colors.lime)
        print("API     : ONLINE")
    else
        term.setTextColor(colors.red)
        print("API     : OFFLINE")
    end

    term.setTextColor(colors.white)
    term.setCursorPos(1,8)
    print("Crafted : "..craftCount.." jobs done")

    term.setCursorPos(1,10)
    term.setTextColor(colors.gray)
    print(API_URL)
    term.setCursorPos(1,11)
    term.setTextColor(colors.lightBlue)
    print(API_URL.."/crafts.html")

    term.setCursorPos(1,13)
    term.setTextColor(colors.white)
    print("Ctrl+T to stop")
end

-- ══════════════════════════════════════════════════════════════════════════
-- Event loop  (parallel tasks)
-- ══════════════════════════════════════════════════════════════════════════

-- Task 1: inventory sync — fires on timer, no sleep polling
function taskInventorySync()
    -- send immediately on start
    local inv, stats = scanInventory()
    lastOnline = pcall(function() pushInventory(inv, stats) end)
    lastStats  = stats
    redraw()

    while true do
        -- Use os.startTimer and wait for that specific timer event
        local timerId = os.startTimer(SYNC_INTERVAL)
        while true do
            local ev, id = os.pullEvent("timer")
            if id == timerId then break end
        end
        local inv2, stats2 = scanInventory()
        lastStats = stats2
        local ok = pcall(function() pushInventory(inv2, stats2) end)
        lastOnline = ok
        redraw()
    end
end

-- Task 2: craft queue poller — uses short timer, processes one job at a time
function taskCraftQueue()
    while true do
        local timerId = os.startTimer(3)  -- check every 3 seconds
        while true do
            local ev, id = os.pullEvent("timer")
            if id == timerId then break end
        end

        local job = getNextJob()
        if job then
            term.setTextColor(colors.orange)
            print("\n=== CRAFT JOB #"..job.id.." ==="  )
            print("    "..job.amount.."x "..job.itemId)
            term.setTextColor(colors.white)

            local ok, err = executeJob(job)
            if ok then
                craftCount = craftCount + 1
                reportDone(job.id, true)
                term.setTextColor(colors.lime)
                print(">>> JOB #"..job.id.." DONE")
            else
                reportDone(job.id, false, err)
                term.setTextColor(colors.red)
                print(">>> JOB #"..job.id.." FAILED: "..(err or "?"))
            end
            term.setTextColor(colors.white)
            redraw()
        end
    end
end

-- Task 3: keyboard input (Ctrl+T handled by CC itself, but we can catch other keys)
function taskInput()
    while true do
        local ev, key = os.pullEvent("key")
        -- r = manual redraw/rescan
        if key == keys.r then
            local inv, stats = scanInventory()
            lastStats = stats
            pushInventory(inv, stats)
            redraw()
        end
    end
end

-- ══════════════════════════════════════════════════════════════════════════
-- Startup
-- ══════════════════════════════════════════════════════════════════════════

term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1,1)
term.setTextColor(colors.yellow)
print("ME Terminal v3.0 starting...")
print("Testing API connection...")

local testOk = pcall(function()
    local r = http.get(API_URL.."/api/stats", HEADERS)
    if r then r.close() else error("no response") end
end)

if not testOk then
    term.setTextColor(colors.red)
    print("ERROR: Cannot connect to "..API_URL)
    print("Check Railway deployment!")
    return
end

term.setTextColor(colors.lime)
print("Connected! Starting event loop...")
print("Press R to force rescan, Ctrl+T to stop")
sleep(1)

-- Run all tasks in parallel — no blocking sleep anywhere
parallel.waitForAny(taskInventorySync, taskCraftQueue, taskInput)
