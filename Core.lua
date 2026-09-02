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
    showClass = true,
    showWeapon = true,
    showConsumable = true,
    showWorld = true,
    showRacial = true,
    showOther = true,
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
function BL.ApplyIconSkin(btn)
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

    local thickness = tonumber(BL.GetSetting("borderThickness")) or 1
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

-- `options` is an array of { label, onClick }. Opens above `anchor`
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
        row.text:SetTextColor(1, 1, 1)
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
