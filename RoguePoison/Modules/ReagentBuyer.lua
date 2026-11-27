local _, ns = ...
local L = ns.L

local M = {}
ns:RegisterModule("reagentBuyer", M)

local PROFESSIONS_ADDON = "Blizzard_Professions"
local MODES = { "stacks", "items" }
local UNIT_KEY = { stacks = "BUY_UNIT_STACKS", items = "BUY_UNIT_ITEMS" }
local MAX_AMOUNT = 99
local ROW_HEIGHT = 24
local BOX_LEFT = 29
local PURCHASE_ERRORS = {
    "ERR_INV_FULL",
    "ERR_BAG_FULL",
    "ERR_ITEM_MAX_COUNT",
    "ERR_NOT_ENOUGH_MONEY",
    "ERR_VENDOR_SOLD_OUT",
    "ERR_VENDOR_TOO_FAR",
}

local panel
local merchantOpen = false
local restockPending = false
local job
local loading = {}

local function Count(itemID)
    return C_Item.GetItemCount(itemID) or 0
end

local function RequestItem(itemID)
    if loading[itemID] then return end
    loading[itemID] = true
    C_Item.RequestLoadItemDataByID(itemID)
end

local function MerchantStock()
    local stock = {}
    for index = 1, GetMerchantNumItems() do
        local itemID = GetMerchantItemID(index)
        local info = itemID and not stock[itemID] and C_MerchantFrame.GetItemInfo(index)
        if info and info.isPurchasable and not info.hasExtendedCost then
            local step = math.max(info.stackCount or 1, 1)
            local maxStack = GetMerchantItemMaxStack(index) or step
            stock[itemID] = {
                index = index,
                price = info.price or 0,
                step  = step,
                available = info.numAvailable or -1,
                chunk = math.max(math.floor(maxStack / step), 1) * step,
            }
        end
    end
    return stock
end

