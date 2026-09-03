--[[
    BuffLedger v0.1.0

    Standalone buff bar that replaces Blizzard's own player buff frame -
    and pfUI's, if pfUI is loaded - sorting icons by who/what gave them
    to you (source class, world buff, consumable, racial, or other)
    instead of raw aura index order. Debuffs, weapon enchants, and pfUI's
    own debuff frame are left completely alone; this only ever touches
    HELPFUL player auras.

    This file: shared namespace, saved-variable settings, and the flat
    pfUI-styled skinning helpers every icon button uses (see Bar.lua).
]]

BuffLedger = BuffLedger or {}
local BL = BuffLedger

-- Defensive rather than relying purely on a load-time "or {}" - this
-- client restores saved variables from disk AFTER this file's own init
-- line runs, and that restore REPLACES BuffLedgerDB wholesale (same
-- quirk CombatLedger/LootLedger work around - see their Core.lua).
BuffLedgerDB = BuffLedgerDB or {}
BuffLedgerDB.settings = BuffLedgerDB.settings or {}
BL.db = BuffLedgerDB

BL.defaultSettings = {
    showMinimapButton = true,
    locked = false,
    scale = 1,
    iconSize = 30,
    spacing = 4,
    categoryGap = 12, -- extra horizontal gap inserted between icons of different categories
    columns = 10,
    fontSizeOverride = 10, -- text size - always manual, never deferred to pfUI's own font_size even while pfUI is loaded
    fontKey = "expressway", -- see BL.FONTS below
    borderThickness = 1, -- backdrop edge size in pixels, for every flat-skinned frame (icons, background panel, Options window)
    showBackground = false, -- bordered panel behind the whole bar, sized to fit - off by default (most people run this over pfUI's own dock/panel)
    showDurationInside = false, -- overlay the timer text on the icon instead of below it - mirrors pfUI's own "Show Duration Inside Buff" option, same default (off)
    growLeft = true, -- icons grow from the bar's right edge leftward, matching pfUI's own default buff frame direction - false grows left-to-right instead
    consolidate = false, -- collapse each same-category cluster of 2+ buffs into a single icon (soonest-expiring's icon/timer, a count badge, hover for the full list) instead of one icon per buff
    consolidateOnlyGroup = false, -- only consolidate while in a party or raid - solo, every cluster shows normally regardless of the setting above
    consolidateOnlyRaid = false, -- only consolidate while specifically in a raid (stricter than consolidateOnlyGroup - a raid still counts as a group, but a party doesn't count as a raid)
    -- Per-category visibility used to live here as fixed showClass/
    -- showWeapon/... booleans - now that categories are fully dynamic
    -- (Core.lua's category system below), visibility is a `hidden`
    -- field on each category record instead, so it generalizes to any
    -- custom category too.

    -- Debuff bar - same knobs as the buff bar above, independent values
    -- (own position/size/etc, see DebuffBar.lua), minus anything that
    -- only makes sense for the buff bar's category clustering
    -- (categoryGap, per-category visibility) - the debuff bar has no
    -- grouping at all, just dispel-type-colored borders.
    debuffLocked = false,
    debuffScale = 1,
    debuffIconSize = 30,
    debuffSpacing = 4,
    debuffColumns = 10,
    debuffFontSizeOverride = 10,
    debuffFontKey = "expressway",
    debuffBorderThickness = 1,
    debuffShowBackground = false,
    debuffShowDurationInside = false,
    debuffGrowLeft = true,
}

local function EnsureSettingsTable()
    if not BuffLedgerDB.settings then
        BuffLedgerDB.settings = {}
    end
end

function BL.GetSetting(key)
    EnsureSettingsTable()
    local v = BuffLedgerDB.settings[key]
    if v == nil then return BL.defaultSettings[key] end
    return v
end

function BL.SetSetting(key, value)
    EnsureSettingsTable()
    BuffLedgerDB.settings[key] = value
end

-- [ Categories ] -----------------------------------------------------------
--
-- Categories are first-class, fully user-editable data - create/delete/
-- rename/recolor any of them, including the shipped defaults (Data.lua's
-- BL.DEFAULT_CATEGORIES is seed data, read once to populate this table
-- and never again - see its own header comment). "other" is the one
-- exception: it's the permanent catch-all a buff falls back to when its
-- own category was deleted (or never matched one), so deleting IT is
-- refused - there always has to be a landing spot.
local function EnsureCategoriesTable()
    if not BuffLedgerDB.categories then
        BuffLedgerDB.categories = {}
        BuffLedgerDB.categoryOrder = {}
    end
end

-- Declared here (not down by BL.GetOverride/SetOverride where it's
-- primarily used) because BL.DeleteCategory below needs it too, and a
-- local function can only be seen by code defined AFTER its own
-- declaration - same reason Bar.lua's FormatTime lives where it does.
local function EnsureOverridesTable()
    if not BuffLedgerDB.overrides then
        BuffLedgerDB.overrides = {}
    end
end

-- First-run population only - if BuffLedgerDB.categories already exists
-- (even empty, even missing every default), the seeding half is a
-- no-op, so a user's edits from a previous session are never
-- overwritten just because the addon loaded again.
--
-- The second half runs every call, seed or not: a one-time backfill
-- for categories saved before the per-category `consolidate` flag
-- existed (this addon used to have one global on/off setting instead
-- of "consolidate Consumable but not Warrior"). Inherits that old
-- global value once per category (nil is the only way to tell "never
-- migrated" from "migrated to false"), so upgrading doesn't silently
-- turn consolidation off for anyone who had it on everywhere. Cheap
-- once every category has a real true/false here, which happens after
-- the first call post-upgrade.
function BL.EnsureCategoriesSeeded()
    if not BuffLedgerDB.categories then
        EnsureCategoriesTable()
        local i
        for i = 1, table.getn(BL.DEFAULT_CATEGORIES) do
            local def = BL.DEFAULT_CATEGORIES[i]
            BuffLedgerDB.categories[def.id] = {
                name = def.name,
                color = { def.color[1], def.color[2], def.color[3] },
                icon = def.icon,
                hidden = false,
                consolidate = false,
                deletable = def.deletable ~= false,
                builtin = true,
            }
            table.insert(BuffLedgerDB.categoryOrder, def.id)
        end
        return
    end

    local oldGlobal = BL.GetSetting("consolidate") and true or false
    local id, cat
    for id, cat in pairs(BuffLedgerDB.categories) do
        if cat.consolidate == nil then
            cat.consolidate = oldGlobal
        end
    end
end

-- Re-adds any shipped default category currently missing (deleted) -
-- the category-level "remember our baseline" - without touching custom
-- categories or clearing any overrides. A deleted default's old
-- overrides were already redirected to "other" at delete time (see
-- BL.DeleteCategory) and stay there; this only restores the category
-- itself, not what used to point at it.
--
-- Also rebuilds categoryOrder rather than just appending restored ids
-- to the end: every default gets put back in its shipped relative
-- order (Warrior, Paladin, ... Other), with any custom categories kept
-- in their existing relative order after them. Appending-only used to
-- leave the list looking shuffled - e.g. restoring Hunter and Rogue
-- landed them after Other instead of back between Paladin and Priest
-- where they belong.
function BL.ResetCategoriesToDefault()
    BL.EnsureCategoriesSeeded()
    local i
    for i = 1, table.getn(BL.DEFAULT_CATEGORIES) do
        local def = BL.DEFAULT_CATEGORIES[i]
        if not BuffLedgerDB.categories[def.id] then
            BuffLedgerDB.categories[def.id] = {
                name = def.name,
                color = { def.color[1], def.color[2], def.color[3] },
                icon = def.icon,
                hidden = false,
                consolidate = false,
                deletable = def.deletable ~= false,
                builtin = true,
            }
        end
    end

    local newOrder = {}
    for i = 1, table.getn(BL.DEFAULT_CATEGORIES) do
        table.insert(newOrder, BL.DEFAULT_CATEGORIES[i].id)
    end
    local oldOrder = BuffLedgerDB.categoryOrder
    for i = 1, table.getn(oldOrder) do
        local id = oldOrder[i]
        if BuffLedgerDB.categories[id] and not BuffLedgerDB.categories[id].builtin then
            table.insert(newOrder, id)
        end
    end
    BuffLedgerDB.categoryOrder = newOrder
end

-- Confirm-before-acting wrapper around the above - restoring categories
-- is a bulk action a misclick shouldn't be able to trigger silently.
-- Same StaticPopupDialogs shape as BL.ShowClassicAPIRequiredPopup below,
-- just a plain OK/Cancel instead of an edit box.
StaticPopupDialogs["BUFFLEDGER_RESET_CATEGORIES"] = {
    text = "Restore any deleted default categories (Warrior, Paladin, ...)? Your custom categories and buff assignments are untouched either way.",
    button1 = OKAY,
    button2 = CANCEL,
    OnAccept = function()
        BL.ResetCategoriesToDefault()
        BL.ForceRefresh()
        -- BL.ForceRefresh only re-renders the live buff bar - the
        -- Options window (if it's the thing you clicked this from,
        -- which it always is) needs telling separately or its category
        -- list just silently sits stale until closed and reopened.
        if BL.RefreshOptionsWindow then BL.RefreshOptionsWindow() end
        BL.Print("Default categories restored.")
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}

function BL.ConfirmResetCategoriesToDefault()
    StaticPopup_Show("BUFFLEDGER_RESET_CATEGORIES")
end

-- A small hand-built frame instead of a StaticPopupDialogs hasEditBox=1
-- entry - two separate attempts at reading that edit box's text back
-- via getglobal(dialogName.."EditBox") both failed on this client (the
-- exact reason never fully pinned down - possibly a template quirk
-- specific to this client's StaticPopup, possibly something about how
-- OnAccept/OnCancel are invoked vs. a real SetScript handler like
-- OnShow). Holding a direct Lua reference to the actual EditBox this
-- code itself created sidesteps the whole class of "guess the right
-- global name" problem entirely - same reasoning BL.ShowDropdown
-- already uses instead of Blizzard's UIDropDownMenu.
local newCategoryPrompt

-- The real, stock ColorPickerFrame, reparented into this prompt instead
-- of a custom palette - it's a shared global singleton the whole game
-- (and other addons) can use, so it's borrowed while this prompt is
-- open and handed back to UIParent (ReleaseColorPicker) the moment it
-- closes, rather than kept. Its native size isn't something this can
-- inspect ahead of time without a live client, so the prompt frame is
-- sized generously and the picker's position may need a follow-up nudge.
local function ReleaseColorPicker()
    ColorPickerFrame:Hide()
    ColorPickerFrame:SetParent(UIParent)
    ColorPickerFrame:ClearAllPoints()
    ColorPickerFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
end

local function BuildNewCategoryPrompt()
    local f = CreateFrame("Frame", "BuffLedgerNewCategoryPrompt", UIParent)
    f:SetWidth(320)
    f:SetHeight(300)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    BL.ApplyIconSkin(f):SetBackdropBorderColor(BL.FLAT_BORDER_R, BL.FLAT_BORDER_G, BL.FLAT_BORDER_B, 1)

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOP", f, "TOP", 0, -12)
    title:SetFont(BL.GetFontPath(), 12, "OUTLINE")
    title:SetText("New category name:")

    local editBox = CreateFrame("EditBox", "BuffLedgerNewCategoryPromptEditBox", f)
    editBox:SetHeight(20)
    editBox:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -32)
    editBox:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -32)
    editBox:SetAutoFocus(true)
    editBox:SetFont(BL.GetFontPath(), 11, "OUTLINE")
    BL.ApplyIconSkin(editBox):SetBackdropBorderColor(BL.FLAT_BORDER_R, BL.FLAT_BORDER_G, BL.FLAT_BORDER_B, 1)
    f.editBox = editBox

    local selectedColor = { 1, 1, 1 }
    f.selectedColor = selectedColor

    local function MakeButton(text, width)
        local btn = CreateFrame("Button", nil, f)
        btn:SetWidth(width)
        btn:SetHeight(20)
        BL.ApplyIconSkin(btn):SetBackdropBorderColor(BL.FLAT_BORDER_R, BL.FLAT_BORDER_G, BL.FLAT_BORDER_B, 1)
        local label = btn:CreateFontString(nil, "OVERLAY")
        label:SetAllPoints(btn)
        label:SetJustifyH("CENTER")
        label:SetFont(BL.GetFontPath(), 11, "OUTLINE")
        label:SetText(text)
        return btn
    end

    local function Accept()
        local name = editBox:GetText()
        f:Hide()
        ReleaseColorPicker()
        if not name or name == "" then
            BL.Print("No category name entered.")
            return
        end

        local ok, idOrErr = pcall(BL.CreateCategory, name)
        if not ok then
            BL.Print("Failed to create category: " .. tostring(idOrErr))
            return
        end
        BL.SetCategoryColor(idOrErr, selectedColor[1], selectedColor[2], selectedColor[3])

        BL.ForceRefresh()
        if BL.RefreshOptionsWindow then BL.RefreshOptionsWindow() end
        BL.Print("Category \"" .. name .. "\" created.")
    end

    local function CancelPrompt()
        f:Hide()
        ReleaseColorPicker()
    end

    editBox:SetScript("OnEnterPressed", Accept)
    editBox:SetScript("OnEscapePressed", CancelPrompt)

    local okBtn = MakeButton(OKAY, 80)
    okBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 12)
    okBtn:SetScript("OnClick", Accept)

    -- Reparented (not just repositioned) so it's actually a child of
    -- this prompt, not merely visually overlapping it - .func fires
    -- continuously while dragging the wheel/slider, so it only ever
    -- updates the live-tracked color; nothing is committed until this
    -- prompt's own Okay above is clicked. ColorPickerFrame's own
    -- internal Okay/Cancel (if this client's build has them, per the
    -- screenshot showing some) just hide the picker the normal way -
    -- harmless here since Accept/CancelPrompt call ReleaseColorPicker
    -- regardless of whether the picker was already hidden.
    ColorPickerFrame:SetParent(f)
    ColorPickerFrame:ClearAllPoints()
    ColorPickerFrame:SetPoint("TOP", f, "TOP", 0, -58)
    ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    ColorPickerFrame:SetFrameLevel(f:GetFrameLevel() + 1)
    ColorPickerFrame.func = function()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        selectedColor[1], selectedColor[2], selectedColor[3] = r, g, b
    end
    ColorPickerFrame.cancelFunc = function() end
    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame:SetColorRGB(1, 1, 1)

    local cancelBtn = MakeButton(CANCEL, 80)
    cancelBtn:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 12)
    cancelBtn:SetScript("OnClick", CancelPrompt)

    f:Hide()
    return f
end

function BL.PromptNewCategory()
    if not newCategoryPrompt then
        newCategoryPrompt = BuildNewCategoryPrompt()
    end
    newCategoryPrompt.editBox:SetText("")
    newCategoryPrompt.selectedColor[1] = 1
    newCategoryPrompt.selectedColor[2] = 1
    newCategoryPrompt.selectedColor[3] = 1
    -- The picker may have been reparented back to UIParent by
    -- ReleaseColorPicker since this prompt was last shown - re-anchor
    -- it under this prompt every time, not just at first build.
    ColorPickerFrame:SetParent(newCategoryPrompt)
    ColorPickerFrame:ClearAllPoints()
    ColorPickerFrame:SetPoint("TOP", newCategoryPrompt, "TOP", 0, -58)
    ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    ColorPickerFrame:SetFrameLevel(newCategoryPrompt:GetFrameLevel() + 1)
    ColorPickerFrame:SetColorRGB(1, 1, 1)
    ColorPickerFrame:Show()
    newCategoryPrompt:Show()
    newCategoryPrompt.editBox:SetFocus()
end

function BL.CategoryExists(id)
    BL.EnsureCategoriesSeeded()
    return id ~= nil and BuffLedgerDB.categories[id] ~= nil
end

function BL.GetCategory(id)
    BL.EnsureCategoriesSeeded()
    return BuffLedgerDB.categories[id]
end

function BL.GetCategoryName(id)
    local cat = BL.GetCategory(id)
    return (cat and cat.name) or id or "?"
end

function BL.GetCategoryOrder()
    BL.EnsureCategoriesSeeded()
    return BuffLedgerDB.categoryOrder
end

-- entry.categoryId's position in the display/sort order, or a large
-- number for a dangling id that somehow isn't in categoryOrder (should
-- only happen mid-delete, never at rest) - sorts it last rather than
-- erroring.
function BL.CategoryPriority(id)
    BL.EnsureCategoriesSeeded()
    local order = BuffLedgerDB.categoryOrder
    local i
    for i = 1, table.getn(order) do
        if order[i] == id then return i end
    end
    return 9999
