--[[
    BuffLedger - the actual buff bar: scans the player's HELPFUL auras
    plus weapon enchants, sorts/colors them by category (see Data.lua),
    and lays out icon buttons in a movable grid. Never reads debuffs
    itself (see DebuffBar.lua for that), but does hide Blizzard's own
    BuffFrame (and pfUI's buff/debuff frames, if pfUI is loaded) - see
    HideOtherBuffFrames below for why that's safe now even though
    BuffFrame renders the player's own debuffs too, on this client.
]]

BuffLedger = BuffLedger or {}
local BL = BuffLedger

if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then
    BL.Print("Requires ClassicAPI (github.com/brues-code/ClassicAPI) or an equivalent client-side mod exposing C_UnitAuras - this client doesn't have it, so BuffLedger can't function. Same requirement pfUI's own buff module has, if you're wondering why pfUI's buffs work but this doesn't.")

    -- The chat line above is easy to miss in login spam - this also
    -- pops a modal (BL.ShowClassicAPIRequiredPopup, Core.lua) once the
    -- world has finished loading, same PLAYER_ENTERING_WORLD-gated
    -- pattern pfUI's own ClassicAPI-required popup uses, so it's one of
    -- the first things visible instead of a buried print.
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function()
        f:UnregisterEvent("PLAYER_ENTERING_WORLD")
        BL.ShowClassicAPIRequiredPopup()
    end)
    return
end

BL.MAX_BUFFS = 40

local buttons = {}
local lastSignature

-- [ Collecting + sorting ] --------------------------------------------

local function GetVisibleGroups()
    return {
        CLASS = BL.GetSetting("showClass") ~= false,
        WEAPON = BL.GetSetting("showWeapon") ~= false,
        CONSUMABLE = BL.GetSetting("showConsumable") ~= false,
        WORLD = BL.GetSetting("showWorld") ~= false,
        RACIAL = BL.GetSetting("showRacial") ~= false,
        OTHER = BL.GetSetting("showOther") ~= false,
    }
end

local function BuildSortKey(entry)
    local classPriority = 0
    if entry.group == "CLASS" then
        classPriority = BL.CLASS_PRIORITY[entry.class] or 50
    end
    return ((BL.GROUP_PRIORITY[entry.group] or 99) * 1000) + classPriority
end

-- Weapon enchants (sharpening stones, wizard/mana oils, ...) never show
-- up in the HELPFUL aura list at all - the client tracks them entirely
-- separately via GetWeaponEnchantInfo(), same as pfUI's own buff module
-- (see its wepbuffs handling). These synthetic entries carry the same
-- fields CollectEntries builds for a real aura (expirationTime as an
-- absolute GetTime()-based timestamp, not the raw milliseconds-remaining
-- the API returns) so LayoutButtons/BuildSignature don't need to know
-- the difference - isWeapon/weaponSlot are the only extra fields, used
-- by CreateIconButton's tooltip/click handlers below.
local function CollectWeaponEntries(visible)
    local out = {}
    if not visible.WEAPON or not GetWeaponEnchantInfo then return out end

    local now = GetTime()
    local hasMH, mhExpire, mhCharges, hasOH, ohExpire, ohCharges = GetWeaponEnchantInfo()

    if hasMH then
        table.insert(out, {
            index = "MH",
            name = "Mainhand Enchant",
            icon = GetInventoryItemTexture("player", 16),
            spellId = nil,
            expirationTime = now + (mhExpire or 0) / 1000,
            stackCount = mhCharges or 0,
            group = "WEAPON",
            isWeapon = true,
            weaponSlot = 16,
        })
    end

    if hasOH then
        table.insert(out, {
            index = "OH",
            name = "Offhand Enchant",
            icon = GetInventoryItemTexture("player", 17),
            spellId = nil,
            expirationTime = now + (ohExpire or 0) / 1000,
            stackCount = ohCharges or 0,
            group = "WEAPON",
            isWeapon = true,
            weaponSlot = 17,
        })
    end

    return out