local function SelectedRecipe()
    local form = ProfessionsFrame.CraftingPage.SchematicForm
    local recipeInfo = form:GetRecipeInfo()
    if not (recipeInfo and recipeInfo.learned) then return nil end
    local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeInfo.recipeID, false)
    if not (schematic and ns.ITEM_KIND[schematic.outputItemID] == "poison") then return nil end
    local reagents = {}
    for _, slot in ipairs(schematic.reagentSlotSchematics) do
        if slot.reagentType == Enum.CraftingReagentType.Basic then
            local reagent = slot.reagents[1]
            if not (reagent and reagent.itemID) then return nil end
            reagents[#reagents + 1] = { itemID = reagent.itemID, quantity = slot.quantityRequired }
        end
    end
    if #reagents == 0 then return nil end
    return {
        itemID   = schematic.outputItemID,
        yield    = math.max(schematic.quantityMin or 1, 1),
        reagents = reagents,
    }
end

local function SoldByMerchant(recipe, stock)
    for _, reagent in ipairs(recipe.reagents) do
        if not stock[reagent.itemID] then return false end
    end
    return true
end

local function Crafts(recipe, mode, amount)
    local items = amount
    if mode == "stacks" then
        local stackSize = C_Item.GetItemMaxStackSizeByID(recipe.itemID)
        if not stackSize then
            RequestItem(recipe.itemID)
            return nil
        end
        items = amount * stackSize
    end
    return math.ceil(items / recipe.yield)
end

local function Plan(recipe, stock, crafts)
    local orders, cost = {}, 0
    for _, reagent in ipairs(recipe.reagents) do
        local missing = crafts * reagent.quantity - Count(reagent.itemID)
        if missing > 0 then
            local s = stock[reagent.itemID]
            local bundles = math.ceil(missing / s.step)
            if s.available >= 0 and bundles > s.available then return orders, cost, true end
            orders[#orders + 1] = {
                itemID   = reagent.itemID,
                index    = s.index,
                chunk    = s.chunk,
                quantity = bundles * s.step,
            }
            cost = cost + bundles * s.price
        end
    end
    return orders, cost
end

local function Context()
    if not (ns.db.profile.enabled and merchantOpen and panel and ProfessionsFrame:IsShown()) then return nil end
    local recipe = SelectedRecipe()
    if not recipe then return nil end
    local stock = MerchantStock()
    if not SoldByMerchant(recipe, stock) then return nil end
    return recipe, stock
end

local function PlanFor(recipe, stock, mode)
    local crafts = Crafts(recipe, mode, ns.db.profile.buyAmount[mode])
    if not crafts then return nil end
    return Plan(recipe, stock, crafts)
end

local function CurrentPlan(mode)
    local recipe, stock = Context()
    if not recipe then return nil end
    return PlanFor(recipe, stock, mode)
end

local function FinishJob(stopped)
    job = nil
    if stopped then ns:Print(L["BUY_STOPPED"]) end
    M:Update()
end

local function NextPurchase()
    local order = job.orders[1]
    if order and order.quantity <= 0 then
        table.remove(job.orders, 1)
        order = job.orders[1]
    end
    if not order then
        FinishJob(false)
        return
    end
    if GetMerchantItemID(order.index) ~= order.itemID then
        FinishJob(true)
        return
    end
    local n = math.min(order.quantity, order.chunk)
    order.quantity = order.quantity - n
    job.itemID, job.index, job.before = order.itemID, order.index, Count(order.itemID)
    BuyMerchantItem(order.index, n)
end

local function RunOrders(orders)
    job = { orders = orders }
    M:Update()
    NextPurchase()
end

local function StartJob(mode)
    if job then return end
    local orders, cost, short = CurrentPlan(mode)
    if not orders or short or #orders == 0 then return end
    if GetMoney() < cost then return end
    RunOrders(orders)
end

local function Restock()
    local db = ns.db.profile
    if not (db.enabled and db.flashRestock and ns:KnowsAny(ns.SPELLS.VANISH)) then
        restockPending = false
        return
    end
    if job then return end
    local itemID = ns.ITEM.FLASH_POWDER
    local s = MerchantStock()[itemID]
    if not s then return end
    restockPending = false
    local missing = db.flashRestockTo - Count(itemID)
    if missing <= 0 then return end
    local bundles = math.ceil(missing / s.step)
    if s.available >= 0 then bundles = math.min(bundles, s.available) end
    if bundles <= 0 then return end
    if s.price > 0 then
        bundles = math.min(bundles, math.floor(GetMoney() / s.price))
        if bundles <= 0 then
            ns:Print(L["RESTOCK_NO_GOLD"])
            return
        end
    end
    local quantity = bundles * s.step
    ns:Print(L["RESTOCK_FLASH"]:format(quantity))
    RunOrders({ { itemID = itemID, index = s.index, chunk = s.chunk, quantity = quantity } })
end

local function HideTooltipOf(button)
    if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
end

local function IsPurchaseError(message)
    for _, key in ipairs(PURCHASE_ERRORS) do
        if message ~= nil and message == _G[key] then return true end
    end
    return false
end

local function ShowPlanTooltip(button)
    local orders, _, short = CurrentPlan(button.mode)
    if not orders then
        HideTooltipOf(button)
        return
    end
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    if short then
        GameTooltip:AddLine(L["BUY_OUT_OF_STOCK"], 1, 0.3, 0.3)
    elseif #orders == 0 then
        GameTooltip:AddLine(L["BUY_ENOUGH"], 1, 1, 1)
    else
        for _, order in ipairs(orders) do
            local name = C_Item.GetItemNameByID(order.itemID)
            if not name then
                RequestItem(order.itemID)
                name = "item:" .. order.itemID
            end
            GameTooltip:AddDoubleLine(name, "x" .. order.quantity, 1, 1, 1, 1, 1, 1)
        end
    end
    GameTooltip:Show()
end

local function CreateRow(mode, index)
    local box = CreateFrame("EditBox", nil, panel, "NumericInputSpinnerTemplate")
    box.clampIfInputExceedsRange = true
    box.highlightIfInputExceedsRange = true
    box:SetMaxLetters(2)
    box:SetJustifyH("CENTER")
    box:SetPoint("LEFT", panel, "BOTTOMLEFT", BOX_LEFT, (#MODES - index + 0.5) * ROW_HEIGHT)
    box:SetMinMaxValues(1, MAX_AMOUNT)
    box:SetOnValueChangedCallback(function(_, value)
        if value == ns.db.profile.buyAmount[mode] then return end
        ns.db.profile.buyAmount[mode] = value
        M:Update()
    end)
    box:SetScript("OnEnterPressed", EditBox_ClearFocus)

    local unit = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    unit:SetPoint("LEFT", box.IncrementButton, "RIGHT", 3, 0)

    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetSize(52, 22)
    button:SetMotionScriptsWhileDisabled(true)
    button.mode = mode
    button:SetScript("OnClick", function(self)
        for _, row in pairs(panel.rows) do row.box:ClearFocus() end
        StartJob(self.mode)
    end)
    button:SetScript("OnEnter", ShowPlanTooltip)
    button:SetScript("OnLeave", GameTooltip_Hide)

    local cost = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cost:SetPoint("LEFT", button, "RIGHT", 6, 0)

    panel.rows[mode] = { box = box, unit = unit, button = button, cost = cost }
end

local function CreatePanel()
    local page = ProfessionsFrame.CraftingPage
    panel = CreateFrame("Frame", nil, page)
    panel:SetSize(1, #MODES * ROW_HEIGHT)
    panel:SetPoint("BOTTOMLEFT", page.CreateAllButton, "TOPLEFT", 0, 2)
    panel.rows = {}
    for index, mode in ipairs(MODES) do
        CreateRow(mode, index)
    end
    panel:Hide()
    hooksecurefunc(page.SchematicForm, "Init", function() M:Update() end)
    page:HookScript("OnShow", function() M:Update() end)
end

function M:Update()
    if not panel then return end
    local recipe, stock = Context()
    panel:SetShown(recipe ~= nil)
    if not recipe then
        for _, row in pairs(panel.rows) do HideTooltipOf(row.button) end
        return
    end
    local db = ns.db.profile
    local unitWidth = 0
    for _, mode in ipairs(MODES) do
        local row = panel.rows[mode]
        row.unit:SetText(L[UNIT_KEY[mode]])
        unitWidth = math.max(unitWidth, row.unit:GetStringWidth() or 0)
    end
    for _, mode in ipairs(MODES) do
        local row = panel.rows[mode]
        row.box:SetValue(db.buyAmount[mode])
        row.button:SetText(L["BUY_BUTTON"])
        row.button:ClearAllPoints()
        row.button:SetPoint("LEFT", row.unit, "LEFT", unitWidth + 4, 0)
        local orders, cost, short = PlanFor(recipe, stock, mode)
        local priced = orders ~= nil and not short and #orders > 0
        local affordable = priced and GetMoney() >= cost
        if priced then
            local text = C_CurrencyInfo.GetCoinTextureString(cost)
            row.cost:SetText(affordable and text or (text .. "  " .. L["BUY_NO_GOLD"]))
            row.cost:SetTextColor(1, affordable and 1 or 0.3, affordable and 1 or 0.3)
        else
            row.cost:SetText("")
        end
        row.button:SetEnabled(job == nil and affordable)
        if GameTooltip:IsOwned(row.button) then ShowPlanTooltip(row.button) end
    end
end

function M:Refresh()
    self:Update()
end

local function OnEvent(_, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 == PROFESSIONS_ADDON and not panel then CreatePanel() end
    elseif event == "MERCHANT_SHOW" then
        merchantOpen = true
        restockPending = true
        Restock()
        M:Update()
    elseif event == "MERCHANT_CLOSED" then
        merchantOpen = false
        restockPending = false
        if job then FinishJob(true) else M:Update() end
    elseif event == "ITEM_DATA_LOAD_RESULT" then
        if loading[arg1] and arg2 then
            loading[arg1] = nil
            if panel and panel:IsShown() then M:Update() end
        end
    elseif event == "UI_ERROR_MESSAGE" then
        if job and IsPurchaseError(arg2) then FinishJob(true) end
    elseif event == "MERCHANT_UPDATE" then
        if job and job.index and GetMerchantItemID(job.index) ~= job.itemID then
            FinishJob(true)
        else
            if restockPending then Restock() end
            M:Update()
        end
    elseif event == "BAG_UPDATE_DELAYED" then
        if job and Count(job.itemID) > job.before then
            NextPurchase()
        else
            M:Update()
        end
    else
        M:Update()
    end
end

function M:OnPlayerLogin()
    local events = CreateFrame("Frame")
    events:RegisterEvent("ADDON_LOADED")
    events:RegisterEvent("MERCHANT_SHOW")
    events:RegisterEvent("MERCHANT_CLOSED")
    events:RegisterEvent("MERCHANT_UPDATE")
    events:RegisterEvent("BAG_UPDATE_DELAYED")
    events:RegisterEvent("UI_ERROR_MESSAGE")
    events:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    events:RegisterEvent("PLAYER_MONEY")
    events:SetScript("OnEvent", OnEvent)
    if C_AddOns.IsAddOnLoaded(PROFESSIONS_ADDON) then CreatePanel() end
end