end

local function Slugify(name)
    local slug = string.lower(name)
    slug = string.gsub(slug, "[^%w]+", "-")
    slug = string.gsub(slug, "^%-+", "")
    slug = string.gsub(slug, "%-+$", "")
    if slug == "" then slug = "category" end
    return slug
end

-- Returns the new category's id. A plain name collision (two different
-- categories both literally named "Test") gets a numeric suffix on the
-- id so both can coexist - display names don't have to be unique, ids
-- do.
function BL.CreateCategory(name)
    BL.EnsureCategoriesSeeded()
    local baseId = Slugify(name)
    local id = baseId
    local n = 2
    while BuffLedgerDB.categories[id] do
        id = baseId .. "-" .. n
        n = n + 1
    end
    BuffLedgerDB.categories[id] = {
        name = name,
        color = { 1, 1, 1 },
        icon = nil,
        hidden = false,
        consolidate = false,
        deletable = true,
        builtin = false,
    }
    table.insert(BuffLedgerDB.categoryOrder, id)
    return id
end

-- Refuses "other" and anything else marked non-deletable. Sweeps
-- BuffLedgerDB.overrides for any entry pointing at this id and clears
-- it, so nothing is left dangling - those buffs fall through to
-- BL.Categorize's built-in match (if any, and if that one still
-- exists) or "other" on the very next categorization call, with no
-- special-casing needed anywhere else.
function BL.DeleteCategory(id)
    BL.EnsureCategoriesSeeded()
    local cat = BuffLedgerDB.categories[id]
    if not cat or id == "other" or not cat.deletable then
        return false
    end

    BuffLedgerDB.categories[id] = nil
    local i
    for i = table.getn(BuffLedgerDB.categoryOrder), 1, -1 do
        if BuffLedgerDB.categoryOrder[i] == id then
            table.remove(BuffLedgerDB.categoryOrder, i)
        end
    end

    EnsureOverridesTable()
    local name
    for name in pairs(BuffLedgerDB.overrides) do
        if BuffLedgerDB.overrides[name] == id then
            BuffLedgerDB.overrides[name] = nil
        end
    end

    return true