end

-- Fixed 1..MAX_BUFFS scan (not "stop at first nil") - same iteration
-- shape as pfUI's own RefreshButton loop, since indices past the real
-- aura count are expected to just return nil, not signal end-of-list.
local function CollectEntries()
    local visible = GetVisibleGroups()
    local entries = {}
    local i
    for i = 1, BL.MAX_BUFFS do
        local name, icon, applications, expirationTime, spellId = BL.GetAura("player", i, "HELPFUL")
        if name then
            BL.RecordIcon(name, icon)
            local group, class = BL.Categorize(name)
            if visible[group] then
                local entry = {
                    index = i,
                    name = name,
                    icon = icon,
                    spellId = spellId,
                    expirationTime = expirationTime or 0,
                    stackCount = applications or 0,
                    group = group,
                    class = class,
                }
                entry.sortKey = BuildSortKey(entry)
                table.insert(entries, entry)
            end
        end
    end

    local weaponEntries = CollectWeaponEntries(visible)
    for i = 1, table.getn(weaponEntries) do
        local entry = weaponEntries[i]
        entry.sortKey = BuildSortKey(entry)
        table.insert(entries, entry)
    end

    -- Within the same group/class (equal sortKey - the same scope
    -- BuildClusters later groups into one visual cluster), soonest-to-
    -- expire sorts first, so the buff most worth reacting to is the
    -- most visually prominent one instead of buried mid-cluster by
    -- alphabetical accident. Name is still the final tie-break, for a
    -- stable order between entries that happen to expire at the exact
    -- same instant.
    table.sort(entries, function(a, b)
        if a.sortKey ~= b.sortKey then return a.sortKey < b.sortKey end
        if a.expirationTime ~= b.expirationTime then return a.expirationTime < b.expirationTime end
        return a.name < b.name
    end)
    return entries
end

-- expirationTime has to be part of this signature, not just
-- index/spellId/stackCount - refreshing a buff (recasting the same one
-- on you before it falls off) changes none of those, only how much time
-- is left on it. Leaving it out meant RefreshBar's "nothing changed,
-- skip the layout pass" early-return also skipped writing the button's
-- new expirationTime, so its timer kept counting down from the STALE
-- value from before the refresh - the "buffs randomly have incorrect
-- times" bug.
local function BuildSignature(entries)
    local parts = {}
    local i
    for i = 1, table.getn(entries) do
        local e = entries[i]
        table.insert(parts, e.index .. ":" .. tostring(e.spellId or e.name) .. ":" .. e.stackCount .. ":" .. tostring(e.expirationTime))
    end
    return table.concat(parts, "|")
end

