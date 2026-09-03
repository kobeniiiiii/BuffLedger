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

-- Exposed so Core.lua's category StaticPopups (New Category, Reset
-- Categories - both live in Core.lua, centralized with the other
-- StaticPopupDialogs there) can resync this window's own display after
-- changing data out from under it. BL.ForceRefresh only re-renders the
-- live buff bar - it never touched this window, so a category created/
-- restored while Options was already open updated SavedVariables
-- correctly but never appeared in the still-open list until the window
-- was closed and reopened (which calls Refresh() fresh). A no-op
-- before the window has ever been built (refreshers is just empty
-- then), which never happens in practice - these popups are only ever
-- reachable through buttons that already live inside this window.
function BL.RefreshOptionsWindow()
    Refresh()
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
    AddCheckboxRow(page, "  -> only while in a group", "consolidateOnlyGroup", y); y = y + ROW_HEIGHT
    AddCheckboxRow(page, "  -> only while in a raid", "consolidateOnlyRaid", y); y = y + ROW_HEIGHT

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
-- Categories tab - every category is fully user-editable data now
-- (Core.lua's BL.CreateCategory/DeleteCategory/etc, seeded from
-- Data.lua's BL.DEFAULT_CATEGORIES on first run only). No per-category
-- buff list here on purpose - shift-right-click a live icon, or the
-- "Add a Buff" box below, are the ways in; browsing/removing individual
-- members isn't needed to manage the category set itself.
--------------------------------------------------------------------------

local CATEGORY_ROW_H = 20
local CATEGORY_LIST_HEIGHT = 120
local categoryRows = {}
local categoryScrollContent

-- A small floating label that follows the cursor while dragging a row -
-- deliberately NOT the row itself being moved (SetPoint-based free
-- dragging would permanently disturb that pool slot's anchor, since
-- RefreshCategoryList only ever sets a row's position once, at
-- creation). The real row never moves; only this ghost does, and the
-- actual reorder happens once, on drop (BL.MoveCategoryToIndex).
local dragGhost

local function GetDragGhost()
    if not dragGhost then
        dragGhost = CreateFrame("Frame", nil, UIParent)
        dragGhost:SetFrameStrata("TOOLTIP")
        dragGhost:SetWidth(160)
        dragGhost:SetHeight(CATEGORY_ROW_H)
        BL.ApplyIconSkin(dragGhost):SetBackdropBorderColor(BL.FLAT_BORDER_R, BL.FLAT_BORDER_G, BL.FLAT_BORDER_B, 1)
        local text = dragGhost:CreateFontString(nil, "OVERLAY")
        text:SetAllPoints(dragGhost)
        text:SetJustifyH("CENTER")
        dragGhost.text = text
        dragGhost:Hide()
    end
    return dragGhost
end

local function RefreshCategoryList()
    if not categoryScrollContent then return end
    local order = BL.GetCategoryOrder()
    local n = table.getn(order)
    local i
    for i = 1, n do
        local id = order[i]
        local cat = BL.GetCategory(id)
        local row = categoryRows[i]
        if not row then
            row = CreateFrame("Frame", nil, categoryScrollContent)
            row:SetHeight(CATEGORY_ROW_H)
            row:SetPoint("TOPLEFT", categoryScrollContent, "TOPLEFT", 0, -(i - 1) * CATEGORY_ROW_H)
            row:SetPoint("TOPRIGHT", categoryScrollContent, "TOPRIGHT", 0, -(i - 1) * CATEGORY_ROW_H)

            -- Drag anywhere on the row's own background (not its swatch/
            -- name/delete children, which capture their own clicks first)
            -- to reorder - this row's screen position never changes
            -- during the drag, only the ghost label does; the actual
            -- move happens once, on drop.
            row:EnableMouse(true)
            row:RegisterForDrag("LeftButton")
            row:SetScript("OnDragStart", function()
                local ghost = GetDragGhost()
                ghost.text:SetFont(BL.GetFontPath(), 11, "OUTLINE")
                ghost.text:SetText(this.name:GetText())
                ghost:Show()
                this:SetScript("OnUpdate", function()
                    local cx, cy = GetCursorPosition()
                    local scale = UIParent:GetEffectiveScale()
                    ghost:ClearAllPoints()
                    ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / scale, cy / scale)
                end)
            end)
            row:SetScript("OnDragStop", function()
                this:SetScript("OnUpdate", nil)
                GetDragGhost():Hide()

                local _, cy = GetCursorPosition()
                local scale = categoryScrollContent:GetEffectiveScale()
                cy = cy / scale
                local contentTop = categoryScrollContent:GetTop()
                if contentTop then
                    local targetIndex = math.floor((contentTop - cy) / CATEGORY_ROW_H) + 1
                    BL.MoveCategoryToIndex(this.categoryId, targetIndex)
                    BL.ForceRefresh()
                    RefreshCategoryList()
                end
            end)

            -- Color swatch - click opens the stock ColorPickerFrame.
            -- categoryId is set fresh below on every refresh (this row
            -- object gets reused for a different category whenever the
            -- list changes), not fixed at creation time.
            local swatch = CreateFrame("Button", nil, row)
            swatch:SetWidth(14)
            swatch:SetHeight(14)
            swatch:SetPoint("LEFT", row, "LEFT", 2, 0)
            swatch.tex = swatch:CreateTexture(nil, "OVERLAY")
            swatch.tex:SetAllPoints(swatch)
            swatch.tex:SetTexture("Interface\\Buttons\\WHITE8X8")
            swatch:SetScript("OnClick", function()
                local c = BL.GetCategory(this.categoryId)
                if not c then return end
                ColorPickerFrame.func = function()
                    local r, g, b = ColorPickerFrame:GetColorRGB()
                    BL.SetCategoryColor(this.categoryId, r, g, b)
                    BL.ForceRefresh()
                    RefreshCategoryList()
                end
                ColorPickerFrame.cancelFunc = function() end
                ColorPickerFrame.hasOpacity = false
                ColorPickerFrame:SetColorRGB(c.color[1], c.color[2], c.color[3])
                -- Its default strata sits below this window's own HIGH,
                -- same class of "which one wins is down to luck" issue
                -- as everything else fixed today - force it above
                -- explicitly rather than trust the default.
                ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
                ShowUIPanel(ColorPickerFrame)
            end)
            row.swatch = swatch

            local name = row:CreateFontString(nil, "OVERLAY")
            name:SetPoint("LEFT", swatch, "RIGHT", 6, 0)
            name:SetPoint("RIGHT", row, "RIGHT", -20, 0)
            name:SetJustifyH("LEFT")
            row.name = name
            table.insert(refreshers, function() row.name:SetFont(BL.GetFontPath(), 11, "OUTLINE") end)

            local del = CreateSmallButton(row, 16, "x")
            del:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            del:SetScript("OnClick", function()
                BL.ConfirmDeleteCategory(this.categoryId)
            end)
            row.del = del

            categoryRows[i] = row
        end

        row.categoryId = id
        row.swatch.categoryId = id
        row.swatch.tex:SetVertexColor(cat.color[1], cat.color[2], cat.color[3])
        row.name:SetFont(BL.GetFontPath(), 11, "OUTLINE")
        row.name:SetText(cat.name)
        row.del.categoryId = id
        -- "Other" (and anything else marked non-deletable) has no
        -- delete button at all - BL.DeleteCategory would refuse it
        -- anyway, but hiding it here avoids an inert button.
        if cat.deletable then
            row.del:Show()
        else
            row.del:Hide()
        end
        row:Show()
    end

    local j
    for j = n + 1, table.getn(categoryRows) do
        categoryRows[j]:Hide()
    end

    categoryScrollContent:SetHeight(math.max(CATEGORY_LIST_HEIGHT, n * CATEGORY_ROW_H))
