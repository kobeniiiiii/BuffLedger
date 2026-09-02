--[[
    BuffLedger - /bl options: a real settings window instead of only
    slash commands. Everything here just calls the same BL.GetSetting/
    BL.SetSetting + BL.ForceRefresh pair the slash commands already use
    (see Bar.lua) - this is a second way to reach the same settings, not
    a separate code path.

    Visual/widget vocabulary is deliberately ported from CombatLedger's
    own UI_Options.lua (row label-left/control-right, gold section
    headers + thin dividers, +/- stepper controls instead of sliders,
    CreateSmallButton-style flat buttons) so this looks like part of the
    same addon family, not a one-off design. Labels/values still use
    BL.GetFontPath() (not GameFontHighlightSmall like CombatLedger's
    own rows) - BuffLedger's whole point is a fully addon-controlled
    font, so borrowing a stock font template here would undercut that.
]]

BuffLedger = BuffLedger or {}
local BL = BuffLedger

local WINDOW_WIDTH = 300
local ROW_HEIGHT = 24

local frame
local refreshers = {} -- functions that resync one control's displayed value from current settings

local function Refresh()
    local i
    for i = 1, table.getn(refreshers) do
        refreshers[i]()
    end
end

--------------------------------------------------------------------------
-- Small reusable controls (CombatLedger's CreateSmallButton/CreateStepper)
--------------------------------------------------------------------------

local function CreateSmallButton(parent, width, text)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetWidth(width)
    btn:SetHeight(18)
    btn:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8", tile = false, tileSize = 0,
        edgeFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 1,
        insets = { left = -1, right = -1, top = -1, bottom = -1 },
    })
    btn:SetBackdropColor(0.15, 0.15, 0.15, 0.75)
    btn:SetBackdropBorderColor(BL.FLAT_BORDER_R, BL.FLAT_BORDER_G, BL.FLAT_BORDER_B, 1)
    local label = btn:CreateFontString(nil, "OVERLAY")
    label:SetAllPoints(btn)
    label:SetJustifyH("CENTER")
    label:SetFont(BL.GetFontPath(), 11, "OUTLINE")
    label:SetText(text or "")
    btn.label = label
    table.insert(refreshers, function() label:SetFont(BL.GetFontPath(), 11, "OUTLINE") end)
    return btn
end

local function CreateStepper(parent, width)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetWidth(width)
    holder:SetHeight(18)

    local minus = CreateSmallButton(holder, 16, "-")
    minus:SetPoint("LEFT", holder, "LEFT", 0, 0)

    local plus = CreateSmallButton(holder, 16, "+")
    plus:SetPoint("RIGHT", holder, "RIGHT", 0, 0)

    local value = holder:CreateFontString(nil, "OVERLAY")
    value:SetPoint("LEFT", minus, "RIGHT", 2, 0)
    value:SetPoint("RIGHT", plus, "LEFT", -2, 0)
    value:SetJustifyH("CENTER")
    value:SetFont(BL.GetFontPath(), 11, "OUTLINE")
    table.insert(refreshers, function() value:SetFont(BL.GetFontPath(), 11, "OUTLINE") end)

    holder.minus = minus
    holder.plus = plus
    holder.value = value
    return holder
end

--------------------------------------------------------------------------
-- Row helpers
--------------------------------------------------------------------------

local function AddCheckboxRow(parent, label, key, y)
    local labelFs = parent:CreateFontString(nil, "OVERLAY")
    labelFs:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, -y)
    labelFs:SetFont(BL.GetFontPath(), 11, "OUTLINE")
    labelFs:SetText(label)

    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetWidth(20)
    cb:SetHeight(20)
    cb:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, -y + 3)
    cb:SetScript("OnClick", function()
        BL.SetSetting(key, this:GetChecked() and true or false)
        BL.ForceRefresh()
    end)

    table.insert(refreshers, function()
        cb:SetChecked(BL.GetSetting(key) ~= false)
        labelFs:SetFont(BL.GetFontPath(), 11, "OUTLINE")
    end)

    return cb
