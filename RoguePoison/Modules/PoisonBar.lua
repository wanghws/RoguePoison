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
local SMALL_TEXT_SCALE = 0.75

local container, mover, flashIcon
local buttons = {}
local entries = {}
local needsPoison = false
local flashTracked = false
local pendingSecure = false

local function Readable(v)
    return v ~= nil and not (issecretvalue and issecretvalue(v))
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

local function SmallFontSize(db)
    return math.max(8, math.floor(db.fontSize * SMALL_TEXT_SCALE))
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
    if Count(self.itemID) > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["TIP_LEFT_CLICK"], 0.3, 1, 0.3)
        if hasOffHand then GameTooltip:AddLine(L["TIP_RIGHT_CLICK"], 0.3, 1, 0.3) end
    end
    GameTooltip:Show()
end

local function FlashOnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetItemByID(ns.ITEM.FLASH_POWDER)
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

local function SetClickActions(b, itemID, offHand)
    local usable = Count(itemID) > 0
    b:SetAttribute("type1", usable and "macro" or nil)
    b:SetAttribute("macrotext1", usable and ("/use item:%d\n/use %d"):format(itemID, MAIN_HAND) or nil)
    local usableOffHand = usable and offHand
    b:SetAttribute("type2", usableOffHand and "macro" or nil)
    b:SetAttribute("macrotext2", usableOffHand and ("/use item:%d\n/use %d"):format(itemID, OFF_HAND) or nil)
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

    flashIcon = CreateFrame("Frame", addonName .. "FlashPowder", container)
    DecorateIcon(flashIcon)
    flashIcon.icon:SetTexture(C_Item.GetItemIconByID(ns.ITEM.FLASH_POWDER) or FALLBACK_ICON)
    flashIcon:EnableMouse(true)
    flashIcon:SetScript("OnEnter", FlashOnEnter)
    flashIcon:SetScript("OnLeave", IconOnLeave)
    flashIcon:Hide()

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
    for _, poison in ipairs(ns.POISON_TYPES) do
        if db.poisons[poison.key] then
            local itemID = ResolveRank(poison, seen)
            if itemID then entries[#entries + 1] = itemID end
        end
    end
    flashTracked = db.trackFlash and KnowsVanish()
end

function M:EvaluateNeeds()
    local db = ns.db.profile
    needsPoison = SlotNeedsPoison(MAIN_HAND, db) or SlotNeedsPoison(OFF_HAND, db)
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
    local offHand = HasWeapon(OFF_HAND)
    local preview = not db.locked

    container:ClearAllPoints()
    container:SetPoint(anchor.point, UIParent, anchor.relativePoint, anchor.x, anchor.y)

    local items = {}
    for _, itemID in ipairs(entries) do
        local count = Count(itemID)
        if preview or IsLow(db, count, db.poisonThreshold) or (needsPoison and count > 0) then
            items[#items + 1] = itemID
        end
    end
    if preview and #items == 0 then
        for _, poison in ipairs(ns.POISON_TYPES) do
            if db.poisons[poison.key] then items[#items + 1] = poison.ranks[1] end
        end
    end

    local hasUsable = false
    for i, itemID in ipairs(items) do
        if Count(itemID) > 0 then hasUsable = true end
        local b = GetButton(i)
        PlaceIcon(b, i, size, spacing)
        SetClickActions(b, itemID, offHand)
        b.itemID = itemID
        b.icon:SetTexture(C_Item.GetItemIconByID(itemID) or FALLBACK_ICON)
        b:Show()
    end
    for i = #items + 1, #buttons do
        buttons[i].itemID = nil
        buttons[i]:Hide()
    end

    local shownCount = #items
    local flashCount = Count(ns.ITEM.FLASH_POWDER)
    local showFlash = flashTracked and (preview or IsLow(db, flashCount, db.flashThreshold))
    if showFlash then
        shownCount = shownCount + 1
        PlaceIcon(flashIcon, shownCount, size, spacing)
    end
    flashIcon:SetShown(showFlash)

    local width = math.max(shownCount, 1) * size + math.max(shownCount - 1, 0) * spacing
    container:SetSize(width, size)
    ApplyFont(container.hint, SmallFontSize(db))
    if preview or not hasUsable then
        container.hint:SetText("")
    else
        container.hint:SetText(offHand and L["HINT_CLICK_BOTH"] or L["HINT_CLICK_MAIN"])
    end
    mover.label:SetText(L["MOVER_LABEL"])
    mover:SetShown(preview and db.enabled)
    container:SetShown(db.enabled and shownCount > 0)
end

function M:UpdateTexts()
    local db = ns.db.profile
    for _, b in ipairs(buttons) do
        if b.itemID then PaintIcon(b, Count(b.itemID), db.poisonThreshold, db) end
    end
    PaintIcon(flashIcon, Count(ns.ITEM.FLASH_POWDER), db.flashThreshold, db)
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
    self:ApplySecure()
    self:UpdateTexts()
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