-- Declared here (not down by OnUpdate where it's also used) because
-- CreateIconButton's tooltip below needs it too, and a local function
-- can only be seen by closures defined AFTER its own declaration.
local function FormatTime(sec)
    if sec >= 3600 then return string.format("%dh", math.floor(sec / 3600) + 1) end
    if sec >= 60 then return string.format("%dm", math.floor(sec / 60) + 1) end
    return string.format("%d", math.floor(sec + 0.5))
end

-- [ Frame + buttons ] ---------------------------------------------------

BL.frame = CreateFrame("Frame", "BuffLedgerFrame", UIParent)
BL.frame:SetFrameStrata("LOW")

local function CreateIconButton(i)
    local btn = CreateFrame("Button", "BuffLedgerButton" .. i, BL.frame)
    btn:RegisterForClicks("RightButtonUp")

    btn.texture = btn:CreateTexture(nil, "BORDER")
    btn.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn.texture:SetAllPoints(btn)

    btn.count = btn:CreateFontString(nil, "OVERLAY")
    btn.count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    btn.count:SetJustifyH("RIGHT")

    -- Anchored fresh every LayoutButtons pass (below the icon, or
    -- overlaid on it - see the showDurationInside setting), not here.
    btn.timer = btn:CreateFontString(nil, "OVERLAY")

    btn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_BOTTOMRIGHT")
        if this.consolidatedMembers then
            -- A consolidated icon stands in for several real auras at
            -- once - no single buffIndex/spellId to ask the tooltip API
            -- about, so the list is built by hand from what LayoutButtons
            -- recorded for this cluster.
            GameTooltip:SetText(this.consolidatedTitle or "Buffs")
            local now = GetTime()
            local i
            for i = 1, table.getn(this.consolidatedMembers) do
                local m = this.consolidatedMembers[i]
                local remain = m.expirationTime - now
                local timeStr = (m.expirationTime > 0 and remain > 0) and FormatTime(remain) or ""
                GameTooltip:AddLine(m.name .. (timeStr ~= "" and ("  |cff999999" .. timeStr .. "|r") or ""), 1, 1, 1)
            end
        elseif this.isTest then
            -- Synthetic /bl test data has no real aura/item behind it to
            -- ask the tooltip API about - just show what it's standing
            -- in for.
            GameTooltip:SetText(this.buffName or "?")
            GameTooltip:AddLine(this.groupLabel or "", 0.8, 0.8, 0.8)
        elseif this.isWeapon then
            GameTooltip:SetInventoryItem("player", this.weaponSlot)
        else
            GameTooltip:SetUnitAura("player", this.buffIndex, "HELPFUL")
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", function()
        -- Weapon enchants aren't spells you can cancel this way - nothing
        -- to do here for those (this.spellId is always nil on them).
        if this.spellId and C_Spell and C_Spell.CancelSpellByID then
            C_Spell.CancelSpellByID(this.spellId)
        end
    end)

    return btn
end

local function GetButton(i)
    if not buttons[i] then
        buttons[i] = CreateIconButton(i)
    end
    return buttons[i]
end

local function GetCategoryColor(entry)
    if entry.group == "CLASS" then
        local c = BL.CLASS_COLOR[entry.class]
        if c then return c.r, c.g, c.b end
        return 1, 1, 1
    end
    local c = BL.GROUP_COLOR[entry.group]
    if c then return c[1], c[2], c[3] end
    return 0.65, 0.65, 0.65
end

-- Shows (while unlocked) a faint background so an empty bar is still
-- visible/grabbable to reposition - hidden while locked, since there's
-- nothing to grab or see the point of at that point.
local function UpdateLockVisual()
    local locked = BL.GetSetting("locked")
    if locked then
        if BL.frame.dragBg then BL.frame.dragBg:Hide() end
        return
    end

    if not BL.frame.dragBg then
        BL.frame.dragBg = BL.frame:CreateTexture(nil, "BACKGROUND")
        BL.frame.dragBg:SetAllPoints(BL.frame)
        BL.frame.dragBg:SetTexture(0, 0, 0, 0.4)
    end
    BL.frame.dragBg:Show()
end
BL.UpdateLockVisual = UpdateLockVisual

-- Optional bordered panel behind the whole bar, sized to fit whatever
-- LayoutButtons just computed - reuses the same flat pfUI-styled skin as
-- individual icons (BL.ApplyIconSkin works on any frame, not just
-- icon-sized ones), just with a neutral border instead of a category
-- color override.
local function UpdateBackground()
    if not BL.GetSetting("showBackground") then
        -- ApplyIconSkin's actual backdrop lives on a child frame
        -- (flatBackdrop), not on BL.frame itself - this used to hide
        -- old field names (backdrop/backdrop_shadow) left over from
        -- before that child-frame restructure, plus SetBackdrop(nil)
        -- on BL.frame which was never what carried the visible skin in
        -- the first place, so toggling this off never actually hid
        -- anything.
        if BL.frame.flatBackdrop then BL.frame.flatBackdrop:Hide() end
        if BL.frame.flatShadow then BL.frame.flatShadow:Hide() end
        return
    end

    local skinTarget = BL.ApplyIconSkin(BL.frame)
    skinTarget:SetBackdropBorderColor(BL.FLAT_BORDER_R, BL.FLAT_BORDER_G, BL.FLAT_BORDER_B, 1)