end

local function AddStepperRow(parent, label, key, minV, maxV, step, y, formatFn)
    local labelFs = parent:CreateFontString(nil, "OVERLAY")
    labelFs:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, -y)
    labelFs:SetFont(BL.GetFontPath(), 11, "OUTLINE")
    labelFs:SetText(label)

    local stepper = CreateStepper(parent, 90)
    stepper:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, -y + 1)

    local function Format(v)
        if formatFn then return formatFn(v) end
        return tostring(v)
    end

    local function Clamp(v)
        if v < minV then v = minV end
        if v > maxV then v = maxV end
        return v
    end

    local function SetVal(v)
        BL.SetSetting(key, Clamp(v))
        BL.ForceRefresh()
        stepper.value:SetText(Format(Clamp(v)))
    end

    stepper.minus:SetScript("OnClick", function()
        SetVal((tonumber(BL.GetSetting(key)) or minV) - step)
    end)
    stepper.plus:SetScript("OnClick", function()
        SetVal((tonumber(BL.GetSetting(key)) or minV) + step)
    end)

    table.insert(refreshers, function()
        local v = tonumber(BL.GetSetting(key)) or minV
        stepper.value:SetText(Format(v))
        labelFs:SetFont(BL.GetFontPath(), 11, "OUTLINE")
    end)

    return stepper
end

local function AddDropdownRow(parent, label, y, width, getLabelFn, openFn)
    local labelFs = parent:CreateFontString(nil, "OVERLAY")
    labelFs:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, -y)
    labelFs:SetFont(BL.GetFontPath(), 11, "OUTLINE")
    labelFs:SetText(label)

    local btn = CreateSmallButton(parent, width, "")
    btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, -y + 1)
    btn:SetScript("OnClick", function() openFn(btn) end)

    local function UpdateLabel()
        btn.label:SetText(getLabelFn())
    end
    UpdateLabel()

    table.insert(refreshers, function()
        UpdateLabel()
        labelFs:SetFont(BL.GetFontPath(), 11, "OUTLINE")
    end)

    return btn
end

-- Thin separator line between sections, same shape as CombatLedger's
-- own AddDivider - advances y by less than a full row since it isn't a
-- control needing a row's worth of breathing room on both sides.
local function AddDivider(parent, y)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetTexture("Interface\\Buttons\\WHITE8X8")
    line:SetVertexColor(1, 1, 1, 0.12)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, -y)
    line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, -y)
    return y + 10
end

local function AddSectionHeader(parent, label, y)
    local header = parent:CreateFontString(nil, "OVERLAY")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, -y)
    header:SetFont(BL.GetFontPath(), 12, "OUTLINE")
    header:SetText("|cffffd700" .. label .. "|r")
    table.insert(refreshers, function() header:SetFont(BL.GetFontPath(), 12, "OUTLINE") end)
    return y + ROW_HEIGHT
end

--------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------

