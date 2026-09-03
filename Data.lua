--[[
    BuffLedger - buff categorization tables.

    The client's aura API has no concept of "which class gave you this" -
    it's just a name/icon/duration. This file is the lookup that fills
    that gap: an exact buff-name -> source-class table for real class
    buffs (ranks share one display name, so one entry covers all of
    them), plus a couple of substring heuristics for the families too
    varied to list by hand (elixirs/potions/flasks, Sayge's fortunes).
    Anything matching neither falls into OTHER - trinket procs, item-use
    effects, quest buffs, and anything not yet added below.

    Extend this table as you run into unrecognized buffs; that's the
    only maintenance this addon needs.
]]

BuffLedger = BuffLedger or {}
local BL = BuffLedger

BL.CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

BL.CLASS_PRIORITY = {}
do
    local i
    for i = 1, table.getn(BL.CLASS_ORDER) do
        BL.CLASS_PRIORITY[BL.CLASS_ORDER[i]] = i
    end
end

BL.CLASS_COLOR = {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
    PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
    HUNTER  = { r = 0.67, g = 0.83, b = 0.45 },
    ROGUE   = { r = 1.00, g = 0.96, b = 0.41 },
    PRIEST  = { r = 1.00, g = 1.00, b = 1.00 },
    SHAMAN  = { r = 0.00, g = 0.44, b = 0.87 },
    MAGE    = { r = 0.41, g = 0.80, b = 0.94 },
    WARLOCK = { r = 0.58, g = 0.51, b = 0.79 },
    DRUID   = { r = 1.00, g = 0.49, b = 0.04 },
}

-- Order: class buffs first (the thing you asked to sort by), then
-- weapon enchants, then consumables, then world buffs / racials /
-- everything else. WEAPON isn't from C_UnitAuras at all - see Bar.lua's
-- CollectWeaponEntries, which reads GetWeaponEnchantInfo() instead and
-- builds synthetic entries tagged with this same group.
BL.GROUP_PRIORITY = { CLASS = 1, WEAPON = 2, CONSUMABLE = 3, WORLD = 4, RACIAL = 5, OTHER = 6 }

BL.GROUP_COLOR = {
    WEAPON     = { 0.20, 0.85, 0.85 },
    CONSUMABLE = { 0.30, 1.00, 0.40 },
    WORLD      = { 1.00, 0.82, 0.00 },
    RACIAL     = { 0.60, 0.60, 0.90 },
    OTHER      = { 0.65, 0.65, 0.65 },
}

-- Exact buff name -> class token. Ranked spells (Fortitude, Blessing of
-- Might, ...) share one display name across all ranks, so one entry
-- covers every rank.
BL.BUFF_CLASS = {
    -- Paladin
    ["Blessing of Might"] = "PALADIN", ["Greater Blessing of Might"] = "PALADIN",
    ["Blessing of Wisdom"] = "PALADIN", ["Greater Blessing of Wisdom"] = "PALADIN",
    ["Blessing of Kings"] = "PALADIN", ["Greater Blessing of Kings"] = "PALADIN",
    ["Blessing of Salvation"] = "PALADIN", ["Greater Blessing of Salvation"] = "PALADIN",
    ["Blessing of Sanctuary"] = "PALADIN", ["Greater Blessing of Sanctuary"] = "PALADIN",
    ["Blessing of Light"] = "PALADIN", ["Greater Blessing of Light"] = "PALADIN",
    ["Blessing of Protection"] = "PALADIN",
    ["Blessing of Freedom"] = "PALADIN",
    ["Blessing of Sacrifice"] = "PALADIN",
    ["Devotion Aura"] = "PALADIN", ["Retribution Aura"] = "PALADIN", ["Concentration Aura"] = "PALADIN",
    ["Shadow Resistance Aura"] = "PALADIN", ["Frost Resistance Aura"] = "PALADIN", ["Fire Resistance Aura"] = "PALADIN",
    ["Righteous Fury"] = "PALADIN",
    ["Seal of Righteousness"] = "PALADIN", ["Seal of Command"] = "PALADIN", ["Seal of the Crusader"] = "PALADIN",
    ["Seal of Wisdom"] = "PALADIN", ["Seal of Light"] = "PALADIN", ["Seal of Justice"] = "PALADIN",
    ["Daybreak"] = "PALADIN",
    ["Divine Intervention"] = "PALADIN",
    ["Sanctity Aura"] = "PALADIN",

    -- Priest
    ["Power Word: Fortitude"] = "PRIEST", ["Prayer of Fortitude"] = "PRIEST",
    ["Power Word: Shield"] = "PRIEST",
    ["Divine Spirit"] = "PRIEST", ["Prayer of Spirit"] = "PRIEST",
    ["Shadow Protection"] = "PRIEST", ["Prayer of Shadow Protection"] = "PRIEST",
    ["Fear Ward"] = "PRIEST",
    ["Inner Fire"] = "PRIEST",
    ["Renew"] = "PRIEST",
    ["Levitate"] = "PRIEST",
    ["Power Infusion"] = "PRIEST",
    ["Touch of Weakness"] = "PRIEST",

    -- Druid
    ["Mark of the Wild"] = "DRUID", ["Gift of the Wild"] = "DRUID",
    ["Thorns"] = "DRUID",
    ["Regrowth"] = "DRUID",
    ["Rejuvenation"] = "DRUID",
    ["Omen of Clarity"] = "DRUID",
    ["Moonkin Aura"] = "DRUID",
    ["Emerald Blessing"] = "DRUID",
    ["Innervate"] = "DRUID",

    -- Mage
    ["Arcane Intellect"] = "MAGE", ["Arcane Brilliance"] = "MAGE",
    ["Ice Armor"] = "MAGE", ["Frost Armor"] = "MAGE", ["Mage Armor"] = "MAGE",
    ["Dampen Magic"] = "MAGE", ["Amplify Magic"] = "MAGE",
    ["Ice Barrier"] = "MAGE", ["Ice Block"] = "MAGE",

    -- Warrior
    ["Battle Shout"] = "WARRIOR", ["Commanding Shout"] = "WARRIOR",

    -- Shaman (totem-granted buffs - some clients show the "Totem" suffix,
    -- some just the effect name, so both forms are listed)
    ["Grace of Air Totem"] = "SHAMAN", ["Grace of Air"] = "SHAMAN",
    ["Strength of Earth Totem"] = "SHAMAN", ["Strength of Earth"] = "SHAMAN",
    ["Stoneskin Totem"] = "SHAMAN", ["Stoneskin"] = "SHAMAN",
    ["Windwall Totem"] = "SHAMAN",
    ["Frost Resistance Totem"] = "SHAMAN", ["Fire Resistance Totem"] = "SHAMAN", ["Nature Resistance Totem"] = "SHAMAN",
    ["Mana Spring Totem"] = "SHAMAN", ["Mana Spring"] = "SHAMAN",
    ["Healing Stream Totem"] = "SHAMAN", ["Healing Stream"] = "SHAMAN",
    ["Windfury Totem"] = "SHAMAN",
    ["Water Shield"] = "SHAMAN",
    ["Lightning Shield"] = "SHAMAN",
    ["Healing Way"] = "SHAMAN",

    -- Warlock
    ["Blood Pact"] = "WARLOCK",
    ["Detect Invisibility"] = "WARLOCK",
    ["Unending Breath"] = "WARLOCK",
    ["Demon Skin"] = "WARLOCK", ["Demon Armor"] = "WARLOCK", ["Fel Armor"] = "WARLOCK",
    ["Firestone"] = "WARLOCK", ["Greater Firestone"] = "WARLOCK", ["Fel Firestone"] = "WARLOCK", ["Master Firestone"] = "WARLOCK",
    ["Voidstone"] = "WARLOCK", ["Greater Voidstone"] = "WARLOCK", ["Fel Voidstone"] = "WARLOCK", ["Master Voidstone"] = "WARLOCK",
    ["Felstone"] = "WARLOCK",
    ["Wrathstone"] = "WARLOCK",
    ["Burning Wish"] = "WARLOCK",
    ["Touch of Shadow"] = "WARLOCK",
    ["Fel Energy"] = "WARLOCK",
    ["Fel Stamina"] = "WARLOCK",
    ["Spellstone"] = "WARLOCK",
    ["Soulstone Resurrection"] = "WARLOCK",
    ["Detect Lesser Invisibility"] = "WARLOCK",
    ["Detect Greater Invisibility"] = "WARLOCK",
    ["Paranoia"] = "WARLOCK",
    ["Shadow Ward"] = "WARLOCK",
    ["Shadow Trance"] = "WARLOCK",

    -- Hunter
    ["Aspect of the Pack"] = "HUNTER",
    ["Trueshot Aura"] = "HUNTER",
}

-- Racial abilities that actually produce a lasting self-buff icon
-- (War Stomp/Perception/Will of the Forsaken don't - they're instant
-- effects with no icon of their own).
BL.BUFF_RACIAL = {
    ["Blood Fury"] = true,
    ["Stoneform"] = true,
    ["Berserking"] = true,
}

-- Named world buffs - one-off zone/boss/event buffs, too specific to
-- pattern-match, so listed exactly.
BL.BUFF_WORLD = {
    ["Songflower Serenade"] = true,
    ["Warchief's Blessing"] = true,
    ["Rallying Cry of the Dragonslayer"] = true,
    ["Spirit of Zandalar"] = true,
    -- Dire Maul tribute runs show these with a "(DM-N Tribute)" suffix on
    -- some server cores - both forms listed since it's unconfirmed which
    -- this client uses.
    ["Fengus' Ferocity"] = true, ["Fengus' Ferocity (DM-N Tribute)"] = true,
    ["Mol'dar's Moxie"] = true, ["Mol'dar's Moxie (DM-N Tribute)"] = true,
    ["Slip'kik's Savvy"] = true, ["Slip'kik's Savvy (DM-N Tribute)"] = true,
}

-- Exact buff names for consumables whose real in-game aura name is a
-- short, generic effect name rather than the item's own name - e.g.
-- Elixir of Shadow Power's actual buff is just "Shadow Power", Cerebral
-- Cortex Compound's is "Infallible Mind", scrolls show their bare stat
-- name ("Agility", "Armor", ...). A substring match on the ITEM name is
-- useless for these (the aura name never contains it), so they need
-- exact entries instead - and exact (not substring) matters here
-- specifically because several are single generic words that would be
-- dangerous as a substring (e.g. "Armor" would blindly match inside
-- "Frost Armor"/"Mage Armor"/"Demon Armor" if this were a substring
-- table; as an exact table those still resolve correctly via the real
-- CLASS entries above, checked first).
--
-- Sourced from RABuffs (github.com/Purple-bloom/Rabuffs, itself forked
-- from pepopo978/Rabuffs), whose buff database records each item's real
-- tooltip text alongside its icon/spellId for its own raid-buff tracker
-- - the exact same "what name does this aura actually show" problem
-- this file exists to solve. Not verified against this specific client
-- one by one; if one of these turns out wrong (or collides with
-- something), the fix is a one-line removal here.
BL.BUFF_CONSUMABLE = {
    -- Flasks/elixirs/potions whose granted buff is a short stat name,
    -- not the item name
    ["Supreme Power"] = true, -- Flask of Supreme Power
    ["Distilled Wisdom"] = true, -- Flask of Distilled Wisdom
    ["Chromatic Resistance"] = true, -- Flask of Chromatic Resistance
    ["Greater Firepower"] = true, -- Elixir of Greater Firepower
    ["Fire Power"] = true, -- Elixir of Firepower
    ["Greater Nature Power"] = true, ["Greater Arcane Power"] = true, ["Greater Frost Power"] = true,
    ["Infallible Mind"] = true, -- Cerebral Cortex Compound
    ["Health II"] = true, -- Elixir of Fortitude
    ["Rage of Ages"] = true, -- R.O.I.D.S.
    ["Strike of the Scorpok"] = true, -- Ground Scorpok Assay
    ["Fire Shield"] = true, -- Oil of Immolation
    ["Regeneration"] = true, -- Troll's Blood Potions
    ["Restoration"] = true, -- Restorative Potion
    ["Invisibility"] = true, ["Lesser Invisibility"] = true, -- Invisibility Potions
    ["Free Action"] = true, ["Living Free Action"] = true, -- Free/Living Action Potions
    ["Speed"] = true, -- Swiftness Potion
    ["Resistance"] = true, -- Magic Resistance Potion
    ["Mana Regeneration"] = true, -- Nightfin Soup, Sagefish Delight, Mageblood Potion
    -- Protection potions (short forms; "Shadow Protection" isn't listed
    -- here since it's already a Priest CLASS entry above - the potion
    -- and the priest spell share that exact aura name, an inherent
    -- ambiguity in the name alone)
    ["Fire Protection"] = true, ["Frost Protection"] = true,
    ["Nature Protection"] = true, ["Arcane Protection"] = true, ["Holy Protection"] = true,
    -- Food/drink whose buff is a generic effect name, not the food's name
    ["Increased Stamina"] = true, ["Increased Agility"] = true, ["Increased Intellect"] = true,
    ["Increased Healing Bonus"] = true,
    ["Rumsey Rum Dark"] = true, ["Gordok Green Grog"] = true,
    ["Blessed Sunfruit"] = true, ["Blessed Sunfruit Juice"] = true,
    ["Sheen of Zanza"] = true, ["Swiftness of Zanza"] = true,
    -- Scrolls (Scroll of Agility/Protection/Intellect/Spirit/Stamina/
    -- Strength) show only the bare stat name
    ["Agility"] = true, ["Armor"] = true, ["Intellect"] = true,
    ["Spirit"] = true, ["Stamina"] = true, ["Strength"] = true,
    -- Concoctions (ZG alternates for several of the elixirs above)
    ["Concoction of the Arcane Giant"] = true, ["Concoction of the Emerald Mongoose"] = true,
    ["Concoction of the Dreamwater"] = true,
}

-- Substrings shared by whole families of purchasable consumables -
-- covers elixirs/flasks/potions/scrolls/food without needing an entry
-- per item. Checked with plain (non-pattern) string.find, so item names
-- containing "." (e.g. "R.O.I.D.S.") don't need escaping.
--
-- The Turtle-WoW-specific entries below (Zanza/Scorpok/Danonzo's/
-- Medivh's/etc.) are one-off names, not families, but a substring entry
-- works just as well for an exact name and keeps everything in one
-- table - sourced from https://turtle-wow.fandom.com/wiki/Consumables.
BL.CONSUMABLE_SUBSTRINGS = {
    "Elixir", "Flask", "Potion", "Juju", "Well Fed", "Scroll of",
    "Rumsey Rum", "R.O.I.D.S.", "Oil of",
    -- Turtle WoW consumables
    "Spirit of Zanza", "Ground Scorpok Assay", "Winterfall Firewater",
    "Gift of Arthas", "Nordanaar Herbal Tea", "Cerebral Cortex Compound",
    "Gurubashi Gumbo", "Le Fishe Au Chocolat", "Sweet Mountain Berry",
    "Dragonbreath Chili", "Dreamtonic", "Juice Striped Melon",
    "Nightfin Soup", "Frozen Rune",
    -- Flasks (already caught by the generic "Flask" entry above - listed
    -- explicitly too so they're easy to find/extend here)
    "Flask of the Titans", "Flask of Distilled Wisdom", "Flask of Supreme Power",
    "Flask of Chromatic Resistance", "Flask of Petrification",
    "Tel'Abim", -- Danonzo's Tel'Abim Medley/Surprise/Delight
    "Medivh's Merlot", -- covers both the plain and "Blue" variants
    "Mushroom", -- Power Mushroom, Hardened Mushroom
    "Shadow Power", -- Elixir of Shadow Power shows in-game as just "Shadow Power"
}

-- Lowercased mirrors of the exact-name tables above, built once at load -
-- matching is done on string.lower(name) so a buff isn't stranded in
-- OTHER just because this client's aura.name capitalizes differently
-- than the tables above happen to (e.g. "blessing of light" vs
-- "Blessing of Light").
local function BuildLowerLookup(t)
    local out = {}
    local k, v
    for k, v in pairs(t) do
        out[string.lower(k)] = v
    end
    return out
end

local BUFF_CLASS_LOWER = BuildLowerLookup(BL.BUFF_CLASS)
local BUFF_RACIAL_LOWER = BuildLowerLookup(BL.BUFF_RACIAL)
local BUFF_WORLD_LOWER = BuildLowerLookup(BL.BUFF_WORLD)
local BUFF_CONSUMABLE_LOWER = BuildLowerLookup(BL.BUFF_CONSUMABLE)

local CONSUMABLE_SUBSTRINGS_LOWER = {}
do
    local i
    for i = 1, table.getn(BL.CONSUMABLE_SUBSTRINGS) do
        CONSUMABLE_SUBSTRINGS_LOWER[i] = string.lower(BL.CONSUMABLE_SUBSTRINGS[i])
    end
end

-- name -> group, class (class only meaningful when group == "CLASS")
function BL.Categorize(name)
    if not name or name == "" then
        return "OTHER"
    end
    local lname = string.lower(name)

    local class = BUFF_CLASS_LOWER[lname]
    if class then
        return "CLASS", class
    end

    if BUFF_RACIAL_LOWER[lname] then
        return "RACIAL"
    end

    if BUFF_WORLD_LOWER[lname] or string.find(lname, "sayge's dark fortune", 1, true) then
        return "WORLD"
    end

    if BUFF_CONSUMABLE_LOWER[lname] then
        return "CONSUMABLE"
    end

    -- Family-pattern fallbacks - these classes have far more named
    -- variants (every blessing/seal, every totem, every aspect) than are
    -- worth listing by hand, and every real match is unambiguous: any
    -- HELPFUL buff whose name contains "totem" is a shaman buff, full
    -- stop. Checked after the exact tables above, so a specific entry
    -- there (e.g. "Righteous Fury") always wins if one exists.
    -- "hand of" catches Turtle WoW's renamed single-target blessings
    -- (Hand of Protection/Freedom/Salvation/... instead of vanilla's
    -- Blessing of Protection/Freedom/Salvation/...) alongside the
    -- regular blessings/seals.
    if string.find(lname, "blessing of", 1, true) or string.find(lname, "seal of", 1, true)
        or string.find(lname, "hand of", 1, true) then
        return "CLASS", "PALADIN"
    end
    if string.find(lname, "totem", 1, true) then
        return "CLASS", "SHAMAN"
    end
    if string.find(lname, "aspect of", 1, true) then
        return "CLASS", "HUNTER"
    end

    local i
    for i = 1, table.getn(CONSUMABLE_SUBSTRINGS_LOWER) do
        if string.find(lname, CONSUMABLE_SUBSTRINGS_LOWER[i], 1, true) then
            return "CONSUMABLE"
        end
    end

    return "OTHER"
end
