-- GoldPulse Core: addon namespace, SavedVariables, event dispatcher
local addonName, GP = ...
_G.GoldPulse = GP

GP.version = "0.1.0"

-- Transaction types
GP.TYPE = {
    SALE    = "sale",
    BUY     = "buy",
    CUT     = "cut",
    DEPOSIT = "deposit",
}

-- Default DB
local defaults = {
    transactions = {},
    settings = {
        minimapPos = 220,
        minimapHide = false,
    },
}

local function deepCopyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            deepCopyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

-- Event frame
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")

f:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        GoldPulseDB = GoldPulseDB or {}
        deepCopyDefaults(GoldPulseDB, defaults)
        GP.db = GoldPulseDB
    elseif event == "PLAYER_LOGIN" then
        if GP.Tracker and GP.Tracker.Init then GP.Tracker:Init() end
        if GP.UI and GP.UI.Init then GP.UI:Init() end
        if GP.Minimap and GP.Minimap.Init then GP.Minimap:Init() end
        print("|cffc9a74dGoldPulse|r v" .. GP.version .. " loaded. /gp — open history")
    end
end)

-- Add a transaction record
function GP:AddTransaction(t)
    t.time = t.time or time()
    table.insert(self.db.transactions, t)
    if self.UI and self.UI.Refresh then self.UI:Refresh() end
end

-- Totals by filter (period in seconds, or nil = all)
function GP:GetTotals(period, typeFilter, search)
    local now = time()
    local income, expense, count = 0, 0, 0
    local list = {}
    for i = #self.db.transactions, 1, -1 do
        local tr = self.db.transactions[i]
        local okPeriod = (not period) or (now - tr.time <= period)
        local okType = (not typeFilter) or (typeFilter == "all") or (tr.type == typeFilter)
        local okSearch = (not search) or search == "" or
            (tr.item and tr.item:lower():find(search:lower(), 1, true))
        if okPeriod and okType and okSearch then
            count = count + 1
            if tr.total and tr.total > 0 then
                income = income + tr.total
            else
                expense = expense + (tr.total or 0)
            end
            table.insert(list, tr)
        end
    end
    return list, income, expense, count
end

-- Format copper to "1,234g 56s 78c" (short)
function GP:FormatMoney(copper)
    if not copper then return "0g" end
    local sign = copper < 0 and "-" or ""
    copper = math.abs(copper)
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    if g > 0 then
        return string.format("%s%s|cffffd700g|r", sign, BreakUpLargeNumbers(g))
    elseif s > 0 then
        return string.format("%s%d|cffc7c7cfs|r", sign, s)
    else
        return string.format("%s%d|cffeda55fc|r", sign, c)
    end
end

SLASH_GOLDPULSE1 = "/gp"
SLASH_GOLDPULSE2 = "/goldpulse"
SlashCmdList["GOLDPULSE"] = function(msg)
    if GP.UI and GP.UI.Toggle then GP.UI:Toggle() end
end
