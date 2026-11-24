local addonName, ns = ...
local L = ns.L

local M = {}
ns:RegisterModule("poisonBar", M)

local MAIN_HAND = INVSLOT_MAINHAND or 16
local OFF_HAND  = INVSLOT_OFFHAND or 17
local HANDS = {
    { slot = MAIN_HAND, label = "TIP_MAIN_HAND", click = "TIP_LEFT_CLICK" },
    { slot = OFF_HAND,  label = "TIP_OFF_HAND",  click = "TIP_RIGHT_CLICK" },
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
local FALLBACK_ICON = 134400
local TICK_SECONDS = 1
local SMALL_TEXT_SCALE = 0.75

local REAGENTS = {
    {
        name      = "FlashPowder",
        itemID    = ns.ITEM.FLASH_POWDER,
        spells    = { 1856, 1857 },
        trackKey  = "trackFlash",
        threshKey = "flashThreshold",
    },
    {
        name      = "BlindingPowder",
        itemID    = ns.ITEM.BLINDING_POWDER,
        spells    = { 2094 },
        trackKey  = "trackBlind",
        threshKey = "blindThreshold",
    },
}

local container, mover
local buttons = {}
local reagentIcons = {}
local reagentTracked = {}
local entries = {}
local trackedKinds = {}
local slotStates = {}
local needs = { poison = false, stone = false }
local pendingSecure = false

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

local function Count(itemID)
    return C_Item.GetItemCount(itemID) or 0
end

local function IsLow(db, count, threshold)
    return db.showWarnings and count < threshold
end

local function HasWeapon(slot)
    local itemID = GetInventoryItemID("player", slot)
    if not itemID then return false end
    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    return classID == WEAPON_CLASS, subclassID
end

local function ReadSlot(slot)
    local isWeapon, subclassID = HasWeapon(slot)
    if not isWeapon then return nil end
    local state = { takes = { poison = true, stone = BLADED[subclassID] == true }, enchants = {} }
    local list = C_Item.GetWeaponEnchantInfo(ENCHANT_SLOT[slot])
    if type(list) ~= "table" then return state end
    for _, e in ipairs(list) do
        if IsSecret(e.hasEnchant) or IsSecret(e.timeLeft) or IsSecret(e.charges) then
            state.unknown = true
            return state
        end
        if e.hasEnchant and e.timeLeft and e.timeLeft > 0 then
            local charges = e.charges or 0
            local kind = charges > 0 and "poison" or "stone"
            state.enchants[kind] = state.enchants[kind] or { timeLeft = e.timeLeft, charges = charges }
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
    return kind == "poison" and db.chargesThreshold > 0 and enchant.charges < db.chargesThreshold
end

local function CanApply(slot, kind)
    local state = slotStates[slot]
    return state ~= nil and state.takes[kind]
end

local function SlotExpiringMs(slot, db)
    local state = KnownState(slot)
    if not state then return nil end
    local soonest
    for kind, enchant in pairs(state.enchants) do
        local ms = trackedKinds[kind] and state.takes[kind] and ExpiringMs(enchant, db)
        if ms and (not soonest or ms < soonest) then soonest = ms end
    end
    return soonest
end

local function KnowsAny(spells)
    for _, spellID in ipairs(spells) do
        if IsPlayerSpell(spellID) then return true end
    end
    return false
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
        local text, missing = SlotStatus(hand.slot, kind)
        if text then
            local shade = missing and 0.3 or 1
            status[#status + 1] = function()
                GameTooltip:AddDoubleLine(L[hand.label], text, 1, 1, 1, 1, shade, shade)
            end
        end
        if usable and CanApply(hand.slot, kind) then
            clicks[#clicks + 1] = function() GameTooltip:AddLine(L[hand.click], 0.3, 1, 0.3) end
        end
    end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetItemByID(self.itemID)
    AddSection(status)
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

local function SetClickActions(b, itemID)
    local usable = Count(itemID) > 0
    local kind = ns.ITEM_KIND[itemID]
    for button, hand in ipairs(HANDS) do
        local apply = usable and CanApply(hand.slot, kind)
        b:SetAttribute("type" .. button, apply and "macro" or nil)
        b:SetAttribute("macrotext" .. button, apply and ("/use item:%d\n/use %d"):format(itemID, hand.slot) or nil)
    end
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

function M:Scan()
    local db, seen = ns.db.profile, ns.db.char.seen
    wipe(entries)
    wipe(trackedKinds)
    for _, poison in ipairs(ns.POISON_TYPES) do
        if db.poisons[poison.key] then
            local itemID = ResolveRank(poison, seen)
            if itemID then
                entries[#entries + 1] = itemID
                trackedKinds[poison.kind] = true
            end
        end
    end
    for i, reagent in ipairs(REAGENTS) do
        reagentTracked[i] = db[reagent.trackKey] and KnowsAny(reagent.spells)
    end
end

function M:EvaluateNeeds()
    local db = ns.db.profile
    for _, hand in ipairs(HANDS) do
        slotStates[hand.slot] = ReadSlot(hand.slot)
    end
    local changed = false
    for _, kind in ipairs(KINDS) do
        local need = false
        for _, hand in ipairs(HANDS) do
            local state = KnownState(hand.slot)
            if state and state.takes[kind] and KindNeeded(state.enchants[kind], kind, db) then need = true end
        end
        if needs[kind] ~= need then
            needs[kind] = need
            changed = true
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

    container:ClearAllPoints()
    container:SetPoint(anchor.point, UIParent, anchor.relativePoint, anchor.x, anchor.y)

    local items = {}
    for _, itemID in ipairs(entries) do
        local count = Count(itemID)
        if preview or IsLow(db, count, db.poisonThreshold) or (needs[ns.ITEM_KIND[itemID]] and count > 0) then
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
            local kind = ns.ITEM_KIND[itemID]
            clickMain = clickMain or CanApply(MAIN_HAND, kind)
            clickOff = clickOff or CanApply(OFF_HAND, kind)
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

function M:UpdateTimer()
    local db = ns.db.profile
    ApplyFont(container.timer, SmallFontSize(db))
    if not db.locked then
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
    events:SetScript("OnEvent", function(_, event)
        if event == "WEAPON_ENCHANT_CHANGED" then
            M:OnTick()
        elseif event == "PLAYER_REGEN_ENABLED" then
            if pendingSecure then M:Refresh() end
        else
            M:Refresh()
        end
    end)

    C_Timer.NewTicker(TICK_SECONDS, function() M:OnTick() end)
end