end

--------------------------------------------------------------------------
-- Assignment history window - every BL.SetOverride call, regardless of
-- how it was made (shift-right-click on the bar, a consolidate popout
-- tile, or the Categories tab's own "Add a Buff" box), gets logged
-- centrally in Core.lua (BL.GetAssignHistory) - this is just a viewer
-- for that log, not a separate tracking mechanism. Right-click any
-- entry to reassign that same buff again, straight from here.
--------------------------------------------------------------------------

local HISTORY_ROW_H = 18
local HISTORY_WINDOW_HEIGHT = 220
local historyWindow
local historyWindowRows = {}
local historyScrollContent

local function RefreshHistoryWindow()
    if not historyScrollContent then return end
    local history = BL.GetAssignHistory()
    local total = table.getn(history)
    local i
    for i = 1, total do
        local entry = history[total - i + 1]
        local row = historyWindowRows[i]
        if not row then
            row = CreateFrame("Button", nil, historyScrollContent)
            row:SetHeight(HISTORY_ROW_H)
            row:RegisterForClicks("RightButtonUp")
            row:SetPoint("TOPLEFT", historyScrollContent, "TOPLEFT", 0, -(i - 1) * HISTORY_ROW_H)
            row:SetPoint("TOPRIGHT", historyScrollContent, "TOPRIGHT", 0, -(i - 1) * HISTORY_ROW_H)
            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints(row)
            hl:SetTexture("Interface\\Buttons\\WHITE8X8")
            hl:SetVertexColor(1, 1, 1, 0.1)
            local text = row:CreateFontString(nil, "OVERLAY")
            text:SetPoint("LEFT", row, "LEFT", 2, 0)
            text:SetJustifyH("LEFT")
            row.text = text
            row:SetScript("OnClick", function()
                BL.ShowCategoryAssignMenu(this, this.buffName, function()
                    RefreshHistoryWindow()
                end)
            end)
            historyWindowRows[i] = row
        end

        row.buffName = entry.name
        row.text:SetFont(BL.GetFontPath(), 10, "OUTLINE")
        row.text:SetText(entry.name .. " |cff999999->|r " .. BL.GetCategoryName(entry.categoryId))
        row:Show()
    end

    local j
    for j = total + 1, table.getn(historyWindowRows) do
        historyWindowRows[j]:Hide()
    end

    historyScrollContent:SetHeight(math.max(HISTORY_WINDOW_HEIGHT - 40, total * HISTORY_ROW_H))
end

local function BuildHistoryWindow()
    local f = CreateFrame("Frame", "BuffLedgerHistoryWindow", UIParent)
    f:SetWidth(280)
    f:SetHeight(HISTORY_WINDOW_HEIGHT)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    -- DIALOG, not FULLSCREEN_DIALOG - the right-click reassign dropdown
    -- (BL.ShowDropdown, Core.lua) opens FROM this window and needs to
    -- draw cleanly above it. Same strata meant which one won was down
    -- to frame-level luck, same class of bug as the Options window vs.
    -- StaticPopup issue earlier.
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    BL.ApplyIconSkin(f):SetBackdropBorderColor(BL.FLAT_BORDER_R, BL.FLAT_BORDER_G, BL.FLAT_BORDER_B, 1)

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOP", f, "TOP", 0, -10)
    title:SetFont(BL.GetFontPath(), 13, "OUTLINE")
    title:SetText("|cffa335eeAssignment History|r")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetWidth(18)
    close:SetHeight(18)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() f:Hide() end)

    local hint = f:CreateFontString(nil, "OVERLAY")
    hint:SetPoint("TOP", f, "TOP", 0, -28)
    hint:SetFont(BL.GetFontPath(), 9, "OUTLINE")
    hint:SetTextColor(0.6, 0.6, 0.6)
    hint:SetText("Right-click an entry to reassign it")

    local scrollFrame = CreateFrame("ScrollFrame", "BuffLedgerHistoryScroll", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -42)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 12)

    historyScrollContent = CreateFrame("Frame", nil, scrollFrame)
    historyScrollContent:SetWidth(240)
    historyScrollContent:SetHeight(HISTORY_WINDOW_HEIGHT - 40)
    scrollFrame:SetScrollChild(historyScrollContent)

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function()
        local current = scrollFrame:GetVerticalScroll()
        local maxScroll = math.max(0, historyScrollContent:GetHeight() - scrollFrame:GetHeight())
        local new = current - arg1 * HISTORY_ROW_H
        if new < 0 then new = 0 end
        if new > maxScroll then new = maxScroll end
        scrollFrame:SetVerticalScroll(new)
    end)

    f:Hide()
    return f
