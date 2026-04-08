-- GoldPulse UI: history window with filters
local addonName, GP = ...

local UI = {}
GP.UI = UI

local PERIODS = {
    { label = "Сегодня",  value = 86400 },
    { label = "7 дней",   value = 7 * 86400 },
    { label = "30 дней",  value = 30 * 86400 },
    { label = "Всё время", value = nil },
}

local TYPES = {
    { label = "Все",      value = "all" },
    { label = "Продажа",  value = GP.TYPE.SALE },
    { label = "Покупка",  value = GP.TYPE.BUY },
    { label = "AH Cut",   value = GP.TYPE.CUT },
    { label = "Депозит",  value = GP.TYPE.DEPOSIT },
}

local TYPE_LABEL = {
    [GP.TYPE.SALE]    = "Продажа",
    [GP.TYPE.BUY]     = "Покупка",
    [GP.TYPE.CUT]     = "AH Cut",
    [GP.TYPE.DEPOSIT] = "Депозит",
}

local state = {
    period = 86400,
    typeFilter = "all",
    search = "",
}

local ROW_HEIGHT = 20
local VISIBLE_ROWS = 15

function UI:Init()
    local f = CreateFrame("Frame", "GoldPulseFrame", UIParent, "BackdropTemplate")
    self.frame = f
    f:SetSize(720, 460)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()

    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    f:SetBackdropBorderColor(0.79, 0.65, 0.30, 1)

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cffc9a74dGoldPulse|r — История операций")

    -- Close button
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    -- Period dropdown
    local periodLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    periodLabel:SetPoint("TOPLEFT", 16, -42)
    periodLabel:SetText("Период:")

    local periodDd = CreateFrame("Frame", "GoldPulsePeriodDropdown", f, "UIDropDownMenuTemplate")
    periodDd:SetPoint("LEFT", periodLabel, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(periodDd, 100)
    UIDropDownMenu_Initialize(periodDd, function(_, level)
        for _, p in ipairs(PERIODS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = p.label
            info.checked = state.period == p.value
            info.func = function()
                state.period = p.value
                UIDropDownMenu_SetText(periodDd, p.label)
                UI:Refresh()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetText(periodDd, "Сегодня")

    -- Type dropdown
    local typeLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    typeLabel:SetPoint("LEFT", periodDd, "RIGHT", 8, 2)
    typeLabel:SetText("Тип:")

    local typeDd = CreateFrame("Frame", "GoldPulseTypeDropdown", f, "UIDropDownMenuTemplate")
    typeDd:SetPoint("LEFT", typeLabel, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(typeDd, 100)
    UIDropDownMenu_Initialize(typeDd, function(_, level)
        for _, t in ipairs(TYPES) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = t.label
            info.checked = state.typeFilter == t.value
            info.func = function()
                state.typeFilter = t.value
                UIDropDownMenu_SetText(typeDd, t.label)
                UI:Refresh()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetText(typeDd, "Все")

    -- Search box
    local searchBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    searchBox:SetSize(160, 20)
    searchBox:SetPoint("LEFT", typeDd, "RIGHT", 10, 2)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnTextChanged", function(self)
        state.search = self:GetText() or ""
        UI:Refresh()
    end)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    -- Header row
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", 16, -78)
    header:SetPoint("TOPRIGHT", -16, -78)
    header:SetHeight(20)

    local function makeHeader(text, x, w)
        local fs = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", header, "LEFT", x, 0)
        fs:SetWidth(w)
        fs:SetJustifyH("LEFT")
        fs:SetText("|cffc9a74d" .. text .. "|r")
        return fs
    end
    makeHeader("Время",    0,   70)
    makeHeader("Тип",      75,  80)
    makeHeader("Предмет",  160, 240)
    makeHeader("Кол",      405, 40)
    makeHeader("Цена",     450, 100)
    makeHeader("Итог",     555, 120)

    -- Separator
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(0.79, 0.65, 0.30, 0.5)
    sep:SetPoint("TOPLEFT", 16, -95)
    sep:SetPoint("TOPRIGHT", -16, -95)
    sep:SetHeight(1)

    -- Scroll frame
    local scroll = CreateFrame("ScrollFrame", "GoldPulseScroll", f, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -100)
    scroll:SetPoint("BOTTOMRIGHT", -32, 50)
    self.scroll = scroll

    -- Rows
    self.rows = {}
    for i = 1, VISIBLE_ROWS do
        local row = CreateFrame("Frame", nil, f)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:SetPoint("RIGHT", scroll, "RIGHT", 0, 0)

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(true)
        if i % 2 == 0 then
            bg:SetColorTexture(1, 1, 1, 0.03)
        else
            bg:SetColorTexture(1, 1, 1, 0.0)
        end

        local function mkFS(x, w, justify)
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", row, "LEFT", x, 0)
            fs:SetWidth(w)
            fs:SetJustifyH(justify or "LEFT")
            return fs
        end
        row.time  = mkFS(0,   70)
        row.type  = mkFS(75,  80)
        row.item  = mkFS(160, 240)
        row.count = mkFS(405, 40,  "RIGHT")
        row.price = mkFS(450, 100, "RIGHT")
        row.total = mkFS(555, 120, "RIGHT")

        self.rows[i] = row
    end

    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, function() UI:Refresh() end)
    end)

    -- Footer
    local footer = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    footer:SetPoint("BOTTOMLEFT", 16, 20)
    footer:SetPoint("BOTTOMRIGHT", -16, 20)
    footer:SetJustifyH("CENTER")
    self.footer = footer

    local footerSep = f:CreateTexture(nil, "ARTWORK")
    footerSep:SetColorTexture(0.79, 0.65, 0.30, 0.5)
    footerSep:SetPoint("BOTTOMLEFT", 16, 42)
    footerSep:SetPoint("BOTTOMRIGHT", -16, 42)
    footerSep:SetHeight(1)
end

function UI:Toggle()
    if not self.frame then return end
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self.frame:Show()
        self:Refresh()
    end
end

function UI:Show()
    if self.frame then self.frame:Show(); self:Refresh() end
end

local function formatTime(t)
    return date("%H:%M", t)
end

function UI:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    local list, income, expense, count = GP:GetTotals(state.period, state.typeFilter, state.search)

    local offset = FauxScrollFrame_GetOffset(self.scroll) or 0
    FauxScrollFrame_Update(self.scroll, #list, VISIBLE_ROWS, ROW_HEIGHT)

    for i = 1, VISIBLE_ROWS do
        local row = self.rows[i]
        local idx = i + offset
        local tr = list[idx]
        if tr then
            row.time:SetText(formatTime(tr.time))
            row.type:SetText(TYPE_LABEL[tr.type] or tr.type)
            row.item:SetText(tr.item or "?")
            row.count:SetText(tr.count and tr.count > 0 and tostring(tr.count) or "-")
            row.price:SetText(tr.price and tr.price > 0 and GP:FormatMoney(tr.price) or "-")
            local total = tr.total or 0
            local color = total >= 0 and "|cff4ade80" or "|cfff87171"
            local sign = total >= 0 and "+" or ""
            row.total:SetText(color .. sign .. GP:FormatMoney(total) .. "|r")
            row:Show()
        else
            row:Hide()
        end
    end

    local net = income + expense
    local netColor = net >= 0 and "|cff4ade80" or "|cfff87171"
    self.footer:SetText(string.format(
        "Записей: %d     Доход: |cff4ade80%s|r     Расход: |cfff87171%s|r     Net: %s%s|r",
        count, GP:FormatMoney(income), GP:FormatMoney(expense), netColor, GP:FormatMoney(net)
    ))
end