local function BuildFrame()
    frame = CreateFrame("Frame", "BuffLedgerOptionsFrame", UIParent)
    frame:SetWidth(WINDOW_WIDTH)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() this:StartMoving() end)
    frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)

    BL.ApplyIconSkin(frame):SetBackdropBorderColor(BL.FLAT_BORDER_R, BL.FLAT_BORDER_G, BL.FLAT_BORDER_B, 1)
    table.insert(refreshers, function()
        BL.ApplyIconSkin(frame):SetBackdropBorderColor(BL.FLAT_BORDER_R, BL.FLAT_BORDER_G, BL.FLAT_BORDER_B, 1)
    end)

    local title = frame:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOP", frame, "TOP", 0, -12)
    title:SetFont(BL.GetFontPath(), 15, "OUTLINE")
    title:SetText("|cffa335eeBuffLedger Options|r")
    table.insert(refreshers, function() title:SetFont(BL.GetFontPath(), 15, "OUTLINE") end)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetWidth(18)
    close:SetHeight(18)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() frame:Hide() end)

    local y = 42

    AddCheckboxRow(frame, "Locked (no dragging)", "locked", y); y = y + ROW_HEIGHT
    AddCheckboxRow(frame, "Show background panel", "showBackground", y); y = y + ROW_HEIGHT
    AddCheckboxRow(frame, "Show duration inside icon", "showDurationInside", y); y = y + ROW_HEIGHT
    AddCheckboxRow(frame, "Grow right-to-left", "growLeft", y); y = y + ROW_HEIGHT

    y = AddDivider(frame, y)
    y = AddSectionHeader(frame, "Layout", y)
    AddStepperRow(frame, "Icon size", "iconSize", 16, 60, 1, y); y = y + ROW_HEIGHT
    AddStepperRow(frame, "Icon spacing", "spacing", 0, 20, 1, y); y = y + ROW_HEIGHT
    AddStepperRow(frame, "Category gap", "categoryGap", 0, 40, 1, y); y = y + ROW_HEIGHT
    AddStepperRow(frame, "Columns", "columns", 1, 20, 1, y); y = y + ROW_HEIGHT
    AddStepperRow(frame, "Border thickness", "borderThickness", 1, 6, 1, y); y = y + ROW_HEIGHT
    AddStepperRow(frame, "Scale", "scale", 0.5, 2, 0.05, y, function(v) return string.format("%.2f", v) end); y = y + ROW_HEIGHT

    y = AddDivider(frame, y)
    y = AddSectionHeader(frame, "Text", y)
    AddStepperRow(frame, "Text size", "fontSizeOverride", 8, 20, 1, y); y = y + ROW_HEIGHT
    AddDropdownRow(frame, "Font", y, 130,
        function()
            local key = BL.GetSetting("fontKey") or "expressway"
            local i
            for i = 1, table.getn(BL.FONTS) do
                if BL.FONTS[i].key == key then return BL.FONTS[i].label end
            end
            return BL.FONTS[1].label
        end,
        function(anchorBtn)
            local options = {}
            local i
            for i = 1, table.getn(BL.FONTS) do
                local font = BL.FONTS[i]
                table.insert(options, {
                    label = font.label,
                    onClick = function()
                        BL.SetSetting("fontKey", font.key)
                        BL.ForceRefresh()
                        Refresh()
                    end,
                })
            end
            BL.ShowDropdown(anchorBtn, options)
        end)
    y = y + ROW_HEIGHT

    -- Per-group visibility toggles used to live here (Class/Weapon/
    -- Consumable/World/Racial/Other checkboxes) - removed: the two-
    -- column layout was confusing (checkboxes didn't align with their
    -- own labels), and the simpler reality is everyone wants to see all
    -- their buffs anyway. The underlying settings/BL.Categorize groups
    -- still exist for sorting/coloring purposes and remain reachable
    -- via /bl toggle <group> for anyone who really wants to hide one.

    y = y + 10
    local resetBtn = CreateSmallButton(frame, WINDOW_WIDTH - 28, "Reset Position")
    resetBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -y)
    resetBtn:SetScript("OnClick", function()
        BL.ResetLayout()
        BL.frame:ClearAllPoints()
        BL.frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -170, -180)
        BL.Print("Position reset.")
    end)
    y = y + 18

    frame:SetHeight(y + 16)

    -- A freshly created Frame is shown by default - without this, the
    -- very first /bl options call built the frame (already visible),
    -- then ToggleOptions immediately saw IsShown() == true and hid it
    -- again in the same call, so it took a second command to actually
    -- see the window.
    frame:Hide()
end

function BL.ToggleOptions()
    if not frame then BuildFrame() end
    if frame:IsShown() then
        frame:Hide()
    else
        Refresh()
        frame:Show()
    end
end