end

-- A confirm-before-acting wrapper, mirroring BL.ConfirmResetCategoriesToDefault -
-- deleting is a bulk-ish action (every buff currently in it falls back
-- to Other) a misclick shouldn't trigger silently. The category id is
-- kept in a plain upvalue instead of threaded through StaticPopup_Show's
-- own data-passing convention - after today's OnAccept/this lesson,
-- relying on the LEAST amount of StaticPopup-specific plumbing possible
-- is worth the small extra caution, even though ordinary text_arg/data
-- passing is probably fine (untested, so not worth the risk here).
local pendingDeleteCategoryId

StaticPopupDialogs["BUFFLEDGER_DELETE_CATEGORY"] = {
    text = "Delete this category?",
    button1 = OKAY,
    button2 = CANCEL,
    OnAccept = function()
        if pendingDeleteCategoryId and BL.DeleteCategory(pendingDeleteCategoryId) then
            BL.ForceRefresh()
            if BL.RefreshOptionsWindow then BL.RefreshOptionsWindow() end
        end
        pendingDeleteCategoryId = nil
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}

function BL.ConfirmDeleteCategory(id)
    local cat = BL.GetCategory(id)
    if not cat then return end
    pendingDeleteCategoryId = id
    StaticPopupDialogs["BUFFLEDGER_DELETE_CATEGORY"].text = "Delete \"" .. cat.name .. "\"? Its buffs fall back to Other."
    StaticPopup_Show("BUFFLEDGER_DELETE_CATEGORY")
