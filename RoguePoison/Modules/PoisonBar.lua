local addonName, ns = ...
local L = ns.L

local M = {}
ns:RegisterModule("poisonBar", M)

local MAIN_HAND = INVSLOT_MAINHAND or 16
local OFF_HAND  = INVSLOT_OFFHAND or 17
local WEAPON_CLASS = Enum.ItemClass.Weapon
local VANISH_RANKS = { 1856, 1857 }
local FALLBACK_ICON = 134400
local TICK_SECONDS = 1

local container, mover, warning
local buttons = {}
local entries = {}
local shortages = {}
local needsPoison = false
local pendingSecure = false

local function Readable(v)
    return v ~= nil and not (issecretvalue and issecretvalue(v))
end

local function Count(itemID)
    return C_Item.GetItemCount(itemID) or 0
end

local function HasWeapon(slot)
    local itemID = GetInventoryItemID("player", slot)
    if not itemID then return false end
    local classID = select(6, C_Item.GetItemInfoInstant(itemID))
    return classID == WEAPON_CLASS
end

local function SlotNeedsPoison(slot, db)
    if not HasWeapon(slot) then return false end
    local info = C_PaperDollInfo.GetTemporaryEnchantmentInfo(slot)
    if not info then return true end
    local ms, charges = info.remainingTimeMs, info.chargesRemaining
    if db.timeThreshold > 0 and Readable(ms) and ms > 0 and ms < db.timeThreshold * 60000 then
        return true
    end
    if db.chargesThreshold > 0 and Readable(charges) and charges > 0 and charges < db.chargesThreshold then
        return true
    end
    return false
end

local function KnowsVanish()
    for _, spellID in ipairs(VANISH_RANKS) do
        if IsPlayerSpell(spellID) then return true end
    end
    return false
end

local function FormatTime(ms)
    local secs = math.floor(ms / 1000)
    return ("%d:%02d"):format(math.floor(secs / 60), secs % 60)
end

local function ItemLabel(itemID)
    local name = C_Item.GetItemNameByID(itemID)
    if not name then C_Item.RequestLoadItemDataByID(itemID) end
    return ("|T%s:0|t%s"):format(C_Item.GetItemIconByID(itemID) or FALLBACK_ICON, name or "")
end

local function ApplyFont(fontString, size)
    local path = NumberFontNormal:GetFont()
    fontString:SetFont(path, size, "OUTLINE")
end

local function AddSlotLine(label, slot)
    local info = C_PaperDollInfo.GetTemporaryEnchantmentInfo(slot)
    if not info then
        GameTooltip:AddDoubleLine(label, L["TIP_NO_POISON"], 1, 1, 1, 1, 0.3, 0.3)
        return
    end
    local parts = {}
    if Readable(info.remainingTimeMs) and info.remainingTimeMs > 0 then
        parts[#parts + 1] = FormatTime(info.remainingTimeMs)
    end
    if Readable(info.chargesRemaining) and info.chargesRemaining > 0 then
        parts[#parts + 1] = L["TIP_CHARGES"]:format(info.chargesRemaining)
    end
    GameTooltip:AddDoubleLine(label, table.concat(parts, "  "), 1, 1, 1, 1, 1, 1)
end

local function ButtonOnEnter(self)
    if not self.itemID then return end
    local hasOffHand = HasWeapon(OFF_HAND)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetItemByID(self.itemID)
    GameTooltip:AddLine(" ")
    AddSlotLine(L["TIP_MAIN_HAND"], MAIN_HAND)
    if hasOffHand then AddSlotLine(L["TIP_OFF_HAND"], OFF_HAND) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["TIP_LEFT_CLICK"], 0.3, 1, 0.3)
    if hasOffHand then GameTooltip:AddLine(L["TIP_RIGHT_CLICK"], 0.3, 1, 0.3) end
    GameTooltip:Show()
end

local function ButtonOnLeave()
    GameTooltip:Hide()
end

local function GetButton(index)
    local b = buttons[index]
    if b then return b end
    b = CreateFrame("Button", nil, container, "SecureActionButtonTemplate")
    b:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonDown", "RightButtonUp")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", -1, 1)
    bg:SetPoint("BOTTOMRIGHT", 1, -1)
    bg:SetColorTexture(0, 0, 0, 0.85)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    b.count = b:CreateFontString(nil, "OVERLAY")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)

    b:SetHighlightTexture([[Interface\Buttons\ButtonHilight-Square]], "ADD")
    b:SetScript("OnEnter", ButtonOnEnter)
    b:SetScript("OnLeave", ButtonOnLeave)
    buttons[index] = b
    return b
