--[[
    BuffLedger - /bl test [fraction]: renders a synthetic set of buffs
    built straight from Data.lua's own tables (every BUFF_CLASS/
    BUFF_RACIAL/BUFF_WORLD entry, plus a handful of representative
    consumable names) run through the real BL.Categorize/sort/layout
    pipeline, so grouping/gaps/colors/row-wrapping can be sanity-checked
    without needing a raid actually holding every buff at once.

    fraction (0-1, default 0.75) picks how much of the full catalog to
    show, shuffled - lets you preview a busier or sparser bar. Random
    durations/stacks stand in for real ones. `/bl test off` returns to
    normal live scanning.

    There's no API to look up an arbitrary spell's icon by name on this
    client, so icons come from BL.GetCachedIcon (Core.lua) - the real
    icon texture, remembered the moment this addon has ever actually
    seen that buff live (from Bar.lua's own scanning, or from /bl
    scan-ing a raid). Anything never encountered falls back to a plain
    question-mark icon; running /bl scan against a real raid first is
    the fastest way to fill the cache in before testing.
]]

BuffLedger = BuffLedger or {}
local BL = BuffLedger

BL.testMode = false
BL.testEntries = nil

local PLACEHOLDER_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- CONSUMABLE_SUBSTRINGS is mostly bare fragments ("Elixir", "Oil of"),
-- not real buff names, so test data needs its own small list of actual
-- complete consumable buff names to stand in for that category.
local TEST_CONSUMABLES = {
    "Elixir of the Mongoose", "Elixir of Giants", "Elixir of Fortitude",
    "Greater Arcane Elixir", "R.O.I.D.S.", "Juju Might", "Winterfall Firewater",
    "Rumsey Rum Black Label", "Nightfin Soup", "Spirit of Zanza",
    "Flask of the Titans", "Free Action Potion", "Mageblood Potion",
}

local function BuildAllKnownBuffNames()
    local list = {}
    local name

    for name in pairs(BL.BUFF_CLASS) do
        table.insert(list, name)
    end
    for name in pairs(BL.BUFF_RACIAL) do
        table.insert(list, name)
    end
    for name in pairs(BL.BUFF_WORLD) do
        table.insert(list, name)
    end
    for name in pairs(BL.BUFF_CONSUMABLE) do
        table.insert(list, name)
    end

    local i
    for i = 1, table.getn(TEST_CONSUMABLES) do
        table.insert(list, TEST_CONSUMABLES[i])
    end

    return list
end

local function ShuffledCopy(list)
    local out = {}
    local i
    for i = 1, table.getn(list) do
        out[i] = list[i]
    end
    for i = table.getn(out), 2, -1 do
        local j = math.random(i)
        out[i], out[j] = out[j], out[i]
    end
    return out
end

function BL.StartTest(fraction)
    fraction = fraction or 0.75

    local names = ShuffledCopy(BuildAllKnownBuffNames())
    local total = table.getn(names)
    local want = math.max(1, math.min(total, math.floor(total * fraction + 0.5)))

    local now = GetTime()
    local entries = {}
    local realIcons = 0
    local i
    for i = 1, want do
        local name = names[i]
        local categoryId = BL.Categorize(name)
        local cachedIcon = BL.GetCachedIcon(name)
        if cachedIcon then realIcons = realIcons + 1 end
        local entry = {
            index = "TEST" .. i,
            name = name,
            icon = cachedIcon or PLACEHOLDER_ICON,
            spellId = nil,
            expirationTime = now + math.random(60, 3600),
            stackCount = (math.random(100) > 85) and math.random(2, 5) or 0,
            categoryId = categoryId,
            isTest = true,
        }
        entry.sortKey = BL.CategoryPriority(categoryId)
        table.insert(entries, entry)
    end

    -- Mirrors Bar.lua's own comparator (soonest-to-expire first within
    -- a group, name as final tie-break) - the random durations here
    -- give this a real chance to be visibly exercised in test mode.
    table.sort(entries, function(a, b)
        if a.sortKey ~= b.sortKey then return a.sortKey < b.sortKey end
        local aExp, bExp = BL.EffectiveExpiration(a.expirationTime), BL.EffectiveExpiration(b.expirationTime)
        if aExp ~= bExp then return aExp < bExp end
        return a.name < b.name
    end)

    BL.testEntries = entries
    BL.testMode = true
    BL.ForceRefresh()
    BL.Print("Test mode: showing " .. want .. "/" .. total .. " known buffs (" .. realIcons .. " with real icons you've actually seen, rest placeholder). \"/bl test off\" to return to live buffs.")
end

function BL.StopTest()
    BL.testMode = false
    BL.testEntries = nil
    BL.ForceRefresh()
    BL.Print("Test mode off - back to live buffs.")
end