end

-- Drag-to-reorder (UI_Options.lua's Categories tab) - removes id from
-- wherever it currently sits and reinserts it at newIndex, clamped to
-- the valid range. This directly IS the buff bar's own sort order
-- (BL.CategoryPriority reads this same array), so a reorder here takes
-- effect on the bar the moment something calls BL.ForceRefresh.
function BL.MoveCategoryToIndex(id, newIndex)
    BL.EnsureCategoriesSeeded()
    local order = BuffLedgerDB.categoryOrder
    local oldIndex
    local i
    for i = 1, table.getn(order) do
        if order[i] == id then oldIndex = i end
    end
    if not oldIndex then return end

    table.remove(order, oldIndex)
    if newIndex < 1 then newIndex = 1 end
    if newIndex > table.getn(order) + 1 then newIndex = table.getn(order) + 1 end
    table.insert(order, newIndex, id)
end

-- "Consolidate All"/"Consolidate None" (UI_Options.lua's Categories
-- tab) - a quick bulk override instead of clicking every row by hand.
function BL.SetAllCategoriesConsolidate(value)
    BL.EnsureCategoriesSeeded()
    local id, cat
    for id, cat in pairs(BuffLedgerDB.categories) do
        cat.consolidate = value
    end
end

function BL.RenameCategory(id, newName)
    local cat = BL.GetCategory(id)
    if cat then cat.name = newName end
end

-- Shared by Bar.lua/Test.lua/DebuffBar.lua's own within-cluster time
-- sorts. expirationTime of 0 (or nil) means "no real timer" (a
-- permanent buff/aura), not "already expired" - sorting it ascending
-- by raw expirationTime would put it FIRST (0 is smaller than any real
-- GetTime()-based timestamp), landing permanent buffs on the
-- soonest-to-expire end of a cluster, which is backwards. This maps
-- that case to a sentinel far larger than any real timestamp instead,
-- so permanent buffs sort last (rightmost, in the growLeft default) -
-- finishing soonest on one end, never finishing on the other. A fixed
-- large number rather than math.huge, which isn't guaranteed to exist
-- on this client's Lua 5.0 - not worth the risk for one comparison.
function BL.EffectiveExpiration(expirationTime)
    if expirationTime and expirationTime > 0 then
        return expirationTime
    end
    return 1e15
end

function BL.SetCategoryColor(id, r, g, b)
    local cat = BL.GetCategory(id)
    if cat then cat.color = { r, g, b } end
end

function BL.ToggleCategoryHidden(id)
    local cat = BL.GetCategory(id)
    if not cat then return end
    cat.hidden = not cat.hidden
end

function BL.ToggleCategoryConsolidate(id)
    local cat = BL.GetCategory(id)
    if not cat then return end
    cat.consolidate = not cat.consolidate
end

-- [ Per-buff-name overrides ] -----------------------------------------------
--
-- Shift-right-click a buff icon (Bar.lua's ShowCategoryAssignMenu), or
-- type a name into the Categories tab's "add a buff" box (UI_Options.lua) -
-- both just call this. Keyed lowercase, same case-insensitive convention
-- Data.lua's own lookup tables use. Checked first by Data.lua's
-- BL.Categorize, ahead of every built-in table/pattern there. Value is
-- a single category id string (not a {group,class} pair - that shape
-- predates the fully dynamic category system and is migrated below).
function BL.GetOverride(name)
    EnsureOverridesTable()
    return BuffLedgerDB.overrides[string.lower(name)]
end

-- A running log of assignments (Categories tab's own "Recent" list) -
-- capped and oldest-trimmed so it can't grow without bound over a long
-- play session. Recorded once, here, rather than at each of
-- BL.ShowCategoryAssignMenu's call sites - shift-right-click on the
-- bar, a popout member tile, and the Categories tab's "Add a Buff" box
-- all funnel through this one function, so this is the single place
-- that sees every assignment regardless of how it was made.
local MAX_ASSIGN_HISTORY = 20

local function EnsureAssignHistoryTable()
    if not BuffLedgerDB.assignHistory then
        BuffLedgerDB.assignHistory = {}
    end
end

local function RecordAssignHistory(name, categoryId)
    EnsureAssignHistoryTable()
    table.insert(BuffLedgerDB.assignHistory, { name = name, categoryId = categoryId, at = time() })
    while table.getn(BuffLedgerDB.assignHistory) > MAX_ASSIGN_HISTORY do
        table.remove(BuffLedgerDB.assignHistory, 1)
    end
end

-- Oldest-first array - a display wanting "most recent" reads it back
-- to front, same as BL.GetCategoryOrder callers read that forward.
function BL.GetAssignHistory()
    EnsureAssignHistoryTable()
    return BuffLedgerDB.assignHistory
end

function BL.SetOverride(name, categoryId)
    EnsureOverridesTable()
    BuffLedgerDB.overrides[string.lower(name)] = categoryId
    RecordAssignHistory(name, categoryId)
end

function BL.ClearOverride(name)
    EnsureOverridesTable()
    BuffLedgerDB.overrides[string.lower(name)] = nil
end

-- One-time migration for overrides saved by the pre-category-system
-- shift-right-click feature ({group=..., class=...} tables) into the
-- new single-id shape. Runs every load but is a no-op after the first
-- time, since every value is a string from then on.
local function MigrateOverrides()
    EnsureOverridesTable()
    local name, value
    for name, value in pairs(BuffLedgerDB.overrides) do
        if type(value) == "table" then
            local id
            if value.group == "CLASS" and value.class then
                id = string.lower(value.class)
            elseif value.group then
                id = string.lower(value.group)
            end
            BuffLedgerDB.overrides[name] = id
        end
    end
end

-- Not BL.EnsureCategoriesSeeded() here too - it reads BL.DEFAULT_CATEGORIES,
-- which doesn't exist yet this early (Data.lua, where that table lives,
-- loads AFTER Core.lua per the .toc order). Every category function
-- above calls it lazily on its own first real use instead, by which
-- point Data.lua has always already loaded. MigrateOverrides has no
-- such dependency, so it's safe to just run once, right here.
MigrateOverrides()

local function EnsureLayoutTable()
    if not BuffLedgerDB.layout then
        BuffLedgerDB.layout = {}
    end
end

function BL.GetLayout()
    EnsureLayoutTable()
    return BuffLedgerDB.layout.main
end

function BL.SaveLayout(frame)
    EnsureLayoutTable()
    local point, _, relPoint, x, y = frame:GetPoint(1)
    BuffLedgerDB.layout.main = {
        point = point or "TOPRIGHT",
        relPoint = relPoint or "TOPRIGHT",
        x = x or -170,
        y = y or -180,
    }
end

function BL.ResetLayout()
    EnsureLayoutTable()
    BuffLedgerDB.layout.main = nil
end

-- Debuff bar equivalents - own key in the same layout table, own
-- default position (a bit further down than the buff bar's default so
-- they don't spawn on top of each other before you've dragged either).
function BL.GetDebuffLayout()
    EnsureLayoutTable()
    return BuffLedgerDB.layout.debuff
end

function BL.SaveDebuffLayout(frame)
    EnsureLayoutTable()
    local point, _, relPoint, x, y = frame:GetPoint(1)
    BuffLedgerDB.layout.debuff = {
        point = point or "TOPRIGHT",
        relPoint = relPoint or "TOPRIGHT",
        x = x or -170,
        y = y or -260,
    }
end

function BL.ResetDebuffLayout()
    EnsureLayoutTable()
    BuffLedgerDB.layout.debuff = nil
end

-- Every real icon this addon has ever actually seen (from live aura
-- scans in Bar.lua, or from /bl scan-ing a raid), keyed by buff name -
-- so /bl test can show real icons instead of a placeholder for anything
-- you've genuinely encountered, and gets more complete the more you
-- play (or the more of a raid you scan). Persisted, not session-only.
function BL.GetCachedIcon(name)
    if not name then return nil end
    return BuffLedgerDB.iconCache and BuffLedgerDB.iconCache[name]
end

function BL.RecordIcon(name, icon)
    if not name or not icon then return end
    if not BuffLedgerDB.iconCache then
        BuffLedgerDB.iconCache = {}
    end
    BuffLedgerDB.iconCache[name] = icon
end

-- Same client quirk CombatLedger/LootLedger already work around: `pfUI`,
-- `pfUI.api`, and even `pfUI.api.CreateBackdrop` as a real callable
-- function can all exist on this client even when pfUI genuinely is NOT
-- loaded - so checking the shape of the `pfUI` global is not reliable.
-- IsAddOnLoaded is the client's own source of truth.
function BL.HasPfui()
    local ok, loaded = pcall(IsAddOnLoaded, "pfUI")
    return ok and loaded and true or false
end

-- This addon never reads pfUI's LIVE config (font_default, font_size,
-- CreateBackdrop's colors, ...) for its own skin, even while pfUI is
-- loaded - only ever these bundled assets (MIT-licensed straight from
-- pfUI, see CombatLedger/README.md), so every knob below (Text Size,
-- the class-colored borders, ...) always actually has an effect. This
-- used to defer to pfUI's own live API when present (matching how
-- LootLedger/CleanRolls skin themselves) - deliberately different here:
-- pfUI's OWN border/font settings would otherwise silently override
-- this addon's Options window controls whenever pfUI happened to be
-- loaded, which defeats the entire point of that window. Looking like
-- pfUI is achieved by using pfUI's own asset files as fixed constants
-- instead, not by asking pfUI what it's currently configured to do.
BL.FLAT_SHADOW = {
    edgeFile = "Interface\\AddOns\\BuffLedger\\img\\glow2", edgeSize = 8,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
}

-- Near-black, matching pfUI's own default border color - same constant
-- CombatLedger's manual skin uses.
BL.FLAT_BORDER_R, BL.FLAT_BORDER_G, BL.FLAT_BORDER_B = 0.059, 0.059, 0.059

-- The client's own built-in font files, plus the bundled Expressway
-- (default) - no LibSharedMedia dependency, same reasoning as
-- CombatLedger's own CL.FONTS.
BL.FONTS = {
    { key = "expressway", label = "Expressway", path = "Interface\\AddOns\\BuffLedger\\fonts\\Expressway.ttf" },
    { key = "friz", label = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    { key = "arial", label = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
    { key = "skurri", label = "Skurri", path = "Fonts\\SKURRI.TTF" },
    { key = "morpheus", label = "Morpheus", path = "Fonts\\MORPHEUS.ttf" },
}

function BL.GetFontPath()
    local key = BL.GetSetting("fontKey") or "expressway"
    local i
    for i = 1, table.getn(BL.FONTS) do
        if BL.FONTS[i].key == key then return BL.FONTS[i].path end
    end
    return BL.FONTS[1].path
end

function BL.GetFontSize()
    return tonumber(BL.GetSetting("fontSizeOverride")) or 10
end

-- Debuff bar equivalents of the two above - separate functions rather
-- than parameterizing GetFontPath/GetFontSize, since every existing
-- buff-bar call site already calls those with no arguments and this
-- keeps that working untouched.
function BL.GetDebuffFontPath()
    local key = BL.GetSetting("debuffFontKey") or "expressway"
    local i
    for i = 1, table.getn(BL.FONTS) do
        if BL.FONTS[i].key == key then return BL.FONTS[i].path end
    end
    return BL.FONTS[1].path
end

function BL.GetDebuffFontSize()
    return tonumber(BL.GetSetting("debuffFontSizeOverride")) or 10
end

BL.FLAT_BACKDROP = {
    bgFile = "Interface\\BUTTONS\\WHITE8X8", tile = false, tileSize = 0,
    edgeFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 1,
    insets = { left = -1, right = -1, top = -1, bottom = -1 },
}

-- Skins one icon button's border/background with the flat pfUI-styled
-- backdrop - border color gets overridden per-category right after this
-- returns (class colors etc.), same as pfUI's own buff.lua does for
-- dispel-type coloring on debuffs.
--
-- The backdrop is NOT applied directly to btn (a Button) - it lives on
-- a separate child Frame instead, expanded outside btn's own bounds via
-- SetPoint offsets before SetBackdrop, exactly mirroring pfUI's own
-- CreateBackdrop (see pfUI/api/api.lua) rather than a simplified
-- from-scratch version. This turned out to matter: applying the
-- backdrop straight to btn produced no visible border at all, even on a
-- full relaunch with SetBackdrop called only once - a plain Frame child
-- (what pfUI itself uses for every one of its own buff icons) is what
-- actually renders correctly here, a Button widget apparently doesn't
-- on this client. Returns the child frame - callers call
-- SetBackdropBorderColor on whatever this returns, not on btn.
--
-- Both the child's expansion offset AND its own backdrop shape
-- (edgeSize/insets) scale together with the borderThickness setting,
-- rebuilt fresh every call rather than applied once - unlike the direct-
-- on-Button case, repeated SetBackdrop calls on a plain Frame render
-- fine here (confirmed - this used to guard against calling it more
-- than once, back when the direct-on-Button approach was still the
-- suspected culprit; the child-frame switch was the actual fix, so that
-- guard was never doing anything useful and would have blocked a live
-- thickness setting from ever taking effect).
-- `thicknessOverride` lets the debuff bar (its own independent
-- "Border Thickness" setting) share this same skinning function instead
-- of duplicating it - omit it (as every buff-bar call site already
-- does) to fall back to the buff bar's own "borderThickness" setting.
function BL.ApplyIconSkin(btn, thicknessOverride)
    if not btn.flatShadow then
        btn.flatShadow = CreateFrame("Frame", nil, btn)
        btn.flatShadow:SetFrameStrata(btn:GetFrameStrata())
        btn.flatShadow:SetFrameLevel(math.max(0, btn:GetFrameLevel() - 1))
        btn.flatShadow:SetPoint("TOPLEFT", btn, "TOPLEFT", -5, 5)
        btn.flatShadow:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 5, -5)
        btn.flatShadow:SetBackdrop(BL.FLAT_SHADOW)
        btn.flatShadow:SetBackdropBorderColor(0, 0, 0, 0.35)
    end
    btn.flatShadow:Show()

    if not btn.flatBackdrop then
        local level = btn:GetFrameLevel()
        local b = CreateFrame("Frame", nil, btn)
        b:SetFrameLevel(level > 0 and level - 1 or level)
        btn.flatBackdrop = b
    end

    local thickness = thicknessOverride or tonumber(BL.GetSetting("borderThickness")) or 1
    btn.flatBackdrop:ClearAllPoints()
    btn.flatBackdrop:SetPoint("TOPLEFT", btn, "TOPLEFT", -thickness, thickness)
    btn.flatBackdrop:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", thickness, -thickness)
    btn.flatBackdrop:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8", tile = false, tileSize = 0,
        edgeFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = thickness,
        insets = { left = -thickness, right = -thickness, top = -thickness, bottom = -thickness },
    })
    btn.flatBackdrop:SetBackdropColor(0, 0, 0, 0.9)
    btn.flatBackdrop:Show()
    return btn.flatBackdrop