end

local function SaveAnchor()
    local point, _, relativePoint, x, y = container:GetPoint(1)
    local anchor = ns.db.profile.anchor
    anchor.point = point
    anchor.relativePoint = relativePoint
    anchor.x = math.floor(x + 0.5)
    anchor.y = math.floor(y + 0.5)
    if ns.RefreshOptionsUI then ns:RefreshOptionsUI() end
end

local function CreateFrames()
    local combatHider = CreateFrame("Frame", nil, UIParent)
    RegisterStateDriver(combatHider, "visibility", "[combat] hide; show")

    container = CreateFrame("Frame", addonName .. "Bar", combatHider)
    container:SetMovable(true)
    container:SetClampedToScreen(true)
    container:SetDontSavePosition(true)
    container:Hide()

    mover = CreateFrame("Frame", nil, container)
    mover:SetAllPoints()
    mover:SetFrameLevel(container:GetFrameLevel() + 20)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    local tint = mover:CreateTexture(nil, "OVERLAY")
    tint:SetAllPoints()
    tint:SetColorTexture(0.2, 0.8, 0.2, 0.35)
    mover.label = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    mover.label:SetPoint("BOTTOM", mover, "TOP", 0, 2)
    mover:SetScript("OnDragStart", function()
        if InCombatLockdown() or ns.db.profile.locked then return end
        container:StartMoving()
    end)
    mover:SetScript("OnDragStop", function()
        container:StopMovingOrSizing()
        SaveAnchor()
    end)
    mover:Hide()

    warning = CreateFrame("Frame", nil, combatHider)
    warning:SetSize(1, 1)
    warning:SetPoint("TOP", container, "BOTTOM", 0, -6)
    warning.text = warning:CreateFontString(nil, "OVERLAY")
    warning.text:SetPoint("TOP")
    warning:Hide()
end

local function ResolveRank(poison, seen)
    local seenItem = seen[poison.key]
    local seenIndex = seenItem and ns.RANK_INDEX[seenItem]
    for index, itemID in ipairs(poison.ranks) do
        if Count(itemID) > 0 then
            if not seenIndex or index < seenIndex then
                seen[poison.key] = itemID
            end
            return itemID
        end
    end
    return seenIndex and seenItem or nil
end

