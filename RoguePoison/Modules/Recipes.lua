local _, ns = ...

local M = {}
ns:RegisterModule("recipes", M)

local checked = {}

local function Record(recipeID)
    local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
    if not info then return end
    local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
    local itemID = schematic and schematic.outputItemID
    if not (itemID and ns.ITEM_TYPE[itemID]) then
        checked[recipeID] = true
    elseif info.learned then
        ns.db.char.craftable[itemID] = true
        checked[recipeID] = true
    end
end

local function ViewingOwnProfession()
    return not (C_TradeSkillUI.IsTradeSkillLinked() or C_TradeSkillUI.IsTradeSkillGuild()
        or C_TradeSkillUI.IsTradeSkillGuildMember() or C_TradeSkillUI.IsNPCCrafting())
end

local function Scan()
    if not ViewingOwnProfession() then return end
    for _, recipeID in ipairs(C_TradeSkillUI.GetFilteredRecipeIDs() or {}) do
        if not checked[recipeID] then Record(recipeID) end
    end
end

function ns:BetterCraftable(itemID)
    local poison = ns.ITEM_TYPE[itemID]
    if not poison then return nil end
    local craftable = self.db.char.craftable
    for index = 1, ns.RANK_INDEX[itemID] - 1 do
        for _, better in ipairs(ns.SAME_RANK[poison.ranks[index]]) do
            if craftable[better] then return better end
        end
    end
    return nil
end

function M:OnPlayerLogin()
    local events = CreateFrame("Frame")
    events:RegisterEvent("TRADE_SKILL_SHOW")
    events:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
    events:RegisterEvent("NEW_RECIPE_LEARNED")
    events:SetScript("OnEvent", function(_, event, recipeID)
        if event == "NEW_RECIPE_LEARNED" then
            Record(recipeID)
        else
            Scan()
        end
    end)
end
