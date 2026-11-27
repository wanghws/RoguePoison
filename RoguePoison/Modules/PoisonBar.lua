local addonName, ns = ...
local L = ns.L

local M = {}
ns:RegisterModule("poisonBar", M)

local MAIN_HAND = INVSLOT_MAINHAND or 16
local OFF_HAND  = INVSLOT_OFFHAND or 17
local HANDS = {
    { slot = MAIN_HAND, label = "TIP_MAIN_HAND", click = "TIP_LEFT_CLICK",  binding = "ApplyMain" },
    { slot = OFF_HAND,  label = "TIP_OFF_HAND",  click = "TIP_RIGHT_CLICK", binding = "ApplyOff" },
}
local ENCHANT_SLOT = {
    [MAIN_HAND] = Enum.WeaponSlot.MainHand,
    [OFF_HAND]  = Enum.WeaponSlot.OffHand,
}
local KINDS = { "poison", "stone" }
local WEAPON_CLASS = Enum.ItemClass.Weapon
local SUBCLASS = Enum.ItemWeaponSubclass
local BLADED = {
    [SUBCLASS.Axe1H]   = true,
    [SUBCLASS.Axe2H]   = true,
    [SUBCLASS.Sword1H] = true,
    [SUBCLASS.Sword2H] = true,
    [SUBCLASS.Polearm] = true,
    [SUBCLASS.Dagger]  = true,
}
local BLUNT = {
    [SUBCLASS.Mace1H]  = true,
    [SUBCLASS.Mace2H]  = true,
    [SUBCLASS.Staff]   = true,
    [SUBCLASS.Unarmed] = true,
}
local MELEE = {}
for subclassID in pairs(BLADED) do MELEE[subclassID] = true end
for subclassID in pairs(BLUNT) do MELEE[subclassID] = true end
local FITS = { bladed = BLADED, blunt = BLUNT, melee = MELEE }
local FALLBACK_ICON = 134400
local TICK_SECONDS = 1
local SMALL_TEXT_SCALE = 0.75
local ALERT_COLOR = "|cffff4d4d"

local REAGENTS = {
    {
        name      = "FlashPowder",
        itemID    = ns.ITEM.FLASH_POWDER,
        spells    = ns.SPELLS.VANISH,
        trackKey  = "trackFlash",
        threshKey = "flashThreshold",
    },
    {
        name      = "BlindingPowder",
        itemID    = ns.ITEM.BLINDING_POWDER,
        spells    = ns.SPELLS.BLIND,
        trackKey  = "trackBlind",
        threshKey = "blindThreshold",
    },
}

local container, mover
local buttons = {}
local reagentIcons = {}
local reagentTracked = {}
local entries = {}
local slotStates = {}
local needs = { [MAIN_HAND] = {}, [OFF_HAND] = {} }
local lastKnown = {}
local bindButtons = {}
local pendingSecure = false

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

local function RawCount(itemID)
    return C_Item.GetItemCount(itemID) or 0
end

local function Count(itemID)
    local total = 0
    for _, id in ipairs(ns.SAME_RANK[itemID] or { itemID }) do
        total = total + RawCount(id)
    end
    return total
end

local function InStock(itemID)
    for _, id in ipairs(ns.SAME_RANK[itemID] or { itemID }) do
        if RawCount(id) > 0 then return id end
    end
    return nil
end

local function IsLow(db, count, threshold)
    return db.showWarnings and count < threshold
end

