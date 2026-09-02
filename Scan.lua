--[[
    BuffLedger - /bl scan: a one-shot diagnostic that reads every raid
    (or party) member's current buffs and reports which ones Data.lua
    doesn't recognize yet (falling into OTHER) - built so "extend the
    table as you run into unrecognized buffs" (see Data.lua's header)
    can happen a whole raid at once instead of one buff bar at a time.

    Whether a buff appeared on units of exactly one class is a strong
    hint about what to add it as - a name seen only on Paladins is
    almost certainly a Paladin buff, one seen across every class in the
    raid almost certainly isn't a class buff at all (a consumable or
    world buff). This can only guess the CLASS case; consumable/world/
    racial still need a human to confirm.
]]

BuffLedger = BuffLedger or {}
local BL = BuffLedger

local function GetScanUnits()
    local units = {}
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        local n = GetNumRaidMembers()
        local i
        for i = 1, n do
            table.insert(units, "raid" .. i)
        end
    elseif GetNumPartyMembers and GetNumPartyMembers() > 0 then
        table.insert(units, "player")
        local n = GetNumPartyMembers()
        local i
        for i = 1, n do
            table.insert(units, "party" .. i)
        end
    else
        table.insert(units, "player")
    end
    return units
end

function BL.ScanRaidBuffs()
    if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then
        BL.Print("Can't scan - C_UnitAuras.GetAuraDataByIndex isn't available.")
        return
    end

    local units = GetScanUnits()
    -- buff name -> { classes = { classToken = true, ... }, count = n }
    local found = {}
    local u
    for u = 1, table.getn(units) do
        local unit = units[u]
        if UnitExists(unit) then
            local _, classToken = UnitClass(unit)
            local i
            for i = 1, 40 do
                local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
                if aura and aura.name then
                    BL.RecordIcon(aura.name, aura.icon)
                    local rec = found[aura.name]
                    if not rec then
                        rec = { classes = {}, count = 0 }
                        found[aura.name] = rec
                    end
                    rec.count = rec.count + 1
                    if classToken then rec.classes[classToken] = true end
                end
            end
        end
    end

    local unresolved = {}
    local name, rec
    for name, rec in pairs(found) do
        if BL.Categorize(name) == "OTHER" then
            table.insert(unresolved, { name = name, rec = rec })
        end
    end

    if table.getn(unresolved) == 0 then
        BL.Print("Scanned " .. table.getn(units) .. " unit(s) - every buff found is already categorized.")
        return
    end

    table.sort(unresolved, function(a, b) return a.name < b.name end)

    BL.Print("Scanned " .. table.getn(units) .. " unit(s) - " .. table.getn(unresolved) .. " uncategorized buff(s):")
    local j
    for j = 1, table.getn(unresolved) do
        local entry = unresolved[j]
        local classList = {}
        local c
        for c in pairs(entry.rec.classes) do table.insert(classList, c) end
        table.sort(classList)

        local guess
        if table.getn(classList) == 1 then
            guess = "-> looks like " .. classList[1]
        elseif table.getn(classList) > 1 then
            guess = "-> seen on multiple classes (" .. table.concat(classList, ", ") .. "), probably not a class buff"
        else
            guess = "-> no class on record for whoever has it"
        end

        DEFAULT_CHAT_FRAME:AddMessage("  \"" .. entry.name .. "\" (x" .. entry.rec.count .. ") " .. guess)
    end
end