end

-- Same epic-purple accent as the toc Title byline and CombatLedger/
-- LootLedger's own CL.ACCENT_HEX - was an arbitrary cyan before.
function BL.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffa335eeBuffLedger:|r " .. msg)
end

BL.CLASSICAPI_URL = "https://github.com/brues-code/ClassicAPI"

-- CLASSIC_API_VERSION is a global the ClassicAPI mod itself sets once
-- loaded - the exact signal pfUI's own startup check uses (see pfUI.lua,
-- same github.com/brues-code/ClassicAPI project) to detect it, more
-- direct than inferring presence from whether C_UnitAuras happens to
-- exist as a side effect.
function BL.HasClassicAPI()
    return CLASSIC_API_VERSION ~= nil
end

-- Modal popup (with a selectable/copyable link, same shape as pfUI's
-- own ClassicAPI-required dialog) plus a chat line, shown once per
-- session - called from Bar.lua's own top-of-file guard on
-- PLAYER_ENTERING_WORLD, so this is one of the first things a player
-- missing ClassicAPI actually sees, not a single line buried in login
-- spam that's easy to miss (which is what shipped before - see commit
-- history).
local shownPopup = false
function BL.ShowClassicAPIRequiredPopup()
    if shownPopup then return end
    shownPopup = true

    local detail
    if BL.HasClassicAPI() then
        -- CLASSIC_API_VERSION exists but C_UnitAuras.GetAuraDataByIndex
        -- still doesn't - shouldn't normally happen, but phrase it
        -- honestly rather than claiming it's flat-out not installed.
        detail = "ClassicAPI is loaded, but this client build still doesn't expose the aura API BuffLedger needs. You may need a newer ClassicAPI release:"
    else
        detail = "BuffLedger needs |cff33ffccClassicAPI|r to read your buffs, and it isn't installed on this client. Get the latest release from:"
    end

    StaticPopupDialogs["BUFFLEDGER_CLASSICAPI_REQUIRED"] = {
        text = "|cffa335eeBuffLedger|r can't run.\n\n" .. detail,
        button1 = OKAY,
        hasEditBox = 1,
        editBoxWidth = 280,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        OnShow = function()
            local editBox = getglobal(this:GetName() .. "EditBox")
            if editBox then
                editBox:SetText(BL.CLASSICAPI_URL)
                editBox:HighlightText()
                editBox:SetFocus()
            end
        end,
    }
    StaticPopup_Show("BUFFLEDGER_CLASSICAPI_REQUIRED")
    DEFAULT_CHAT_FRAME:AddMessage("|cffa335eeBuffLedger:|r " .. detail .. " " .. BL.CLASSICAPI_URL, 1, 0.3, 0.3)
