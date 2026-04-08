-- GoldPulse Minimap: golden coin button with tooltip
local addonName, GP = ...

local Minimap = {}
GP.Minimap = Minimap

local function UpdatePosition(button)
    local angle = math.rad(GP.db.settings.minimapPos or 220)
    local x, y = math.cos(angle), math.sin(angle)
    local radius = (_G.Minimap:GetWidth() / 2) + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", _G.Minimap, "CENTER", x * radius, y * radius)
end

function Minimap:Init()
    if GP.db.settings.minimapHide then return end

    local btn = CreateFrame("Button", "GoldPulseMinimapButton", _G.Minimap)
    self.button = btn
    btn:SetSize(32, 32)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn:SetMovable(true)

    -- Icon
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Border
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(52, 52)
    border:SetPoint("TOPLEFT")

    UpdatePosition(btn)

    -- Dragging around minimap
    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function(self)
            local mx, my = _G.Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = _G.Minimap:GetEffectiveScale()
            px, py = px / scale, py / scale
            local angle = math.deg(math.atan2(py - my, px - mx))
            GP.db.settings.minimapPos = angle
            UpdatePosition(self)
        end)
    end)
    btn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    -- Click
    btn:SetScript("OnClick", function(_, button)
        if button == "LeftButton" then
            GP.UI:Toggle()
        elseif button == "RightButton" then
            print("|cffc9a74dGoldPulse|r: настройки пока не реализованы (MVP)")
        end
    end)

    -- Tooltip
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cffc9a74dGoldPulse|r")
        GameTooltip:AddLine(" ")
        local _, inc, exp = GP:GetTotals(86400, "all", nil)
        local net = inc + exp
        local netColor = net >= 0 and "|cff4ade80" or "|cfff87171"
        local sign = net >= 0 and "+" or ""
        GameTooltip:AddDoubleLine("Сегодня:", netColor .. sign .. GP:FormatMoney(net) .. "|r")
        GameTooltip:AddDoubleLine("Доход:", "|cff4ade80" .. GP:FormatMoney(inc) .. "|r")
        GameTooltip:AddDoubleLine("Расход:", "|cfff87171" .. GP:FormatMoney(exp) .. "|r")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("ЛКМ — открыть историю", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("ПКМ — настройки", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