end
BL.UpdateBackground = UpdateBackground

-- Same key for every entry in one visual cluster - each class is its
-- own cluster (not just "CLASS" as a whole), since class is the primary
-- thing this addon sorts by.
local function CategoryKey(entry)
    if entry.group == "CLASS" then return "CLASS:" .. tostring(entry.class) end
    return entry.group
end

-- entries is already sorted so every member of one cluster (same
-- CategoryKey) is contiguous - this just finds those runs so the layout
-- pass below can size a whole cluster before deciding whether it fits
-- on the current row.
local function BuildClusters(entries)
    local clusters = {}
    local n = table.getn(entries)
    local i = 1
    while i <= n do
        local key = CategoryKey(entries[i])
        local j = i
        while j <= n and CategoryKey(entries[j]) == key do
            j = j + 1
        end
        table.insert(clusters, { first = i, last = j - 1 })
        i = j
    end
    return clusters
end

-- Flowing layout (not a fixed grid), packed cluster-by-cluster instead
-- of icon-by-icon - a whole category moves to the next row together
-- rather than splitting mid-cluster the moment a row runs out of width,
-- which is what a naive per-icon wrap check does. Only exception: a
-- single cluster wider than the entire row budget, which has no choice
-- but to wrap internally (the per-icon safety check inside the inner
-- loop below).
local function LayoutButtons(entries)
    local size = tonumber(BL.GetSetting("iconSize")) or 30
    local spacing = tonumber(BL.GetSetting("spacing")) or 4
    local categoryGap = tonumber(BL.GetSetting("categoryGap")) or 12
    local columns = math.max(1, tonumber(BL.GetSetting("columns")) or 10)
    local fontPath = BL.GetFontPath()
    local fontSize = BL.GetFontSize()
    local showDurationInside = BL.GetSetting("showDurationInside")
    -- Mirrors pfUI's own "Show Duration Inside Buff" option (C.buffs.
    -- textinside) - overlaying the timer on the icon instead of below
    -- it means rows don't need the extra vertical room for that text.
    local rowExtra = showDurationInside and 0 or (fontSize + 5)
    -- Deliberately NOT columns * (size + spacing) - that would make the
    -- bar's own footprint (and therefore its anchored/pinned edge)
    -- shift every time Icon Spacing changes, which is exactly what
    -- "adjusting spacing shouldn't move the frame" was about. Basing
    -- the width budget on icon size alone keeps the footprint tied only
    -- to Icon Size and Columns - a larger Icon Spacing just means
    -- slightly fewer icons practically fit before wrapping to the next
    -- row, not a wider (or narrower) bar.
    local rowWidth = columns * size
    -- Default matches pfUI's own buff frame, which anchors TOPRIGHT and
    -- grows leftward - `x` below is still a plain 0-based width budget
    -- either way, only the final anchor/sign flips.
    local growLeft = BL.GetSetting("growLeft") ~= false

    local clusters = BuildClusters(entries)
    local x, row = 0, 0
    local slot = 0
    local firstOnRow = true
    local consolidate = BL.GetSetting("consolidate")
    local c
    -- x already carries a trailing `spacing` from the last icon placed
    -- (every icon advances x by size+spacing, cluster boundary or not -
    -- see the inner loop below) - categoryGap is meant to be the TOTAL
    -- gap between clusters, comparable to how `spacing` is the total gap
    -- within one, not an extra amount stacked on top of that spacing.
    -- Only the difference gets added here so the two settings are
    -- actually apples-to-apples (equal values ~ equal-looking gaps),
    -- clamped so a Category Gap smaller than Icon Spacing never
    -- produces a negative (overlapping) advance.
    local extraGap = math.max(0, categoryGap - spacing)
    for c = 1, table.getn(clusters) do
        local cluster = clusters[c]
        local count = cluster.last - cluster.first + 1
        -- Only worth consolidating a cluster that's actually more than
        -- one icon - a lone buff already IS its own single icon, so
        -- there's nothing to collapse and no badge should appear on it.
        local doConsolidate = consolidate and count > 1

        -- Build the list of icons this cluster renders as, in final
        -- left-to-right visual order, before worrying about placement -
        -- either every real entry (one icon each) or a single synthetic
        -- item standing in for the whole cluster.
        local items = {}
        if doConsolidate then
            -- entries[] is sorted ascending by time within a cluster
            -- (see CollectEntries), so cluster.first is already the
            -- soonest-to-expire member - the representative icon/timer,
            -- same "most urgent = most visually prominent" reasoning as
            -- everywhere else in this file. spellId/buffIndex are left
            -- nil - there's no single spell a merged icon could cancel.
            local rep = entries[cluster.first]
            local members = {}
            local m
            for m = cluster.first, cluster.last do
                table.insert(members, { name = entries[m].name, expirationTime = entries[m].expirationTime })
            end
            -- "Paladin" (from the class) or "World"/"Consumable"/... (from
            -- the group) reads as a tooltip title far better than the raw
            -- "CLASS - PALADIN" groupLabel string used for the small gray
            -- isTest subtitle elsewhere.
            local titleRaw = rep.class or rep.group or "Buffs"
            local title = string.upper(string.sub(titleRaw, 1, 1)) .. string.lower(string.sub(titleRaw, 2))
            table.insert(items, {
                icon = rep.icon,
                expirationTime = rep.expirationTime,
                countText = count,
                group = rep.group,
                class = rep.class,
                isTest = rep.isTest,
                consolidatedMembers = members,
                consolidatedTitle = title,
            })
        else
            -- Placement order within the cluster - forward (soonest-
            -- expiring entry first) normally, since x=0 is the LEFTMOST
            -- slot and grows rightward, so array-first already lands
            -- leftmost. But when growLeft is on, x=0 is the RIGHTMOST
            -- slot and each subsequent icon goes further left - placed
            -- forward, the soonest entry would land rightmost and the
            -- longest-remaining one leftmost, which reads as DESCENDING
            -- time left-to-right (the bug: 10m appearing before 17m/
            -- 17s). Walking the cluster backward here undoes exactly
            -- that inversion, so reading left-to-right is ascending
            -- (soonest first) in both growth directions.
            local kStart, kEnd, kStep
            if growLeft then
                kStart, kEnd, kStep = cluster.last, cluster.first, -1
            else
                kStart, kEnd, kStep = cluster.first, cluster.last, 1
            end
            local k
            for k = kStart, kEnd, kStep do
                local entry = entries[k]
                table.insert(items, {
                    icon = entry.icon,
                    expirationTime = entry.expirationTime,
                    countText = entry.stackCount > 1 and entry.stackCount or "",
                    group = entry.group,
                    class = entry.class,
                    isTest = entry.isTest,
                    buffIndex = entry.index,
                    buffName = entry.name,
                    spellId = entry.spellId,
                    isWeapon = entry.isWeapon,
                    weaponSlot = entry.weaponSlot,
                })
            end
        end

        local clusterWidth = doConsolidate and size or (count * size + (count - 1) * spacing)

        if not firstOnRow then
            if x + extraGap + clusterWidth > rowWidth then
                x = 0
                row = row + 1
                firstOnRow = true
            else
                x = x + extraGap
            end
        end

        local ii
        for ii = 1, table.getn(items) do
            local item = items[ii]
            -- Only triggers when a single cluster is wider than rowWidth
            -- all by itself - the cluster-level check above already
            -- guaranteed it starts a fresh row when it needs one.
            if x > 0 and x + size > rowWidth then
                x = 0
                row = row + 1
            end

            slot = slot + 1
            local btn = GetButton(slot)
            btn.buffIndex = item.buffIndex
            btn.buffName = item.buffName
            btn.groupLabel = item.class and (item.group .. " - " .. item.class) or item.group
            btn.spellId = item.spellId
            btn.isWeapon = item.isWeapon
            btn.weaponSlot = item.weaponSlot
            btn.isTest = item.isTest
            btn.consolidatedMembers = item.consolidatedMembers
            btn.consolidatedTitle = item.consolidatedTitle
            btn.texture:SetTexture(item.icon)
            btn.count:SetFont(fontPath, fontSize, "OUTLINE")
            btn.count:SetText(item.countText)
            btn.timer:SetFont(fontPath, math.max(8, fontSize - 1), "OUTLINE")
            btn.timer:ClearAllPoints()
            if showDurationInside then
                btn.timer:SetPoint("CENTER", btn, "CENTER", 0, 0)
            else
                btn.timer:SetPoint("TOP", btn, "BOTTOM", 0, -3)
            end
            btn.expirationTime = item.expirationTime

            local skinTarget = BL.ApplyIconSkin(btn)
            local r, g, b = GetCategoryColor(item)
            skinTarget:SetBackdropBorderColor(r, g, b, 1)

            btn:SetWidth(size)
            btn:SetHeight(size)
            btn:ClearAllPoints()
            if growLeft then
                btn:SetPoint("TOPRIGHT", BL.frame, "TOPRIGHT", -x, -row * (size + spacing + rowExtra))
            else
                btn:SetPoint("TOPLEFT", BL.frame, "TOPLEFT", x, -row * (size + spacing + rowExtra))
            end
            btn:Show()

            x = x + size + spacing
        end

        firstOnRow = false
    end

    local j
    for j = slot + 1, table.getn(buttons) do
        if buttons[j] then buttons[j]:Hide() end
    end

    local rows = row + 1
    BL.frame:SetWidth(math.max(size, rowWidth))
    BL.frame:SetHeight(rows * (size + spacing + rowExtra))

    UpdateBackground()
    UpdateLockVisual()