local function AddShortage(itemID, threshold)
    local count = Count(itemID)
    if count < threshold then
        shortages[#shortages + 1] = { itemID = itemID, count = count }
    end
end

function M:Scan()
    local db, seen = ns.db.profile, ns.db.char.seen
    wipe(entries)
    wipe(shortages)
    for _, poison in ipairs(ns.POISON_TYPES) do
        if db.poisons[poison.key] then
            local itemID = ResolveRank(poison, seen)
            if itemID then
                entries[#entries + 1] = { itemID = itemID, count = Count(itemID) }
                AddShortage(itemID, db.poisonThreshold)
            end
        end
    end
    if db.trackFlash and KnowsVanish() then
        AddShortage(ns.ITEM.FLASH_POWDER, db.flashThreshold)
    end
end

function M:EvaluateNeeds()
    local db = ns.db.profile
    needsPoison = SlotNeedsPoison(MAIN_HAND, db) or SlotNeedsPoison(OFF_HAND, db)
end

local function ShouldShow(db, shownCount)
    if not db.enabled or shownCount == 0 then return false end
    return not db.locked or needsPoison
end

function M:ApplySecure()
    if InCombatLockdown() then
        pendingSecure = true
        return
    end
    pendingSecure = false

    local db = ns.db.profile
    local anchor = db.anchor
    local size, spacing = db.iconSize, db.spacing
    local offHandMacro = HasWeapon(OFF_HAND)
    local preview = not db.locked

    container:ClearAllPoints()
    container:SetPoint(anchor.point, UIParent, anchor.relativePoint, anchor.x, anchor.y)

    local items = {}
    for _, entry in ipairs(entries) do
        if entry.count > 0 or preview then items[#items + 1] = entry.itemID end
    end
    if preview and #items == 0 then
        for _, poison in ipairs(ns.POISON_TYPES) do
            if db.poisons[poison.key] then items[#items + 1] = poison.ranks[1] end
        end
    end

    local shownCount = #items
    for i, itemID in ipairs(items) do
        local b = GetButton(i)
        b:SetSize(size, size)
        b:ClearAllPoints()
        b:SetPoint("LEFT", container, "LEFT", (i - 1) * (size + spacing), 0)
        b:SetAttribute("type1", "macro")
        b:SetAttribute("macrotext1", ("/use item:%d\n/use %d"):format(itemID, MAIN_HAND))
        if offHandMacro then
            b:SetAttribute("type2", "macro")
            b:SetAttribute("macrotext2", ("/use item:%d\n/use %d"):format(itemID, OFF_HAND))
        else
            b:SetAttribute("type2", nil)
            b:SetAttribute("macrotext2", nil)
        end
        b.itemID = itemID
        b.icon:SetTexture(C_Item.GetItemIconByID(itemID) or FALLBACK_ICON)
        b:Show()
    end
    for i = shownCount + 1, #buttons do
        buttons[i].itemID = nil
        buttons[i]:Hide()
    end

    local width = math.max(shownCount, 1) * size + math.max(shownCount - 1, 0) * spacing
    container:SetSize(width, size)
    mover.label:SetText(L["MOVER_LABEL"])
    mover:SetShown(preview and db.enabled)
    container:SetShown(ShouldShow(db, shownCount))
    self.shownCount = shownCount
end

function M:UpdateTexts()
    local db = ns.db.profile
    for _, b in ipairs(buttons) do
        if b.itemID then
            local count = Count(b.itemID)
            ApplyFont(b.count, db.fontSize)
            b.count:SetText(count)
            if count < db.poisonThreshold then
                b.count:SetTextColor(1, 0.3, 0.3)
            else
                b.count:SetTextColor(1, 1, 1)
            end
            b.icon:SetDesaturated(count == 0)
        end
    end

    if not (db.enabled and db.showWarnings and #shortages > 0) then
        warning:Hide()
        return
    end
    local parts = {}
    for _, s in ipairs(shortages) do
        parts[#parts + 1] = ("%s |cffff5555%d|r"):format(ItemLabel(s.itemID), s.count)
    end
    ApplyFont(warning.text, db.fontSize)
    warning.text:SetTextColor(1, 0.82, 0)
    warning.text:SetText(L["WARN_LOW_STOCK"] .. " " .. table.concat(parts, "   "))
    warning:Show()
end

function M:Refresh()
    if not ns.active then return end
    self:Scan()
    self:EvaluateNeeds()
    self:ApplySecure()
    self:UpdateTexts()
end

function M:OnTick()
    local before = needsPoison
    self:EvaluateNeeds()
    if before == needsPoison then return end
    if InCombatLockdown() then
        pendingSecure = true
        return
    end
    container:SetShown(ShouldShow(ns.db.profile, self.shownCount or 0))
end

function M:OnPlayerLogin()
    CreateFrames()

    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("BAG_UPDATE_DELAYED")
    events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    events:RegisterEvent("WEAPON_ENCHANT_CHANGED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("SPELLS_CHANGED")
    events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    events:SetScript("OnEvent", function(_, event)
        if event == "WEAPON_ENCHANT_CHANGED" then
            M:OnTick()
        elseif event == "GET_ITEM_INFO_RECEIVED" then
            M:UpdateTexts()
        elseif event == "PLAYER_REGEN_ENABLED" then
            if pendingSecure then M:Refresh() end
        else
            M:Refresh()
        end
    end)

    C_Timer.NewTicker(TICK_SECONDS, function() M:OnTick() end)
end