end

-- C_UnitAuras.GetAuraDataByIndex allocates a fresh table every single
-- call - fine for a one-shot scan, but this addon also calls it from
-- Bar.lua's live refresh loop on every real buff-change event during
-- normal play (PLAYER_AURAS_CHANGED, BUFF_UPDATE_DURATION_SELF, ...),
-- not just from /bl scan, so the GC churn adds up over an actual
-- session. C_UnitAuras.UnitAura returns the same fields as plain
-- multiple values instead of a table, so this prefers it when present.
--
-- Not verified whether this client's C_UnitAuras backport actually
-- includes UnitAura (only GetAuraDataByIndex has been directly
-- confirmed working, via pfUI's own buff module) - guarded behind a
-- feature check rather than assumed, so this only ever activates where
-- the client genuinely supports it and otherwise costs nothing.
local hasUnitAura = C_UnitAuras and type(C_UnitAuras.UnitAura) == "function"

-- Returns name, icon, applications, expirationTime, spellId, dispelName
-- - the only fields anything in this addon reads off an aura (dispelName
-- is only used by the debuff bar's border coloring) - as plain values
-- either way, so callers never unpack a table regardless of which
-- underlying API answered.
function BL.GetAura(unit, index, filter)
    if hasUnitAura then
        local name, icon, applications, dispelName, _, expirationTime, _, _, _, spellId = C_UnitAuras.UnitAura(unit, index, filter)
        return name, icon, applications, expirationTime, spellId, dispelName
    end
    local aura = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
    if not aura then return nil end
    return aura.name, aura.icon, aura.applications, aura.expirationTime, aura.spellId, aura.dispelName
end

-- Lightweight click-menu (a plain frame + pooled row buttons) rather
-- than Blizzard's UIDropDownMenu, which is finicky to reuse outside its
-- own XML-driven templates on this client - same reasoning CombatLedger's
-- own CL.ShowDropdown carries. Only one can be open at a time.
local dropdownFrame
local dropdownCatcher

function BL.CloseDropdown()
    if dropdownFrame then dropdownFrame:Hide() end
    if dropdownCatcher then dropdownCatcher:Hide() end
end

-- `options` is an array of { label, onClick, color }. `color` is
-- optional ({r,g,b}, 0-1) - defaults to white when omitted. Opens above `anchor`
-- instead of below it when there isn't room below to fit on screen.
function BL.ShowDropdown(anchor, options)
    if not dropdownCatcher then
        dropdownCatcher = CreateFrame("Button", nil, UIParent)
        dropdownCatcher:SetAllPoints(UIParent)
        dropdownCatcher:SetFrameLevel(1)
        dropdownCatcher:EnableMouse(true)
        dropdownCatcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        dropdownCatcher:SetScript("OnClick", BL.CloseDropdown)
    end
    if not dropdownFrame then
        dropdownFrame = CreateFrame("Frame", nil, UIParent)
        dropdownFrame:SetFrameLevel(2)
        dropdownFrame:SetBackdrop(BL.FLAT_BACKDROP)
        dropdownFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.97)
        dropdownFrame:SetBackdropBorderColor(BL.FLAT_BORDER_R, BL.FLAT_BORDER_G, BL.FLAT_BORDER_B, 1)
        dropdownFrame.rows = {}
    end

    -- Only ever opened from the Options window (DIALOG strata) right
    -- now, so a fixed higher tier is enough to always win - no need for
    -- CombatLedger's relative-to-anchor strata math, which exists there
    -- to handle dropdowns opening from many different windows.
    dropdownCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
    dropdownFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    dropdownCatcher:Show()

    local ROW_H = 16
    local width = 150
    local count = table.getn(options)
    local height = count * ROW_H + 6
    dropdownFrame:SetWidth(width)
    dropdownFrame:SetHeight(height)
    dropdownFrame:ClearAllPoints()
    local anchorBottom = anchor:GetBottom() or 0
    if anchorBottom - height < 10 then
        dropdownFrame:SetPoint("BOTTOM", anchor, "TOP", 0, 2)
    else
        dropdownFrame:SetPoint("TOP", anchor, "BOTTOM", 0, -2)
    end

    local i
    for i = 1, count do
        local row = dropdownFrame.rows[i]
        if not row then
            row = CreateFrame("Button", nil, dropdownFrame)
            row:SetHeight(ROW_H)
            row:EnableMouse(true)
            row:RegisterForClicks("LeftButtonUp")
            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints(row)
            hl:SetTexture("Interface\\Buttons\\WHITE8X8")
            hl:SetVertexColor(1, 1, 1, 0.15)
            local text = row:CreateFontString(nil, "OVERLAY")
            text:SetPoint("LEFT", row, "LEFT", 4, 0)
            text:SetJustifyH("LEFT")
            row.text = text
            dropdownFrame.rows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", dropdownFrame, "TOPLEFT", 3, -3 - (i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", dropdownFrame, "TOPRIGHT", -3, -3 - (i - 1) * ROW_H)
        row.text:SetFont(BL.GetFontPath(), 11, "OUTLINE")
        row.text:SetText(options[i].label)
        local color = options[i].color
        if color then
            row.text:SetTextColor(color[1], color[2], color[3])
        else
            row.text:SetTextColor(1, 1, 1)
        end
        local onClick = options[i].onClick
        row:SetScript("OnClick", function()
            BL.CloseDropdown()
            if onClick then onClick() end
        end)
        row:Show()
    end
    local j
    for j = count + 1, table.getn(dropdownFrame.rows) do
        dropdownFrame.rows[j]:Hide()
    end

    dropdownFrame:Show()
end
