--[[
    BuffLedger - the debuff bar: a simpler sibling to Bar.lua's buff
    bar. Shows the player's HARMFUL auras, color-coded by dispel type
    (Magic/Curse/Poison/Disease - the same colors Blizzard's own
    tooltips use) instead of a class/category lookup, since there's no
    "which class gave you this" question to answer for a debuff. No
    clustering/categorizing - just a flowing grid, ordered by time
    remaining (shortest left, longest right - same reasoning as the
    buff bar's own within-cluster time sort, just applied across the
    whole bar here since there's no clustering to sort within), same
    footprint/skin/options shape as the buff bar (see UI_Options.lua's
    second tab) so the two feel like one addon, not two.

    Never touches any other addon's debuff display - only ever reads
    HARMFUL auras for its own icons, same as Bar.lua only ever reads
    HELPFUL ones. See Bar.lua's own HideOtherBuffFrames comment for why
    hiding a debuff-carrying frame is something this addon avoids
    entirely now.
]]

BuffLedger = BuffLedger or {}
local BL = BuffLedger

if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then
    -- Bar.lua's own guard already prints/pops the ClassicAPI-required
    -- message once per session (BL.ShowClassicAPIRequiredPopup no-ops
    -- on a second call) - just bail quietly here.
    return
end

BL.MAX_DEBUFFS = 16

local buttons = {}
local lastSignature

-- Neutral fallback border for a debuff with no real dispel type (most
-- physical/direct-damage debuffs) - matches the muted red Blizzard's
-- own tooltips use for "not dispellable this way".
local FALLBACK_COLOR = { 0.8, 0.2, 0.2 }

local function GetDispelColor(dispelName)
    if C_UnitAuras and C_UnitAuras.GetAuraDispelTypeColor then
        local ok, color = pcall(C_UnitAuras.GetAuraDispelTypeColor, dispelName)
        if ok and color and color.GetRGBA then
            local r, g, b = color:GetRGBA()
            return r, g, b
        end
    end
    return FALLBACK_COLOR[1], FALLBACK_COLOR[2], FALLBACK_COLOR[3]
end

local function CollectDebuffs()
    local entries = {}
    local i
    for i = 1, BL.MAX_DEBUFFS do
        local name, icon, applications, expirationTime, spellId, dispelName = BL.GetAura("player", i, "HARMFUL")
        if name then
            table.insert(entries, {
                index = i,
                name = name,
                icon = icon,
                spellId = spellId,
                expirationTime = expirationTime or 0,
                stackCount = applications or 0,
                dispelName = dispelName,
            })
        end
    end

    -- Ascending by time remaining - soonest-to-fall-off first, so
    -- LayoutDebuffs below can place the shortest-remaining debuff
    -- leftmost and the longest-remaining one rightmost. Name is the
    -- tie-break for a stable order between debuffs expiring at the
    -- same instant.
    table.sort(entries, function(a, b)
        if a.expirationTime ~= b.expirationTime then return a.expirationTime < b.expirationTime end
        return a.name < b.name
    end)

    return entries
end

local function BuildSignature(entries)
    local parts = {}
    local i
    for i = 1, table.getn(entries) do
        local e = entries[i]
        table.insert(parts, e.index .. ":" .. tostring(e.spellId or e.name) .. ":" .. e.stackCount .. ":" .. tostring(e.expirationTime))
    end
    return table.concat(parts, "|")
end

BL.debuffFrame = CreateFrame("Frame", "BuffLedgerDebuffFrame", UIParent)
BL.debuffFrame:SetFrameStrata("LOW")

local function CreateDebuffButton(i)
    local btn = CreateFrame("Button", "BuffLedgerDebuffButton" .. i, BL.debuffFrame)
    -- No RegisterForClicks/OnClick - debuffs aren't yours to cancel.

    btn.texture = btn:CreateTexture(nil, "BORDER")
    btn.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn.texture:SetAllPoints(btn)

    btn.count = btn:CreateFontString(nil, "OVERLAY")
    btn.count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    btn.count:SetJustifyH("RIGHT")

    btn.timer = btn:CreateFontString(nil, "OVERLAY")

    btn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetUnitAura("player", this.buffIndex, "HARMFUL")
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return btn
end

local function GetButton(i)
    if not buttons[i] then
        buttons[i] = CreateDebuffButton(i)
    end
    return buttons[i]
end

local function UpdateLockVisual()
    local locked = BL.GetSetting("debuffLocked")
    if locked then
        if BL.debuffFrame.dragBg then BL.debuffFrame.dragBg:Hide() end
        return
    end

    if not BL.debuffFrame.dragBg then
        BL.debuffFrame.dragBg = BL.debuffFrame:CreateTexture(nil, "BACKGROUND")
        BL.debuffFrame.dragBg:SetAllPoints(BL.debuffFrame)
        BL.debuffFrame.dragBg:SetTexture(0, 0, 0, 0.4)
    end
    BL.debuffFrame.dragBg:Show()
end
BL.UpdateDebuffLockVisual = UpdateLockVisual

local function UpdateBackground()
    if not BL.GetSetting("debuffShowBackground") then
        if BL.debuffFrame.flatBackdrop then BL.debuffFrame.flatBackdrop:Hide() end
        if BL.debuffFrame.flatShadow then BL.debuffFrame.flatShadow:Hide() end
        return
    end

    local thickness = tonumber(BL.GetSetting("debuffBorderThickness")) or 1
    local skinTarget = BL.ApplyIconSkin(BL.debuffFrame, thickness)
    skinTarget:SetBackdropBorderColor(BL.FLAT_BORDER_R, BL.FLAT_BORDER_G, BL.FLAT_BORDER_B, 1)
end
BL.UpdateDebuffBackground = UpdateBackground

-- No clusters, no category gap - just a flowing grid in the time-sorted
-- order CollectDebuffs returned, wrapping at the configured column
-- budget.
local function LayoutDebuffs(entries)
    local size = tonumber(BL.GetSetting("debuffIconSize")) or 30
    local spacing = tonumber(BL.GetSetting("debuffSpacing")) or 4
    local columns = math.max(1, tonumber(BL.GetSetting("debuffColumns")) or 10)
    local fontPath = BL.GetDebuffFontPath()
    local fontSize = BL.GetDebuffFontSize()
    local showDurationInside = BL.GetSetting("debuffShowDurationInside")
    local rowExtra = showDurationInside and 0 or (fontSize + 5)
    local rowWidth = columns * size
    local growLeft = BL.GetSetting("debuffGrowLeft") ~= false
    local thickness = tonumber(BL.GetSetting("debuffBorderThickness")) or 1

    local n = table.getn(entries)
    local x, row = 0, 0
    local slot = 0
    -- entries[] is sorted shortest-remaining-first (see CollectDebuffs).
    -- With growLeft, x=0 is the RIGHTMOST slot and each subsequent icon
    -- goes further left - placed in forward array order, the shortest
    -- entry would land rightmost and the longest leftmost, which is
    -- backwards from what was asked for. Walking the array backward
    -- here undoes exactly that inversion, matching LayoutButtons' own
    -- cluster-order fix in Bar.lua for the same underlying reason.
    local kStart, kEnd, kStep
    if growLeft then
        kStart, kEnd, kStep = n, 1, -1
    else
        kStart, kEnd, kStep = 1, n, 1
    end
    local k
    for k = kStart, kEnd, kStep do
        slot = slot + 1
        if x > 0 and x + size > rowWidth then
            x = 0
            row = row + 1
        end

        local entry = entries[k]
        local btn = GetButton(slot)
        btn.buffIndex = entry.index
        btn.spellId = entry.spellId
        btn.texture:SetTexture(entry.icon)
        btn.count:SetFont(fontPath, fontSize, "OUTLINE")
        btn.count:SetText(entry.stackCount > 1 and entry.stackCount or "")
        btn.timer:SetFont(fontPath, math.max(8, fontSize - 1), "OUTLINE")
        btn.timer:ClearAllPoints()
        if showDurationInside then
            btn.timer:SetPoint("CENTER", btn, "CENTER", 0, 0)
        else
            btn.timer:SetPoint("TOP", btn, "BOTTOM", 0, -3)
        end
        btn.expirationTime = entry.expirationTime

        local skinTarget = BL.ApplyIconSkin(btn, thickness)
        local r, g, b = GetDispelColor(entry.dispelName)
        skinTarget:SetBackdropBorderColor(r, g, b, 1)

        btn:SetWidth(size)
        btn:SetHeight(size)
        btn:ClearAllPoints()
        if growLeft then
            btn:SetPoint("TOPRIGHT", BL.debuffFrame, "TOPRIGHT", -x, -row * (size + spacing + rowExtra))
        else
            btn:SetPoint("TOPLEFT", BL.debuffFrame, "TOPLEFT", x, -row * (size + spacing + rowExtra))
        end
        btn:Show()

        x = x + size + spacing
    end

    local j
    for j = slot + 1, table.getn(buttons) do
        if buttons[j] then buttons[j]:Hide() end
    end

    local rows = row + 1
    BL.debuffFrame:SetWidth(math.max(size, rowWidth))
    BL.debuffFrame:SetHeight(rows * (size + spacing + rowExtra))

    UpdateBackground()
    UpdateLockVisual()
end
BL.LayoutDebuffs = LayoutDebuffs

local function RefreshDebuffBar(force)
    local entries = CollectDebuffs()
    local sig = BuildSignature(entries)
    if not force and sig == lastSignature then return end
    lastSignature = sig
    LayoutDebuffs(entries)
end

function BL.ForceDebuffRefresh()
    RefreshDebuffBar(true)
end

local function FormatTime(sec)
    if sec >= 3600 then return string.format("%dh", math.floor(sec / 3600) + 1) end
    if sec >= 60 then return string.format("%dm", math.floor(sec / 60) + 1) end
    return string.format("%d", math.floor(sec + 0.5))
end

local updateElapsed = 0
BL.debuffFrame:SetScript("OnUpdate", function()
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

BL.debuffFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
BL.debuffFrame:RegisterEvent("PLAYER_AURAS_CHANGED")
BL.debuffFrame:RegisterEvent("DEBUFF_UPDATE_DURATION_SELF")
BL.debuffFrame:SetScript("OnEvent", function()
    RefreshDebuffBar(event == "PLAYER_ENTERING_WORLD")
end)

BL.debuffFrame:SetMovable(true)
BL.debuffFrame:EnableMouse(true)
BL.debuffFrame:RegisterForDrag("LeftButton")
BL.debuffFrame:SetScript("OnDragStart", function()
    if not BL.GetSetting("debuffLocked") then this:StartMoving() end
end)
BL.debuffFrame:SetScript("OnDragStop", function()
    this:StopMovingOrSizing()
    BL.SaveDebuffLayout(this)
end)

local savedDebuff = BL.GetDebuffLayout()
if savedDebuff then
    BL.debuffFrame:SetPoint(savedDebuff.point, UIParent, savedDebuff.relPoint, savedDebuff.x, savedDebuff.y)
else
    BL.debuffFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -170, -260)
end
BL.debuffFrame:SetScale(tonumber(BL.GetSetting("debuffScale")) or 1)

RefreshDebuffBar(true)