local function ReadSlot(slot)
    local itemID = GetInventoryItemID("player", slot)
    if not itemID then return nil end
    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    if classID ~= WEAPON_CLASS then return nil end
    local state = { itemID = itemID, subclassID = subclassID, takes = {}, enchants = {} }
    for _, entry in ipairs(entries) do
        local poison = ns.ITEM_TYPE[entry]
        if poison.fits == "any" or FITS[poison.fits][subclassID] then state.takes[poison.kind] = true end
    end
    local list = C_Item.GetWeaponEnchantInfo(ENCHANT_SLOT[slot])
    if type(list) ~= "table" then return state end
    for _, e in ipairs(list) do
        if IsSecret(e.hasEnchant) or IsSecret(e.timeLeft) or IsSecret(e.charges) or IsSecret(e.enchantID) then
            state.unknown = true
            return state
        end
        local kind = ns.ENCHANT_KIND[e.enchantID]
        if kind and e.hasEnchant and e.timeLeft and e.timeLeft > 0 then
            local charges = e.charges or 0
            state.enchants[kind] = state.enchants[kind]
                or { timeLeft = e.timeLeft, charges = charges, type = ns.ENCHANT_TYPE[e.enchantID] }
        end
    end
    return state
end

local function KnownState(slot)
    local state = slotStates[slot]
    if state and not state.unknown then return state end
    return nil
end

local function ExpiringMs(enchant, db)
    local ms = enchant and enchant.timeLeft
    if db.timeThreshold > 0 and ms and ms < db.timeThreshold * 60000 then
        return ms
    end
    return nil
end

local function KindNeeded(enchant, kind, db)
    if not enchant then return true end
    if ExpiringMs(enchant, db) then return true end
    return kind == "poison" and db.chargesThreshold > 0 and enchant.charges > 0
        and enchant.charges < db.chargesThreshold
end

local function CanApply(slot, itemID)
    local state = slotStates[slot]
    if not state then return false end
    local poison = ns.ITEM_TYPE[itemID]
    return poison.fits == "any" or FITS[poison.fits][state.subclassID] == true
end

local function NeededBy(itemID)
    local kind = ns.ITEM_KIND[itemID]
    for _, hand in ipairs(HANDS) do
        if needs[hand.slot][kind] and CanApply(hand.slot, itemID) then return true end
    end
    return false
end

local function SlotExpiringMs(slot, db)
    local state = KnownState(slot)
    if not state then return nil end
    local soonest
    for kind, enchant in pairs(state.enchants) do
        local ms = state.takes[kind] and ExpiringMs(enchant, db)
        if ms and (not soonest or ms < soonest) then soonest = ms end
    end
    return soonest
end

local function FormatTime(ms)
    local secs = math.floor(ms / 1000)
    return ("%d:%02d"):format(math.floor(secs / 60), secs % 60)
end

local function SmallFontSize(db)
    return math.max(8, math.floor(db.fontSize * SMALL_TEXT_SCALE))
end

local function ApplyFont(fontString, size)
    local path = NumberFontNormal:GetFont()
    fontString:SetFont(path, size, "OUTLINE")
end