end
BL.LayoutButtons = LayoutButtons

-- [ Refresh ] ------------------------------------------------------------

-- While /bl test is active, every normal refresh (event-driven or
-- forced by a settings change like /bl gap) re-renders the frozen
-- synthetic set instead of doing a live aura scan, so real game events
-- can't stomp the test display and settings changes still preview
-- against it immediately. See Test.lua.
local function RefreshBar(force)
    if BL.testMode and BL.testEntries then
        LayoutButtons(BL.testEntries)
        return
    end

    local entries = CollectEntries()
    local sig = BuildSignature(entries)
    if not force and sig == lastSignature then return end
    lastSignature = sig
    LayoutButtons(entries)
end

function BL.ForceRefresh()
    RefreshBar(true)
end

local updateElapsed = 0
BL.frame:SetScript("OnUpdate", function()
    updateElapsed = updateElapsed + arg1
    if updateElapsed < 0.2 then return end
    updateElapsed = 0

    local now = GetTime()
    local i
    for i = 1, table.getn(buttons) do
        local btn = buttons[i]
        if btn and btn:IsShown() then
            local remain = (btn.expirationTime or 0) - now
            if btn.expirationTime and btn.expirationTime > 0 and remain > 0 then
                btn.timer:SetText(FormatTime(remain))
            else
                btn.timer:SetText("")
            end
        end
    end
end)

