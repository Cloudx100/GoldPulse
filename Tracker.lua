-- GoldPulse Tracker: listens to AH and mail events, records transactions
local addonName, GP = ...

local Tracker = {}
GP.Tracker = Tracker

-- AH cut is 5% in retail
local AH_CUT = 0.05

function Tracker:Init()
    local f = CreateFrame("Frame")
    self.frame = f

    -- Auction House events
    f:RegisterEvent("AUCTION_HOUSE_SHOW")
    f:RegisterEvent("AUCTION_HOUSE_CLOSED")
    f:RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED")
    f:RegisterEvent("AUCTION_HOUSE_AUCTION_CREATED")
    f:RegisterEvent("PLAYER_MONEY")

    -- Mail (for sold auction payouts)
    f:RegisterEvent("MAIL_INBOX_UPDATE")
    f:RegisterEvent("MAIL_SHOW")
    f:RegisterEvent("MAIL_CLOSED")

    self.ahOpen = false
    self.lastMoney = GetMoney and GetMoney() or 0
    self.pendingBuy = nil  -- { item=..., count=..., expires=time }

    f:SetScript("OnEvent", function(_, event, ...)
        local handler = Tracker[event]
        if handler then handler(Tracker, ...) end
    end)
end

-- ===== Auction posting: record deposit =====
function Tracker:AUCTION_HOUSE_AUCTION_CREATED(auctionID)
    -- Deposit amount isn't directly exposed by this event; best-effort hook below
end

-- Hook posting (deposit) and buying
local hooked = false
local function HookAH()
    if hooked or not C_AuctionHouse then return end
    hooked = true

    -- PlaceBid: bid or buyout on a single-item auction
    if C_AuctionHouse.PlaceBid then
        hooksecurefunc(C_AuctionHouse, "PlaceBid", function(auctionID, bidAmount)
            local name = "Auction item"
            if C_AuctionHouse.GetItemKeyFromItemID then
                -- best-effort: unknown without more context
            end
            GP.Tracker.pendingBuy = {
                item = name,
                count = 1,
                amount = bidAmount,
                expires = GetTime() + 3,
            }
        end)
    end

    -- Commodities purchase
    if C_AuctionHouse.ConfirmCommoditiesPurchase then
        hooksecurefunc(C_AuctionHouse, "ConfirmCommoditiesPurchase", function(itemID, quantity)
            local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID))
                or (GetItemInfo and GetItemInfo(itemID))
                or ("Item "..tostring(itemID))
            local info = C_AuctionHouse.GetCommoditiesPurchaseInfo and C_AuctionHouse.GetCommoditiesPurchaseInfo()
            local total = info and info.totalPrice or nil
            GP.Tracker.pendingBuy = {
                item = name,
                count = quantity or 1,
                amount = total,
                expires = GetTime() + 3,
            }
        end)
    end

    if C_AuctionHouse.PostItem then
        hooksecurefunc(C_AuctionHouse, "PostItem", function(itemLocation, duration, quantity, bid, buyout)
            local deposit = C_AuctionHouse.CalculateItemDeposit and
                C_AuctionHouse.CalculateItemDeposit(itemLocation, duration, quantity) or 0
            local name = "Unknown"
            if itemLocation and C_Item and C_Item.DoesItemExist(itemLocation) then
                name = C_Item.GetItemName(itemLocation) or name
            end
            if deposit and deposit > 0 then
                GP:AddTransaction({
                    type = GP.TYPE.DEPOSIT,
                    item = name,
                    count = quantity or 1,
                    price = 0,
                    total = -deposit,
                })
            end
        end)
    end

    if C_AuctionHouse.PostCommodity then
        hooksecurefunc(C_AuctionHouse, "PostCommodity", function(itemLocation, duration, quantity, unitPrice)
            local deposit = C_AuctionHouse.CalculateCommodityDeposit and
                C_AuctionHouse.CalculateCommodityDeposit(
                    (itemLocation and C_Item and C_Item.GetItemID(itemLocation)) or 0,
                    duration, quantity) or 0
            local name = "Unknown"
            if itemLocation and C_Item and C_Item.DoesItemExist(itemLocation) then
                name = C_Item.GetItemName(itemLocation) or name
            end
            if deposit and deposit > 0 then
                GP:AddTransaction({
                    type = GP.TYPE.DEPOSIT,
                    item = name,
                    count = quantity or 1,
                    price = 0,
                    total = -deposit,
                })
            end
        end)
    end
end

function Tracker:AUCTION_HOUSE_SHOW()
    HookAH()
    self.ahOpen = true
    self.lastMoney = GetMoney() or 0
end

function Tracker:AUCTION_HOUSE_CLOSED()
    self.ahOpen = false
end

-- Detect purchases via money delta while AH is open
function Tracker:PLAYER_MONEY()
    local now = GetMoney() or 0
    local delta = now - (self.lastMoney or now)
    self.lastMoney = now
    if not self.ahOpen then return end
    if delta >= 0 then return end  -- only losses
    local spent = -delta

    -- Match with a pending buy (fresh)
    local pending = self.pendingBuy
    local item, count = "Auction purchase", 1
    if pending and pending.expires and GetTime() <= pending.expires then
        item = pending.item or item
        count = pending.count or 1
        self.pendingBuy = nil
    end

    GP:AddTransaction({
        type = GP.TYPE.BUY,
        item = item,
        count = count,
        price = (count > 0) and math.floor(spent / count) or spent,
        total = -spent,
    })
end

function Tracker:COMMODITY_PURCHASE_SUCCEEDED() end

-- ===== Mail: detect AH sale payouts =====
-- Blizzard sends mail from sender "Auction House" with money attached when a lot sells.
-- We track already-seen mails by a simple signature to avoid duplicates.
local seen = {}

function Tracker:MAIL_INBOX_UPDATE()
    local num = GetInboxNumItems and GetInboxNumItems() or 0
    for i = 1, num do
        local _, _, sender, subject, money, _, daysLeft, _, _, _, _, _, isGM = GetInboxHeaderInfo(i)
        if sender and subject and money and money > 0 then
            -- Signature: sender + subject + money + daysLeft rounded
            local sig = string.format("%s|%s|%d|%d", sender, subject, money, math.floor((daysLeft or 0) * 10))
            if not seen[sig] and self:IsAuctionSaleMail(sender, subject) then
                seen[sig] = true
                local itemName = subject:match("^[^:]+: (.+)$") or subject
                -- Net money received already has AH cut deducted by Blizzard
                -- Record gross sale approximation: money is the net; cut = money * 5/95
                local cut = math.floor(money * AH_CUT / (1 - AH_CUT))
                GP:AddTransaction({
                    type = GP.TYPE.SALE,
                    item = itemName,
                    count = 1,
                    price = money + cut,
                    total = money + cut,
                })
                GP:AddTransaction({
                    type = GP.TYPE.CUT,
                    item = itemName,
                    count = 1,
                    price = 0,
                    total = -cut,
                })
            end
        end
    end
end

function Tracker:IsAuctionSaleMail(sender, subject)
    -- Localized strings from Blizzard globals
    if AUCTION_HOUSE_MAIL_SELLER and sender == AUCTION_HOUSE_MAIL_SELLER then return true end
    if sender and sender:find("Auction House") then return true end
    if subject and (subject:find("Auction successful") or subject:find("Аукцион") or subject:find("успеш")) then
        return true
    end
    return false
end

function Tracker:MAIL_SHOW() end
function Tracker:MAIL_CLOSED() end