local function SlotStatus(slot, kind)
    local state = KnownState(slot)
    if not (state and state.takes[kind]) then return nil end
    local enchant = state.enchants[kind]
    if not enchant then
        return kind == "stone" and L["TIP_NO_STONE"] or L["TIP_NO_POISON"], true
    end
    local parts = { FormatTime(enchant.timeLeft) }
    if enchant.charges > 0 then
        parts[#parts + 1] = L["TIP_CHARGES"]:format(enchant.charges)
    end
    return table.concat(parts, "  "), false
end

local function AddSection(lines)
    if #lines == 0 then return end
    GameTooltip:AddLine(" ")
    for _, line in ipairs(lines) do line() end
end

local function ButtonOnEnter(self)
    if not self.itemID then return end
    local kind = ns.ITEM_KIND[self.itemID]
    local usable = Count(self.itemID) > 0
    local status, clicks = {}, {}
    for _, hand in ipairs(HANDS) do
        local text, missing
        if CanApply(hand.slot, self.itemID) then text, missing = SlotStatus(hand.slot, kind) end
        if text then
            local shade = missing and 0.3 or 1
            status[#status + 1] = function()
                GameTooltip:AddDoubleLine(L[hand.label], text, 1, 1, 1, 1, shade, shade)
            end
        end
        if usable and CanApply(hand.slot, self.itemID) then
            clicks[#clicks + 1] = function() GameTooltip:AddLine(L[hand.click], 0.3, 1, 0.3) end
        end
    end
    local craft = {}
    local better = ns:BetterCraftable(self.itemID)
    local betterName = better and C_Item.GetItemNameByID(better)
    if better and not betterName then C_Item.RequestLoadItemDataByID(better) end
    if betterName then
        craft[1] = function() GameTooltip:AddLine(L["TIP_CRAFT_HIGHER"]:format(betterName), 1, 0.82, 0) end
    end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetItemByID(self.itemID)
    AddSection(status)
    AddSection(craft)
    AddSection(clicks)
    GameTooltip:Show()
end

local function ReagentOnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetItemByID(self.itemID)
    GameTooltip:Show()
end

local function IconOnLeave()
    GameTooltip:Hide()
end

local function DecorateIcon(f)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", -1, 1)
    bg:SetPoint("BOTTOMRIGHT", 1, -1)
    bg:SetColorTexture(0, 0, 0, 0.85)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    f.count = f:CreateFontString(nil, "OVERLAY")
    f.count:SetPoint("BOTTOMRIGHT", -2, 2)

    f.low = f:CreateFontString(nil, "OVERLAY")
    f.low:SetPoint("TOP", f, "BOTTOM", 0, -3)
    f.low:SetJustifyH("CENTER")
    f.low:SetWordWrap(true)
    f.low:SetTextColor(1, 0.3, 0.3)
end

local function PlaceIcon(f, index, size, spacing)
    f:SetSize(size, size)
    f:ClearAllPoints()
    f:SetPoint("LEFT", container, "LEFT", (index - 1) * (size + spacing), 0)
    f.low:SetWidth(size + spacing)
end

local function PaintIcon(f, count, threshold, db)
    local low = IsLow(db, count, threshold)
    ApplyFont(f.count, db.fontSize)
    f.count:SetText(count)
    if low then
        f.count:SetTextColor(1, 0.3, 0.3)
    else
        f.count:SetTextColor(1, 1, 1)
    end
    f.icon:SetDesaturated(count == 0)
    ApplyFont(f.low, SmallFontSize(db))
    f.low:SetText(low and L["WARN_LOW_STOCK"] or "")
    return low
end

local function GetButton(index)
    local b = buttons[index]
    if b then return b end
    b = CreateFrame("Button", nil, container, "SecureActionButtonTemplate")
    b:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonDown", "RightButtonUp")
    DecorateIcon(b)
    b:SetHighlightTexture([[Interface\Buttons\ButtonHilight-Square]], "ADD")
    b:SetScript("OnEnter", ButtonOnEnter)
    b:SetScript("OnLeave", IconOnLeave)
    buttons[index] = b
    return b
end

local function SetMacro(b, suffix, itemID, slot)
    b:SetAttribute("type" .. suffix, itemID and "macro" or nil)
    b:SetAttribute("macrotext" .. suffix, itemID and ("/use item:%d\n/use %d"):format(itemID, slot) or nil)
end

local function SetClickActions(b, itemID)
    local usable = Count(itemID) > 0
    for button, hand in ipairs(HANDS) do
        SetMacro(b, button, usable and CanApply(hand.slot, itemID) and itemID or nil, hand.slot)
    end
end

local function BestInBags(poison)
    for _, itemID in ipairs(poison.ranks) do
        local inStock = InStock(itemID)
        if inStock then return inStock end
    end
    return nil
end

local function BindingItem(slot)
    if not slotStates[slot] then return nil end
    local key = ns.db.char.lastPoison[slot]
    local remembered = key and ns.TYPE_BY_KEY[key]
    if remembered then return BestInBags(remembered) end
    for _, itemID in ipairs(entries) do
        if ns.ITEM_KIND[itemID] == "poison" and Count(itemID) > 0 then return itemID end
    end
    return nil
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

    container.hint = container:CreateFontString(nil, "OVERLAY")
    container.hint:SetPoint("BOTTOM", container, "TOP", 0, 3)
    container.hint:SetTextColor(0.9, 0.9, 0.9)

    container.timer = container:CreateFontString(nil, "OVERLAY")
    container.timer:SetPoint("TOP", container, "BOTTOM", 0, -3)
    container.timer:SetTextColor(1, 0.82, 0)

    for i, reagent in ipairs(REAGENTS) do
        local icon = CreateFrame("Frame", addonName .. reagent.name, container)
        DecorateIcon(icon)
        icon.itemID = reagent.itemID
        icon.icon:SetTexture(C_Item.GetItemIconByID(reagent.itemID) or FALLBACK_ICON)
        icon:EnableMouse(true)
        icon:SetScript("OnEnter", ReagentOnEnter)
        icon:SetScript("OnLeave", IconOnLeave)
        icon:Hide()
        reagentIcons[i] = icon
    end

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

    for _, hand in ipairs(HANDS) do
        local b = CreateFrame("Button", addonName .. hand.binding, UIParent, "SecureActionButtonTemplate")
        b:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
        b:Hide()
        bindButtons[hand.slot] = b
    end
end

local function ResolveRank(poison, seen)
    local seenItem = seen[poison.key]
    local seenIndex = seenItem and ns.ITEM_TYPE[seenItem] == poison and ns.RANK_INDEX[seenItem]
    for index, rankItem in ipairs(poison.ranks) do
        local itemID = InStock(rankItem)
        if itemID then
            if not seenIndex or index < seenIndex then
                seen[poison.key] = itemID
            end
            return itemID
        end
    end
    return seenIndex and seenItem or nil
end

function M:Scan()
    local db, seen = ns.db.profile, ns.db.char.seen
    wipe(entries)
    for _, poison in ipairs(ns.POISON_TYPES) do
        if db.poisons[poison.key] then
            local itemID = ResolveRank(poison, seen)
            if itemID then
                entries[#entries + 1] = itemID
            end
        end
    end
    for i, reagent in ipairs(REAGENTS) do
        reagentTracked[i] = db[reagent.trackKey] and ns:KnowsAny(reagent.spells)
    end
end

local function DetectExpiry(db)
    local expired = false
    for _, hand in ipairs(HANDS) do
        local slot, state = hand.slot, slotStates[hand.slot]
        if not state then
            lastKnown[slot] = nil
        elseif not state.unknown then
            local prev = lastKnown[slot]
            if prev and prev.itemID == state.itemID then
                for kind in pairs(prev.kinds) do
                    if state.takes[kind] and not state.enchants[kind] then expired = true end
                end
            end
            local kinds = {}
            for kind in pairs(state.enchants) do kinds[kind] = true end
            lastKnown[slot] = { itemID = state.itemID, kinds = kinds }
        end
    end
    if expired and db.enabled and db.expireSound then PlaySound(SOUNDKIT.RAID_WARNING) end
end

local function RememberPoisons()
    local remembered = ns.db.char.lastPoison
    local changed = false
    for _, hand in ipairs(HANDS) do
        local state = KnownState(hand.slot)
        local poison = state and state.enchants.poison
        local key = poison and poison.type.key
        if key and remembered[hand.slot] ~= key then
            remembered[hand.slot] = key
            changed = true
        end
    end
    return changed
end

function M:EvaluateNeeds()
    local db = ns.db.profile
    for _, hand in ipairs(HANDS) do
        slotStates[hand.slot] = ReadSlot(hand.slot)
    end
    DetectExpiry(db)
    local changed = RememberPoisons()
    for _, hand in ipairs(HANDS) do
        local state = KnownState(hand.slot)
        for _, kind in ipairs(KINDS) do
            local need = state ~= nil and state.takes[kind] == true and KindNeeded(state.enchants[kind], kind, db)
            if needs[hand.slot][kind] ~= need then
                needs[hand.slot][kind] = need
                changed = true
            end
        end
    end
    return changed
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
    local preview = not db.locked
    local resting = IsResting()

    container:ClearAllPoints()
    container:SetPoint(anchor.point, UIParent, anchor.relativePoint, anchor.x, anchor.y)

    local items = {}
    for _, itemID in ipairs(entries) do
        local count = Count(itemID)
        if preview or IsLow(db, count, db.poisonThreshold) or (not resting and count > 0 and NeededBy(itemID)) then
            items[#items + 1] = itemID
        end
    end
    if preview and #items == 0 then
        for _, poison in ipairs(ns.POISON_TYPES) do
            if db.poisons[poison.key] then items[#items + 1] = poison.ranks[1] end
        end
    end

    local clickMain, clickOff = false, false
    for i, itemID in ipairs(items) do
        if Count(itemID) > 0 then
            clickMain = clickMain or CanApply(MAIN_HAND, itemID)
            clickOff = clickOff or CanApply(OFF_HAND, itemID)
        end
        local b = GetButton(i)
        PlaceIcon(b, i, size, spacing)
        SetClickActions(b, itemID)
        b.itemID = itemID
        b.icon:SetTexture(C_Item.GetItemIconByID(itemID) or FALLBACK_ICON)
        b:Show()
    end
    for i = #items + 1, #buttons do
        buttons[i].itemID = nil
        buttons[i]:Hide()
    end
    for _, hand in ipairs(HANDS) do
        SetMacro(bindButtons[hand.slot], "", db.enabled and BindingItem(hand.slot) or nil, hand.slot)
    end

    local shownCount = #items
    for i, reagent in ipairs(REAGENTS) do
        local icon = reagentIcons[i]
        local show = reagentTracked[i] and (preview or IsLow(db, Count(reagent.itemID), db[reagent.threshKey]))
        if show then
            shownCount = shownCount + 1
            PlaceIcon(icon, shownCount, size, spacing)
        end
        icon:SetShown(show)
    end

    local width = math.max(shownCount, 1) * size + math.max(shownCount - 1, 0) * spacing
    container:SetSize(width, size)
    ApplyFont(container.hint, SmallFontSize(db))
    if preview or not (clickMain or clickOff) then
        container.hint:SetText("")
    elseif clickMain and clickOff then
        container.hint:SetText(L["HINT_CLICK_BOTH"])
    else
        container.hint:SetText(clickMain and L["HINT_CLICK_MAIN"] or L["HINT_CLICK_OFF"])
    end
    mover.label:SetText(L["MOVER_LABEL"])
    mover:SetShown(preview and db.enabled)
    container:SetShown(db.enabled and shownCount > 0)
end

local function HandSummary(slot, db)
    local state = slotStates[slot]
    if not state then return nil end
    if state.unknown then return "?" end
    local soonest, needed
    for _, kind in ipairs(KINDS) do
        if state.takes[kind] then
            local enchant = state.enchants[kind]
            if not enchant then return ALERT_COLOR .. "-|r" end
            needed = needed or KindNeeded(enchant, kind, db)
            if not soonest or enchant.timeLeft < soonest then soonest = enchant.timeLeft end
        end
    end
    if not soonest then return nil end
    local text = L["BROKER_MINUTES"]:format(math.ceil(soonest / 60000))
    return needed and (ALERT_COLOR .. text .. "|r") or text
end

function M:UpdateBroker()
    local broker = ns._broker
    if not broker then return end
    local db = ns.db.profile
    local parts = {}
    if db.enabled then
        for _, hand in ipairs(HANDS) do
            local text = HandSummary(hand.slot, db)
            if text then parts[#parts + 1] = L[hand.label] .. " " .. text end
        end
    end
    broker.text = table.concat(parts, "  ")
end

function ns:AddWeaponStatus(tip)
    local added = false
    for _, hand in ipairs(HANDS) do
        for _, kind in ipairs(KINDS) do
            local text, missing = SlotStatus(hand.slot, kind)
            if text then
                local enchant = not missing and slotStates[hand.slot].enchants[kind]
                if enchant then text = L["POISON_" .. enchant.type.key] .. "  " .. text end
                local shade = missing and 0.3 or 1
                tip:AddDoubleLine(L[hand.label], text, 1, 1, 1, 1, shade, shade)
                added = true
            end
        end
    end
    return added
end

function M:OnReadyCheck()
    local db = ns.db.profile
    if not (db.enabled and db.readyCheck) then return end
    self:OnTick()
    local parts = {}
    for _, hand in ipairs(HANDS) do
        local state = KnownState(hand.slot)
        local statuses = {}
        for _, kind in ipairs(KINDS) do
            if state and state.takes[kind] and KindNeeded(state.enchants[kind], kind, db) then
                statuses[#statuses + 1] = SlotStatus(hand.slot, kind)
            end
        end
        if #statuses > 0 then parts[#parts + 1] = L[hand.label] .. " " .. table.concat(statuses, " / ") end
    end
    if #parts == 0 then return end
    local text = L["READY_CHECK_WARN"]:format(table.concat(parts, "  "))
    RaidWarningUtil.AddMessage(text, ChatTypeInfo.RAID_WARNING)
    PlaySound(SOUNDKIT.RAID_WARNING)
    ns:Print(text)
end

function M:UpdateTimer()
    self:UpdateBroker()
    local db = ns.db.profile
    ApplyFont(container.timer, SmallFontSize(db))
    if not db.locked or IsResting() then
        container.timer:SetText("")
        return
    end
    local parts = {}
    local mhMs = SlotExpiringMs(MAIN_HAND, db)
    if mhMs then parts[#parts + 1] = L["TIP_MAIN_HAND"] .. " " .. FormatTime(mhMs) end
    local ohMs = SlotExpiringMs(OFF_HAND, db)
    if ohMs then parts[#parts + 1] = L["TIP_OFF_HAND"] .. " " .. FormatTime(ohMs) end
    container.timer:SetText(table.concat(parts, "  "))
end

function M:UpdateTexts()
    local db = ns.db.profile
    local smallSize = SmallFontSize(db)
    local maxLowHeight = 0
    for _, b in ipairs(buttons) do
        if b.itemID then
            local low = PaintIcon(b, Count(b.itemID), db.poisonThreshold, db)
            if low then
                local h = b.low:GetStringHeight() or 0
                maxLowHeight = math.max(maxLowHeight, h > 0 and h or smallSize)
            end
        end
    end
    for i, reagent in ipairs(REAGENTS) do
        local icon = reagentIcons[i]
        local low = PaintIcon(icon, Count(reagent.itemID), db[reagent.threshKey], db)
        if icon:IsShown() and low then
            local h = icon.low:GetStringHeight() or 0
            maxLowHeight = math.max(maxLowHeight, h > 0 and h or smallSize)
        end
    end
    if not InCombatLockdown() then
        local yOffset = maxLowHeight > 0 and -(maxLowHeight + 6) or -3
        container.timer:ClearAllPoints()
        container.timer:SetPoint("TOP", container, "BOTTOM", 0, yOffset)
    end
    self:UpdateTimer()
end

function M:Refresh()
    if not ns.active then return end
    self:Scan()
    self:EvaluateNeeds()
    self:ApplySecure()
    self:UpdateTexts()
end

function M:OnTick()
    if self:EvaluateNeeds() then
        self:ApplySecure()
        self:UpdateTexts()
    else
        self:UpdateTimer()
    end
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
    events:RegisterEvent("PLAYER_UPDATE_RESTING")
    events:RegisterEvent("READY_CHECK")
    events:SetScript("OnEvent", function(_, event)
        if event == "WEAPON_ENCHANT_CHANGED" then
            M:OnTick()
        elseif event == "READY_CHECK" then
            M:OnReadyCheck()
        elseif event == "PLAYER_ENTERING_WORLD" then
            wipe(lastKnown)
            M:Refresh()
        elseif event == "PLAYER_REGEN_ENABLED" then
            if pendingSecure then M:Refresh() end
        else
            M:Refresh()
        end
    end)

    C_Timer.NewTicker(TICK_SECONDS, function() M:OnTick() end)
end
