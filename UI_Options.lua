--[[
    BuffLedger - /bl options: a real settings window instead of only
    slash commands. Everything here just calls the same BL.GetSetting/
    BL.SetSetting + BL.ForceRefresh (or ForceDebuffRefresh) pair the
    slash commands/DebuffBar.lua already use - this is a second way to
    reach the same settings, not a separate code path.

    Two tabs - Buff Bar and Debuff Bar - rather than one long scroll,
    same reasoning CombatLedger's own General/Advanced split uses: the
    debuff bar has its own full set of layout/text/lock controls
    (DebuffBar.lua), just without the buff bar's Category Gap (there's
    no clustering to space out - see DebuffBar.lua's own header comment
    for why).

    Visual/widget vocabulary is deliberately ported from CombatLedger's
    own UI_Options.lua (tabs, row label-left/control-right, gold section
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
local CONTENT_TOP = 64 -- below the title/close row and the tab strip

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
-- Row helpers - all take `parent` as the first arg, so the same helpers
-- build both tabs' content just by pointing them at pageBuff/pageDebuff.
--------------------------------------------------------------------------

-- `refreshFn` defaults to BL.ForceRefresh (the buff bar) - pass
-- BL.ForceDebuffRefresh for a debuff-tab row instead. Same reasoning
-- as AddStepperRow's refreshFn param.
local function AddCheckboxRow(parent, label, key, y, refreshFn)
    refreshFn = refreshFn or BL.ForceRefresh

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
        refreshFn()
    end)

    table.insert(refreshers, function()
        cb:SetChecked(BL.GetSetting(key) ~= false)
        labelFs:SetFont(BL.GetFontPath(), 11, "OUTLINE")
    end)

    return cb
end

-- `refreshFn` defaults to BL.ForceRefresh (the buff bar) - pass
-- BL.ForceDebuffRefresh for a debuff-tab row instead.
local function AddStepperRow(parent, label, key, minV, maxV, step, y, formatFn, refreshFn)
    refreshFn = refreshFn or BL.ForceRefresh

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
        refreshFn()
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

-- A font-picker row bound to a specific settingKey/refresh pair -
-- shared shape for the buff tab's "fontKey" and the debuff tab's
-- "debuffFontKey".
local function AddFontRow(parent, y, settingKey, refreshFn)
    return AddDropdownRow(parent, "Font", y, 130,
        function()
            local key = BL.GetSetting(settingKey) or "expressway"
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
                        BL.SetSetting(settingKey, font.key)
                        refreshFn()
                        Refresh()
                    end,
                })
            end
            BL.ShowDropdown(anchorBtn, options)
        end)
end

--------------------------------------------------------------------------
-- Tab content builders
--------------------------------------------------------------------------

local function BuildBuffTab(page)
    local y = CONTENT_TOP

    AddCheckboxRow(page, "Locked (no dragging)", "locked", y); y = y + ROW_HEIGHT
    AddCheckboxRow(page, "Show background panel", "showBackground", y); y = y + ROW_HEIGHT
    AddCheckboxRow(page, "Show duration inside icon", "showDurationInside", y); y = y + ROW_HEIGHT
    AddCheckboxRow(page, "Grow right-to-left", "growLeft", y); y = y + ROW_HEIGHT
    AddCheckboxRow(page, "Consolidate same-category buffs", "consolidate", y); y = y + ROW_HEIGHT

    y = AddDivider(page, y)
    y = AddSectionHeader(page, "Layout", y)
    AddStepperRow(page, "Icon size", "iconSize", 16, 60, 1, y); y = y + ROW_HEIGHT
    AddStepperRow(page, "Icon spacing", "spacing", 0, 20, 1, y); y = y + ROW_HEIGHT
    AddStepperRow(page, "Category gap", "categoryGap", 0, 40, 1, y); y = y + ROW_HEIGHT
    AddStepperRow(page, "Columns", "columns", 1, 20, 1, y); y = y + ROW_HEIGHT
    AddStepperRow(page, "Border thickness", "borderThickness", 1, 6, 1, y); y = y + ROW_HEIGHT
    AddStepperRow(page, "Scale", "scale", 0.5, 2, 0.05, y, function(v) return string.format("%.2f", v) end); y = y + ROW_HEIGHT

    y = AddDivider(page, y)
    y = AddSectionHeader(page, "Text", y)
    AddStepperRow(page, "Text size", "fontSizeOverride", 8, 20, 1, y); y = y + ROW_HEIGHT
    AddFontRow(page, y, "fontKey", BL.ForceRefresh); y = y + ROW_HEIGHT

    y = y + 10
    local resetBtn = CreateSmallButton(page, WINDOW_WIDTH - 28, "Reset Position")
    resetBtn:SetPoint("TOPLEFT", page, "TOPLEFT", 14, -y)
    resetBtn:SetScript("OnClick", function()
        BL.ResetLayout()
        BL.frame:ClearAllPoints()
        BL.frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -170, -180)
        BL.Print("Buff bar position reset.")
    end)
    y = y + 18

    return y