BL.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
BL.frame:RegisterEvent("PLAYER_AURAS_CHANGED")
BL.frame:RegisterEvent("BUFF_UPDATE_DURATION_SELF")
-- Applying/losing a weapon enchant doesn't fire PLAYER_AURAS_CHANGED at
-- all (it's not an aura) - these two are what pfUI's own buff module
-- registers to catch that instead.
BL.frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
BL.frame:RegisterEvent("UNIT_MODEL_CHANGED")
BL.frame:SetScript("OnEvent", function()
    -- PLAYER_ENTERING_WORLD is forced, not gated like the others - this
    -- client restores SavedVariables AFTER this file's own top-level
    -- code already ran (see Core.lua's own comment on the same quirk),
    -- so the very first RefreshBar(true) call below happens against
    -- still-default settings. If your buffs happen to be identical
    -- before and after a /reload (the common case), a plain gated
    -- RefreshBar(false) here would compute the same signature as that
    -- stale initial pass and skip LayoutButtons entirely, leaving
    -- "locked" and every other setting stuck showing pre-restore
    -- defaults until your buffs actually change. Forcing here re-lays-
    -- out once real settings are in effect regardless.
    RefreshBar(event == "PLAYER_ENTERING_WORLD")
end)

-- [ Movable ] --------------------------------------------------------------

BL.frame:SetMovable(true)
BL.frame:EnableMouse(true)
BL.frame:RegisterForDrag("LeftButton")
BL.frame:SetScript("OnDragStart", function()
    if not BL.GetSetting("locked") then this:StartMoving() end
end)
BL.frame:SetScript("OnDragStop", function()
    this:StopMovingOrSizing()
    BL.SaveLayout(this)
end)

local saved = BL.GetLayout()
if saved then
    BL.frame:SetPoint(saved.point, UIParent, saved.relPoint, saved.x, saved.y)
else
    BL.frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -170, -180)
end
BL.frame:SetScale(tonumber(BL.GetSetting("scale")) or 1)

-- [ Hide Blizzard's / pfUI's own buff frame ] -------------------------------

-- Blizzard's stock BuffFrame used to be left alone entirely: on this
-- client the player's own debuffs render through that same BuffFrame
-- rather than a separate frame, and back when BuffLedger only had a
-- buff bar, hiding it (UnregisterAllEvents especially - that stops it
-- from ever refreshing again even if shown) meant taking real debuffs
-- down with it. That's no longer true - DebuffBar.lua now reads the
-- player's debuffs directly from the aura API, completely independent
-- of whatever Blizzard's own BuffFrame is doing, so hiding BuffFrame
-- can no longer hide any debuff BuffLedger itself would show. Leaving
-- it up just meant Blizzard's stock icons duplicating this addon's own
-- bars - hiding it unconditionally (pfUI installed or not) is what
-- "this replaces the stock frame" was supposed to mean all along.
local function HideOtherBuffFrames()
    local done = true

    if BuffFrame then
        BuffFrame:Hide()
        BuffFrame:UnregisterAllEvents()
    end

    if TemporaryEnchantFrame then
        TemporaryEnchantFrame:Hide()
        TemporaryEnchantFrame:UnregisterAllEvents()
    end

    if BL.HasPfui() then
        if pfUI.buff and pfUI.buff.buffs then
            pfUI.buff.buffs:Hide()
        else
            done = false -- pfUI hasn't built its own buff frame yet - retry later
        end
        if pfUI.buff and pfUI.buff.wepbuffs then
            pfUI.buff.wepbuffs:Hide()
        end
        -- Unlike Blizzard's BuffFrame, pfUI.buff.debuffs is a real
        -- dedicated debuff frame, not shared with anything else - safe
        -- to hide unconditionally now that DebuffBar.lua covers the
        -- same job. This file only reaches here at all when ClassicAPI
        -- is present, so DebuffBar.lua already loaded successfully too.
        if pfUI.buff and pfUI.buff.debuffs then
            pfUI.buff.debuffs:Hide()
        end
    end

    return done
end

-- Same delayed-retry shape as CombatLedger's UI_PfuiDock.lua - pfUI.buff
-- may not exist yet the instant this file executes, even once
-- IsAddOnLoaded("pfUI") is already true.
local hidden = false
local delayFrame = CreateFrame("Frame")
local elapsed = 0
delayFrame:SetScript("OnUpdate", function()
    elapsed = elapsed + arg1
    if elapsed > 2 then
        delayFrame:SetScript("OnUpdate", nil)
        hidden = HideOtherBuffFrames()
    end
end)

local hideEventFrame = CreateFrame("Frame")
hideEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
hideEventFrame:SetScript("OnEvent", function()
    hidden = HideOtherBuffFrames()
end)

-- [ Slash command ] ---------------------------------------------------------

SLASH_BUFFLEDGER1 = "/bl"
SLASH_BUFFLEDGER2 = "/buffledger"
SlashCmdList["BUFFLEDGER"] = function(msg)
    msg = string.lower(msg or "")

    if msg == "scan" then
        BL.ScanRaidBuffs()
    elseif msg == "auras" then
        BL.ScanPlayerAuras()
    elseif msg == "options" or msg == "opt" or msg == "config" then
        BL.ToggleOptions()
    elseif msg == "test" then
        BL.StartTest()
    elseif msg == "test off" then
        BL.StopTest()
    elseif string.find(msg, "^test ") then
        -- accepts either a 0-1 fraction ("/bl test 0.5") or a percent
        -- ("/bl test 50") - anything over 1 is treated as a percent.
        local frac = tonumber(string.sub(msg, 6))
        if frac then
            BL.StartTest(frac > 1 and frac / 100 or frac)
        end
    elseif msg == "lock" then
        BL.SetSetting("locked", true)
        UpdateLockVisual()
        BL.Print("Locked.")
    elseif msg == "unlock" then
        BL.SetSetting("locked", false)
        UpdateLockVisual()
        BL.Print("Unlocked - drag to move.")
    elseif msg == "reset" then
        BL.ResetLayout()
        BL.frame:ClearAllPoints()
        BL.frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -170, -180)
        BL.Print("Position reset.")
    elseif string.find(msg, "^scale ") then
        local n = tonumber(string.sub(msg, 7))
        if n and n > 0 then
            BL.SetSetting("scale", n)
            BL.frame:SetScale(n)
            BL.Print("Scale set to " .. n)
        end
    elseif string.find(msg, "^columns ") then
        local n = tonumber(string.sub(msg, 9))
        if n and n >= 1 then
            BL.SetSetting("columns", math.floor(n))
            BL.ForceRefresh()
            BL.Print("Columns set to " .. math.floor(n))
        end
    elseif string.find(msg, "^gap ") then
        local n = tonumber(string.sub(msg, 5))
        if n and n >= 0 then
            BL.SetSetting("categoryGap", n)
            BL.ForceRefresh()
            BL.Print("Category gap set to " .. n)
        end
    elseif string.find(msg, "^size ") then
        local n = tonumber(string.sub(msg, 6))
        if n and n >= 10 then
            BL.SetSetting("iconSize", n)
            BL.ForceRefresh()
            BL.Print("Icon size set to " .. n)
        end
    elseif string.find(msg, "^toggle ") then
        local group = string.upper(string.sub(msg, 8))
        local map = { CLASS = "showClass", WEAPON = "showWeapon", CONSUMABLE = "showConsumable", WORLD = "showWorld", RACIAL = "showRacial", OTHER = "showOther" }
        local key = map[group]
        if key then
            local newVal = not (BL.GetSetting(key) ~= false)
            BL.SetSetting(key, newVal)
            BL.ForceRefresh()
            BL.Print(group .. " group " .. (newVal and "shown" or "hidden") .. ".")
        else
            BL.Print("Unknown group. Use: class, weapon, consumable, world, racial, other")
        end
    else
        BL.Print("Commands: options, scan, test [0-1|% |off], lock, unlock, reset, scale <n>, columns <n>, size <n>, gap <n>, toggle <class|weapon|consumable|world|racial|other>")
    end
end

RefreshBar(true)