end

local function ShowHistoryWindow()
    if not historyWindow then
        historyWindow = BuildHistoryWindow()
    end
    RefreshHistoryWindow()
    historyWindow:Show()
end

-- `targetHeight` is the shared window height every tab draws inside
-- now (matching CombatLedger's own convention - one fixed window size,
-- not a per-tab resize) - the scroll list fills whatever's left after
-- everything below it (Add a Buff + the History button, a known fixed
-- height), instead of sitting at a small fixed size with dead space
-- under it.
local function BuildCategoriesTab(page, targetHeight)
    local y = CONTENT_TOP

    local halfWidth = (WINDOW_WIDTH - 28 - 4) / 2
    local newBtn = CreateSmallButton(page, halfWidth, "+ New Category")
    newBtn:SetPoint("TOPLEFT", page, "TOPLEFT", 14, -y)
    newBtn:SetScript("OnClick", function() BL.PromptNewCategory() end)

    local resetBtn = CreateSmallButton(page, halfWidth, "Reset to Default")
    resetBtn:SetPoint("LEFT", newBtn, "RIGHT", 4, 0)
    resetBtn:SetScript("OnClick", function() BL.ConfirmResetCategoriesToDefault() end)
    y = y + ROW_HEIGHT + 4

    -- Everything below the scroll list, in the order it's built further
    -- down: 10 (gap) + AddDivider's 10 + AddSectionHeader's ROW_HEIGHT +
    -- the edit box row's ROW_HEIGHT+6 + the History button's ROW_HEIGHT.
    local belowListHeight = 10 + 10 + ROW_HEIGHT + (ROW_HEIGHT + 6) + ROW_HEIGHT
    CATEGORY_LIST_HEIGHT = math.max(60, (targetHeight or 0) - y - belowListHeight)

    local scrollWidth = WINDOW_WIDTH - 12 - 14 - 20
    local categoryScrollFrame = CreateFrame("ScrollFrame", "BuffLedgerCategoryScroll", page, "UIPanelScrollFrameTemplate")
    categoryScrollFrame:SetPoint("TOPLEFT", page, "TOPLEFT", 14, -y)
    categoryScrollFrame:SetWidth(scrollWidth)
    categoryScrollFrame:SetHeight(CATEGORY_LIST_HEIGHT)

    categoryScrollContent = CreateFrame("Frame", nil, categoryScrollFrame)
    categoryScrollContent:SetWidth(scrollWidth)
    categoryScrollContent:SetHeight(CATEGORY_LIST_HEIGHT)
    categoryScrollFrame:SetScrollChild(categoryScrollContent)

    -- UIPanelScrollFrameTemplate gives the scrollbar itself, but not
    -- mouse-wheel support - wired by hand so scrolling doesn't require
    -- dragging the thumb precisely.
    categoryScrollFrame:EnableMouseWheel(true)
    categoryScrollFrame:SetScript("OnMouseWheel", function()
        local current = categoryScrollFrame:GetVerticalScroll()
        local maxScroll = math.max(0, categoryScrollContent:GetHeight() - categoryScrollFrame:GetHeight())
        local new = current - arg1 * CATEGORY_ROW_H
        if new < 0 then new = 0 end
        if new > maxScroll then new = maxScroll end
        categoryScrollFrame:SetVerticalScroll(new)
    end)

    RefreshCategoryList()
    table.insert(refreshers, RefreshCategoryList)

    y = y + CATEGORY_LIST_HEIGHT + 10

    y = AddDivider(page, y)
    y = AddSectionHeader(page, "Add a Buff", y)

    -- One shared assign flow, not a text box per category - type a
    -- name (doesn't need to be on the bar right now), Assign opens the
    -- same color-coded category dropdown shift-right-clicking a live
    -- icon does (BL.ShowCategoryAssignMenu, Bar.lua).
    local editBox = CreateFrame("EditBox", nil, page)
    editBox:SetHeight(18)
    editBox:SetPoint("TOPLEFT", page, "TOPLEFT", 14, -y)
    editBox:SetPoint("TOPRIGHT", page, "TOPRIGHT", -70, -y)
    editBox:SetAutoFocus(false)
    editBox:SetFont(BL.GetFontPath(), 11, "OUTLINE")
    BL.ApplyIconSkin(editBox):SetBackdropBorderColor(BL.FLAT_BORDER_R, BL.FLAT_BORDER_G, BL.FLAT_BORDER_B, 1)
    table.insert(refreshers, function() editBox:SetFont(BL.GetFontPath(), 11, "OUTLINE") end)

    local addBtn = CreateSmallButton(page, 52, "Assign")
    addBtn:SetPoint("TOPRIGHT", page, "TOPRIGHT", -12, -y - 1)
    addBtn:SetScript("OnClick", function()
        local text = editBox:GetText()
        if text and text ~= "" then
            BL.ShowCategoryAssignMenu(addBtn, text, function()
                editBox:SetText("")
            end)
        end
    end)
    y = y + ROW_HEIGHT + 6

    local historyBtn = CreateSmallButton(page, WINDOW_WIDTH - 28, "View Assignment History")
    historyBtn:SetPoint("TOPLEFT", page, "TOPLEFT", 14, -y)
    historyBtn:SetScript("OnClick", function() ShowHistoryWindow() end)
    y = y + ROW_HEIGHT

    return y
end

--------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------

local function BuildFrame()
    frame = CreateFrame("Frame", "BuffLedgerOptionsFrame", UIParent)
    frame:SetWidth(WINDOW_WIDTH)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    -- HIGH, not DIALOG - a native StaticPopup (New Category, Reset
    -- Categories confirm, ...) also defaults to DIALOG strata, so with
    -- this window AT that same tier too, which one draws on top came
    -- down to frame-level luck - the Options window (created/shown
    -- most recently) was winning, burying the popup behind itself with
    -- no visible sign it had opened at all. HIGH keeps this window
    -- above the game world and other addons while guaranteeing any
    -- native dialog still wins.
    frame:SetFrameStrata("HIGH")
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

    -- Three plain buttons + three content frames toggled together, not
    -- a real TabButtonTemplate strip - same "avoid Blizzard's heavier
    -- templates" reasoning as ShowDropdown instead of UIDropDownMenu.
    local pageBuff = CreateFrame("Frame", nil, frame)
    pageBuff:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    pageBuff:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    local pageDebuff = CreateFrame("Frame", nil, frame)
    pageDebuff:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    pageDebuff:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    local pageCategories = CreateFrame("Frame", nil, frame)
    pageCategories:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    pageCategories:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

    local tabWidth = (WINDOW_WIDTH - 28 - 8) / 3
    local tabBuffBtn = CreateSmallButton(frame, tabWidth, "Buff Bar")
    tabBuffBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -34)
    local tabDebuffBtn = CreateSmallButton(frame, tabWidth, "Debuff Bar")
    tabDebuffBtn:SetPoint("LEFT", tabBuffBtn, "RIGHT", 4, 0)
    local tabCategoriesBtn = CreateSmallButton(frame, tabWidth, "Categories")
    tabCategoriesBtn:SetPoint("LEFT", tabDebuffBtn, "RIGHT", 4, 0)

    -- One shared window size for every tab (matching CombatLedger's own
    -- convention), not a per-tab resize - Buff Bar's own content height
    -- is the tallest of the three and becomes the fixed size all three
    -- share. Categories fills that space itself (its scroll list grows
    -- to match - see BuildCategoriesTab's targetHeight param), so
    -- there's no dead area to leave in the first place.
    local buffBottom = BuildBuffTab(pageBuff)
    BuildDebuffTab(pageDebuff)
    BuildCategoriesTab(pageCategories, buffBottom)

    local function ShowTab(tab)
        pageBuff:Hide()
        pageDebuff:Hide()
        pageCategories:Hide()
        tabBuffBtn:SetBackdropColor(0.15, 0.15, 0.15, 0.75)
        tabDebuffBtn:SetBackdropColor(0.15, 0.15, 0.15, 0.75)
        tabCategoriesBtn:SetBackdropColor(0.15, 0.15, 0.15, 0.75)

        if tab == "debuff" then
            pageDebuff:Show()
            tabDebuffBtn:SetBackdropColor(0.3, 0.25, 0.4, 0.9)
        elseif tab == "categories" then
            pageCategories:Show()
            tabCategoriesBtn:SetBackdropColor(0.3, 0.25, 0.4, 0.9)
        else
            pageBuff:Show()
            tabBuffBtn:SetBackdropColor(0.3, 0.25, 0.4, 0.9)
        end
    end
    tabBuffBtn:SetScript("OnClick", function() ShowTab("buff") end)
    tabDebuffBtn:SetScript("OnClick", function() ShowTab("debuff") end)
    tabCategoriesBtn:SetScript("OnClick", function() ShowTab("categories") end)

    frame:SetHeight(buffBottom + 16)
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