end

local function BuildDebuffTab(page)
    local y = CONTENT_TOP

    AddCheckboxRow(page, "Locked (no dragging)", "debuffLocked", y, BL.ForceDebuffRefresh); y = y + ROW_HEIGHT
    AddCheckboxRow(page, "Show background panel", "debuffShowBackground", y, BL.ForceDebuffRefresh); y = y + ROW_HEIGHT
    AddCheckboxRow(page, "Show duration inside icon", "debuffShowDurationInside", y, BL.ForceDebuffRefresh); y = y + ROW_HEIGHT
    AddCheckboxRow(page, "Grow right-to-left", "debuffGrowLeft", y, BL.ForceDebuffRefresh); y = y + ROW_HEIGHT

    y = AddDivider(page, y)
    y = AddSectionHeader(page, "Layout", y)
    AddStepperRow(page, "Icon size", "debuffIconSize", 16, 60, 1, y, nil, BL.ForceDebuffRefresh); y = y + ROW_HEIGHT
    AddStepperRow(page, "Icon spacing", "debuffSpacing", 0, 20, 1, y, nil, BL.ForceDebuffRefresh); y = y + ROW_HEIGHT
    AddStepperRow(page, "Columns", "debuffColumns", 1, 20, 1, y, nil, BL.ForceDebuffRefresh); y = y + ROW_HEIGHT
    AddStepperRow(page, "Border thickness", "debuffBorderThickness", 1, 6, 1, y, nil, BL.ForceDebuffRefresh); y = y + ROW_HEIGHT
    AddStepperRow(page, "Scale", "debuffScale", 0.5, 2, 0.05, y, function(v) return string.format("%.2f", v) end, BL.ForceDebuffRefresh); y = y + ROW_HEIGHT

    y = AddDivider(page, y)
    y = AddSectionHeader(page, "Text", y)
    AddStepperRow(page, "Text size", "debuffFontSizeOverride", 8, 20, 1, y, nil, BL.ForceDebuffRefresh); y = y + ROW_HEIGHT
    AddFontRow(page, y, "debuffFontKey", BL.ForceDebuffRefresh); y = y + ROW_HEIGHT

    y = y + 10
    local resetBtn = CreateSmallButton(page, WINDOW_WIDTH - 28, "Reset Position")
    resetBtn:SetPoint("TOPLEFT", page, "TOPLEFT", 14, -y)
    resetBtn:SetScript("OnClick", function()
        BL.ResetDebuffLayout()
        BL.debuffFrame:ClearAllPoints()
        BL.debuffFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -170, -260)
        BL.Print("Debuff bar position reset.")
    end)
    y = y + 18

    return y
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

    -- Two plain buttons + two content frames toggled together, not a
    -- real TabButtonTemplate strip - same "avoid Blizzard's heavier
    -- templates" reasoning as ShowDropdown instead of UIDropDownMenu.
    local pageBuff = CreateFrame("Frame", nil, frame)
    pageBuff:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    pageBuff:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    local pageDebuff = CreateFrame("Frame", nil, frame)
    pageDebuff:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    pageDebuff:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

    local tabBuffBtn = CreateSmallButton(frame, (WINDOW_WIDTH - 32) / 2, "Buff Bar")
    tabBuffBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -34)
    local tabDebuffBtn = CreateSmallButton(frame, (WINDOW_WIDTH - 32) / 2, "Debuff Bar")
    tabDebuffBtn:SetPoint("LEFT", tabBuffBtn, "RIGHT", 4, 0)

    local function ShowTab(tab)
        if tab == "debuff" then
            pageBuff:Hide()
            pageDebuff:Show()
            tabBuffBtn:SetBackdropColor(0.15, 0.15, 0.15, 0.75)
            tabDebuffBtn:SetBackdropColor(0.3, 0.25, 0.4, 0.9)
        else
            pageDebuff:Hide()
            pageBuff:Show()
            tabDebuffBtn:SetBackdropColor(0.15, 0.15, 0.15, 0.75)
            tabBuffBtn:SetBackdropColor(0.3, 0.25, 0.4, 0.9)
        end
    end
    tabBuffBtn:SetScript("OnClick", function() ShowTab("buff") end)
    tabDebuffBtn:SetScript("OnClick", function() ShowTab("debuff") end)

    local buffBottom = BuildBuffTab(pageBuff)
    local debuffBottom = BuildDebuffTab(pageDebuff)
    frame:SetHeight(math.max(buffBottom, debuffBottom) + 16)

    ShowTab("buff")

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
