local ROOT = arg[1] or "RoguePoison"
local inCombat = false
local blocked = {}
local bags, equipped = {}, { [16] = 1000, [17] = 1001 }
local enchants = { [16] = {}, [17] = {} }
local knownSpells = { [1856] = true }
local frames, eventFrames = {}, {}
local tickers = {}

local function secureCheck(f, op)
  if inCombat and rawget(f, "_protected") then blocked[#blocked+1] = op end
end

local FrameMT = {}
FrameMT.__index = function(t, k)
  local v = rawget(FrameMT, k)
  if v then return v end
  if type(k) == "string" and k:find("^%u") then return function() end end
end
function FrameMT:Show() secureCheck(self, "Show"); self._shown = true end
function FrameMT:Hide() secureCheck(self, "Hide"); self._shown = false end
function FrameMT:SetShown(v) if v then self:Show() else self:Hide() end end
function FrameMT:IsShown() return self._shown end
function FrameMT:SetAttribute(k, v) secureCheck(self, "SetAttribute"); self._attr[k] = v end
function FrameMT:GetAttribute(k) return self._attr[k] end
function FrameMT:SetPoint(...) secureCheck(self, "SetPoint"); self._point = {...} end
function FrameMT:ClearAllPoints() secureCheck(self, "ClearAllPoints") end
function FrameMT:SetSize(w, h) secureCheck(self, "SetSize"); self._w, self._h = w, h end
function FrameMT:GetPoint() local p = self._point or {}; return p[1], p[2], p[3], p[4], p[5] end
function FrameMT:RegisterEvent(e) self._events[e] = true; eventFrames[self] = true end
function FrameMT:UnregisterAllEvents() self._events = {} end
function FrameMT:SetScript(k, fn) self._scripts[k] = fn end
function FrameMT:GetFrameLevel() return 1 end
function FrameMT:SetText(t) self._text = t end
function FrameMT:GetText() return self._text end
function FrameMT:GetFont() return "Fonts\\ARIALN.TTF", 12, "" end
function FrameMT:SetTexture(t) self._tex = t end
function FrameMT:SetDesaturated(d) self._desat = d end
function FrameMT:SetTextColor(r,g,b) self._color = {r,g,b} end
function FrameMT:SetEnabled(v) self._enabled = v end
function FrameMT:SetFocus() self._focus = true end
function FrameMT:HasFocus() return self._focus == true end
function FrameMT:ClearFocus()
  if not self._focus then return end
  self._focus = false
  if self._scripts.OnEditFocusLost then self._scripts.OnEditFocusLost(self) end
end
function FrameMT:HookScript(k, fn) self._hooks = self._hooks or {}; self._hooks[k] = fn end

local function newObj(parent, template)
  local o = setmetatable({ _attr = {}, _events = {}, _scripts = {}, _shown = true, _children = {} }, FrameMT)
  o.CreateTexture = function() return newObj() end
  o.CreateFontString = function() return newObj() end
  if template and template:find("Secure") then
    o._protected = true
    local p = parent
    while p do rawset(p, "_protected", true); p = rawget(p, "_parent") end
  end
  rawset(o, "_parent", parent or false)
  return o
end

local Spinner = {}
function Spinner:SetMinMaxValues(min, max) self.min, self.max = min, max; self:SetValue(self:GetValue()) end
function Spinner:GetValue() return self.currentValue or self.min or 0 end
function Spinner:SetOnValueChangedCallback(fn) self.onValueChangedCallback = fn end
function Spinner:SetValue(value)
  local v = math.max(self.min or -math.huge, math.min(self.max or math.huge, value))
  local changed = v ~= self.currentValue
  if changed or (self.clampIfInputExceedsRange and v ~= value) then
    self.currentValue = v
    self._text = v
    if changed and self.onValueChangedCallback then self.onValueChangedCallback(self, v) end
  end
end
function Spinner:Increment(n) self:SetValue(self:GetValue() + (n or 1)) end
function Spinner:Decrement(n) self:SetValue(self:GetValue() - (n or 1)) end

function CreateFrame(_, name, parent, template)
  local f = newObj(parent, template)
  if template == "NumericInputSpinnerTemplate" then
    for k, v in pairs(Spinner) do f[k] = v end
    f.IncrementButton, f.DecrementButton = newObj(f), newObj(f)
    f._scripts.OnTextChanged = function(self) self:SetValue(tonumber(self._text) or 0) end
  end
  frames[#frames+1] = f
  if name then _G[name] = f end
  return f
end

UIParent = newObj()
NumberFontNormal = newObj()
GameTooltip = newObj()
local tipLines = {}
local tipOwner
GameTooltip.SetOwner = function(_, o) wipe(tipLines); tipOwner = o end
GameTooltip.IsOwned = function(_, f) return tipOwner == f end
GameTooltip.AddLine = function(_, text) tipLines[#tipLines+1] = text end
GameTooltip.AddDoubleLine = function(_, left, right) tipLines[#tipLines+1] = left .. "|" .. right end
INVSLOT_MAINHAND, INVSLOT_OFFHAND = 16, 17
Enum = {
  ItemClass = { Weapon = 2 },
  ItemWeaponSubclass = { Axe1H = 0, Axe2H = 1, Mace1H = 4, Mace2H = 5, Polearm = 6, Staff = 10, Sword1H = 7, Sword2H = 8, Unarmed = 13, Dagger = 15 },
  WeaponSlot = { MainHand = 0, OffHand = 1, Ranged = 2 },
  CraftingReagentType = { Modifying = 0, Basic = 1, Finishing = 2 },
}
function InCombatLockdown() return inCombat end
local stateDrivers = {}
function RegisterStateDriver(f, attr, cond)
  assert(attr == "visibility" and cond:find("%[combat%] hide"), "combat visibility driver")
  stateDrivers[#stateDrivers+1] = f
end
local function setCombat(v)
  inCombat = v
  for _, f in ipairs(stateDrivers) do rawset(f, "_shown", not v) end
end
local function visible(f)
  local p = f
  while p do
    if not rawget(p, "_shown") then return false end
    p = rawget(p, "_parent")
  end
  return true
end
local optionsWidgets = {}
local function aceWidget()
  local w = { _cb = {} }
  optionsWidgets[#optionsWidgets+1] = w
  return setmetatable(w, { __index = function(_, k)
    if k == "SetCallback" then return function(self, n, fn) self._cb[n] = fn end end
    if k == "Hide" then return function(self) self._hidden = true; if self._cb.OnClose then self._cb.OnClose(self) end end end
    if k == "SelectTab" then return function(self, g) self.localstatus = { selected = g } end end
    if k == "status" or k == "localstatus" then return nil end
    return function() end
  end })
end
local FakeAceGUI = { Create = function() return aceWidget() end, Release = function() end }
function UnitClass() return "Rogue", "ROGUE" end
function IsPlayerSpell(id) return knownSpells[id] == true end
local resting = false
function IsResting() return resting end
function GetInventoryItemID(_, slot) return equipped[slot] end
local clientLocale = "zhCN"
function GetLocale() return clientLocale end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
local SECRET = {}
function issecretvalue(v) return v == SECRET end
C_AddOns = { GetAddOnMetadata = function() return "1.0.0" end, IsAddOnLoaded = function() return false end }
C_Item = {
  GetItemCount = function(id) return bags[id] or 0 end,
  GetItemInfoInstant = function(id) return id, "Weapon", "Dagger", "INVTYPE_WEAPON", 1, 2, id == 1002 and 4 or 15 end,
  GetItemNameByID = function(id) return "Item" .. id end,
  GetItemIconByID = function(id) return 100000 + id end,
  GetItemMaxStackSizeByID = function() return 20 end,
  RequestLoadItemDataByID = function() end,
  GetWeaponEnchantInfo = function(ws)
    local e = enchants[ws == 0 and 16 or 17]
    local list = { { hasEnchant = false, enchantType = 0, enchantID = 0, timeLeft = 0, charges = 0 } }
    if e.stone then list[#list+1] = e.stone end
    if e.poison then list[#list+1] = e.poison end
    return list
  end,
}
local function P(ms, charges) return { hasEnchant = true, enchantType = 2, enchantID = 625, timeLeft = ms, charges = charges } end
local function S(ms) return { hasEnchant = true, enchantType = 2, enchantID = 2506, timeLeft = ms, charges = 0 } end
local deferred = {}
C_Timer = { NewTicker = function(_, fn) tickers[#tickers+1] = fn end, After = function(_, fn) deferred[#deferred+1] = fn end }
SlashCmdList = {}
Settings = { RegisterCanvasLayoutCategory = function() return {} end, RegisterAddOnCategory = function() end }
local sounds, warnings = {}, {}
SOUNDKIT = { RAID_WARNING = 8959 }
function PlaySound(id) sounds[#sounds+1] = id end
ChatTypeInfo = { RAID_WARNING = {} }
RaidWarningUtil = { AddMessage = function(text) warnings[#warnings+1] = text end }
local lastPrint
ERR_INV_FULL = "Inventory is full."
function print(...)
  local line = table.concat({...}, " ")
  if line:find("RoguePoison|r", 1, true) then lastPrint = line end
  io.write("[print] ", line, "\n")
end

local libs = {}
LibStub = setmetatable({ NewLibrary = function() end }, { __call = function(_, name)
  if name == "AceGUI-3.0" then
    return FakeAceGUI
  elseif name == "LibDataBroker-1.1" then
    return { NewDataObject = function(_, _, obj) return obj end }
  elseif name == "AceDB-3.0" then
    return { New = function(_, _, defaults)
      local function copy(t) local r = {} for k, v in pairs(t) do r[k] = type(v) == "table" and copy(v) or v end return r end
      local db = copy(defaults)
      db.RegisterCallback = function() end
      return db
    end }
  end
  return setmetatable({}, { __index = function() return function() end end })
end })

local ns = {}
local function load(rel)
  local chunk = assert(loadfile(ROOT .. "/" .. rel))
  chunk("RoguePoison", ns)
end
for _, f in ipairs({ "Locales/Locales.lua", "Locales/enUS.lua", "Locales/zhCN.lua", "Locales/zhTW.lua", "Data/Poisons.lua",
  "Init.lua", "Config.lua", "Modules/PoisonBar.lua", "Modules/ReagentBuyer.lua", "Modules/Recipes.lua", "Options.lua" }) do load(f) end

local function fire(event, ...)
  for f in pairs(eventFrames) do
    if f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
  end
end
local function tick() for _, fn in ipairs(tickers) do fn() end end

local function check(cond, msg) if not cond then error("FAIL: " .. msg, 2) end print("ok  " .. msg) end
local bar

bags = { [8928] = 25, [8985] = 5, [8925] = 3, [5140] = 2, [5173] = 20, [8924] = 15, [7964] = 4, [12404] = 12 }
fire("ADDON_LOADED", "RoguePoison")
fire("PLAYER_LOGIN")
check(ns.active, "active for rogue")
fire("PLAYER_ENTERING_WORLD")
bar = _G.RoguePoisonBar
local flash = _G.RoguePoisonFlashPowder
local blind = _G.RoguePoisonBlindingPowder

local function poisonButtons()
  local list = {}
  for _, f in ipairs(frames) do
    if rawget(f, "_protected") and rawget(f, "low") and rawget(f, "_shown") then list[#list+1] = f end
  end
  return list
end
local function shownItems()
  local ids = {}
  for _, f in ipairs(poisonButtons()) do ids[#ids+1] = tostring(rawget(f, "itemID")) end
  if flash._shown then ids[#ids+1] = "flash" end
  if blind._shown then ids[#ids+1] = "blind" end
  return table.concat(ids, ",")
end
local function buttonFor(itemID)
  for _, f in ipairs(poisonButtons()) do if rawget(f, "itemID") == itemID then return f end end
end

check(bar._shown, "bar shown when weapons have no poison")
check(shownItems() == "8928,8985,12404,flash", "instant, deadly, sharpening stone, low flash powder: " .. shownItems())
check(buttonFor(8928)._attr.macrotext1 == "/use item:8928\n/use 16", "left click macro main hand")
check(buttonFor(8928)._attr.macrotext2 == "/use item:8928\n/use 17", "right click macro off hand")
check(buttonFor(8985)._attr.macrotext1 == "/use item:8985\n/use 16", "deadly V macro")
check(buttonFor(12404)._attr.macrotext1 == "/use item:12404\n/use 16", "sharpening stone picks dense over solid")
check(buttonFor(8985).low._text == "数量不足", "low label under deadly poison")
check(buttonFor(8985).count._text == 5 and buttonFor(8985).count._color[2] == 0.3, "deadly count in red")
check(buttonFor(8928).low._text == "" and buttonFor(12404).low._text == "", "no label under stocked items")
check(flash.low._text == "数量不足", "low label under flash powder")
check(flash.count._text == 2 and flash.count._color[2] == 0.3, "flash powder shows owned count in red")
check(flash._point[4] == 120, "flash powder icon after the poison buttons")
check(bar.hint._text == "左键主手,右键副手", "click hint above the icons")
check(bar.timer._text == "", "no countdown when weapons have no poison")
check(not blind._shown, "no blinding powder icon before Blind is learned")

enchants[16].poison = P(30 * 60000, 50)
enchants[17].poison = P(25 * 60000, 40)
tick()
check(bar._shown and shownItems() == "8985,12404,flash", "stone still offered when weapons only poisoned: " .. shownItems())
enchants[16].stone = S(30 * 60000)
enchants[17].stone = S(30 * 60000)
fire("WEAPON_ENCHANT_CHANGED")
check(bar._shown and shownItems() == "8985,flash", "only low items shown when weapons poisoned and sharpened: " .. shownItems())
check(flash._point[4] == 40, "flash powder icon follows the low poison")
bags[5140] = 20
bags[8985] = 20
fire("BAG_UPDATE_DELAYED")
check(not bar._shown, "bar hidden when weapons poisoned and stock is fine")

knownSpells[2094] = true
bags[5530] = 3
fire("SPELLS_CHANGED")
check(bar._shown and shownItems() == "blind", "blinding powder shown when Blind learned and stock low: " .. shownItems())
check(blind.low._text == "数量不足", "low label under blinding powder")
check(blind.count._text == 3 and blind.count._color[2] == 0.3, "blinding powder count in red")
check(bar.hint._text == "", "no click hint when only blinding powder shows")
bags[5140] = 2
fire("BAG_UPDATE_DELAYED")
check(shownItems() == "flash,blind" and blind._point[4] == 40, "blinding powder follows flash powder")
ns.db.profile.trackBlind = false
ns:RefreshAll()
check(shownItems() == "flash", "untracked blinding powder hidden")
ns.db.profile.trackBlind = true
bags[5140] = 20
bags[5530] = 20
ns:RefreshAll()
check(not bar._shown, "hidden when flash and blinding powder stocked")

enchants[16].poison, enchants[17].poison = nil, nil
fire("WEAPON_ENCHANT_CHANGED")
check(bar._shown and shownItems() == "8928,8985", "poisons shown when weapons only have stones: " .. shownItems())
check(bar.timer._text == "", "no countdown for missing poison")
enchants[16].poison = P(30 * 60000, 50)
enchants[17].poison = P(25 * 60000, 40)
fire("WEAPON_ENCHANT_CHANGED")
check(not bar._shown, "hidden when both weapons have poison and stone")
enchants[16].stone = S(3 * 60000 + 30 * 1000)
tick()
check(bar._shown and shownItems() == "12404", "expiring stone offers only the stone: " .. shownItems())
check(bar.timer._text == "主手 3:30", "countdown follows the expiring stone: " .. tostring(bar.timer._text))
ns.db.profile.poisons.sharpening = false
ns:RefreshAll()
check(not bar._shown and bar.timer._text == "", "untracked stone neither shown nor counted down")
ns.db.profile.poisons.sharpening = true
enchants[16].stone = S(30 * 60000)
ns:RefreshAll()
check(not bar._shown, "hidden again after re-sharpening")

equipped[17] = 1002
enchants[17].stone = nil
fire("PLAYER_EQUIPMENT_CHANGED")
check(not bar._shown, "mace off hand without a stone needs none")
enchants[16].stone = nil
fire("WEAPON_ENCHANT_CHANGED")
check(bar._shown and shownItems() == "12404", "dagger main hand still asks for a stone: " .. shownItems())
local stone = buttonFor(12404)
check(stone._attr.type1 == "macro" and stone._attr.type2 == nil, "stone has no right-click onto a mace off hand")
check(bar.hint._text == "左键主手", "hint omits the mace off hand for the stone")
stone._scripts.OnEnter(stone)
check(table.concat(tipLines, ";") == " ;主手|无磨刀石; ;左键:涂抹主手武器", "stone tooltip skips the mace off hand: " .. table.concat(tipLines, ";"))
equipped[16], equipped[17] = 1002, 1001
enchants[17].stone = nil
fire("PLAYER_EQUIPMENT_CHANGED")
stone = buttonFor(12404)
check(stone._attr.type1 == nil and stone._attr.macrotext2 == "/use item:12404\n/use 17", "stone only right-clicks onto a dagger off hand")
check(bar.hint._text == "右键副手", "hint names only the off hand: " .. tostring(bar.hint._text))
equipped[17] = 1002
bags[12404] = 3
fire("PLAYER_EQUIPMENT_CHANGED")
stone = buttonFor(12404)
check(stone and stone._attr.type1 == nil and stone._attr.type2 == nil, "low stone with two maces has no click action")
check(bar.hint._text == "", "no hint when no hand takes the shown stone")
stone._scripts.OnEnter(stone)
check(#tipLines == 0, "no blank lines in the stone tooltip with two maces: " .. #tipLines)
bags[12404] = 12
equipped[16], equipped[17] = 1000, 1001
enchants[16].stone = S(30 * 60000)
enchants[17].stone = S(30 * 60000)
equipped[17] = 1001
fire("PLAYER_EQUIPMENT_CHANGED")
check(not bar._shown, "hidden with dagger off hand sharpened again")
enchants[16].poison = { hasEnchant = true, enchantType = 2, enchantID = 625, timeLeft = SECRET, charges = SECRET }
fire("WEAPON_ENCHANT_CHANGED")
check(not bar._shown, "unreadable enchant data is not treated as missing")
enchants[16].poison = P(30 * 60000, 50)
fire("WEAPON_ENCHANT_CHANGED")

enchants[16].poison = P(4 * 60000 + 59 * 1000, 50)
tick()
check(bar._shown and bar.timer._text == "主手 4:59", "countdown shows main hand 4:59: " .. tostring(bar.timer._text))
check(bar.timer._point[5] == -3, "countdown right below bar when no low-stock label")
enchants[16].poison = P(4 * 60000 + 58 * 1000, 50)
tick()
check(bar.timer._text == "主手 4:58", "countdown ticks down while needsPoison stays true: " .. tostring(bar.timer._text))
enchants[17].poison = P(3 * 60000 + 12 * 1000, 40)
tick()
check(bar.timer._text == "主手 4:58  副手 3:12", "countdown lists both expiring hands: " .. tostring(bar.timer._text))
enchants[16].poison = P(30 * 60000, 50)
fire("WEAPON_ENCHANT_CHANGED")
check(bar.timer._text == "副手 3:12", "re-poisoned main hand leaves off hand countdown: " .. tostring(bar.timer._text))
enchants[17].poison = P(25 * 60000, 40)
tick()
check(not bar._shown and bar.timer._text == "", "countdown clears when weapons poisoned")

enchants[17].poison = P(25 * 60000, 8)
tick()
check(bar._shown and shownItems() == "8928,8985", "only poisons shown when off hand charges < 10: " .. shownItems())
check(bar.timer._text == "", "no countdown when triggered only by low charges")

enchants[17].poison = { hasEnchant = true, enchantType = 2, enchantID = 603, timeLeft = 25 * 60000, charges = 0 }
tick()
check(not bar._shown, "chargeless crippling poison is a poison, not low charges")
enchants[17].poison = { hasEnchant = true, enchantType = 2, enchantID = 1003, timeLeft = 25 * 60000, charges = 0 }
tick()
check(bar._shown and shownItems() == "8928,8985", "unlisted enchant is not taken for a poison: " .. shownItems())
for _, id in ipairs({ 1643, 483, 14, 13, 40, 2684 }) do
  enchants[17].stone = { hasEnchant = true, enchantType = 2, enchantID = id, timeLeft = 30 * 60000, charges = 0 }
  enchants[17].poison = P(25 * 60000, 40)
  tick()
  check(not bar._shown, "stone enchant " .. id .. " counts as a stone")
end
enchants[17].stone = S(30 * 60000)
enchants[17].poison = P(25 * 60000, 40)
tick()
check(not bar._shown, "hidden again")
bags[5140] = 2
fire("BAG_UPDATE_DELAYED")
check(bar._shown and shownItems() == "flash" and bar.hint._text == "", "no click hint when only flash powder shows")
bags[5140] = 20
fire("BAG_UPDATE_DELAYED")

setCombat(true)
fire("PLAYER_REGEN_DISABLED")
enchants[16].poison = P(9 * 60000, 50)
tick()
bags[8928] = 0
fire("BAG_UPDATE_DELAYED")
check(#blocked == 0, "no protected calls in combat (" .. table.concat(blocked, ",") .. ")")
check(not bar._shown, "visibility frozen in combat")
check(not visible(bar), "bar hidden by combat driver")
setCombat(false)
fire("PLAYER_REGEN_ENABLED")
check(bar._shown and visible(bar), "bar shown after combat when main hand < 10m")
check(bar.timer._text == "主手 9:00", "countdown active after combat: " .. tostring(bar.timer._text))
check(bar.timer._point[5] < -3, "countdown shifts below low-stock label when low item shown")
local instant = buttonFor(8928)
check(instant ~= nil and instant.count._text == 0 and instant.icon._desat, "instant VI at 0 stays as grey icon (remembered)")
check(instant.low._text == "数量不足", "low label under empty instant poison")
check(instant._attr.type1 == nil and instant._attr.type2 == nil, "no click action without the item")

equipped[17] = nil
fire("PLAYER_EQUIPMENT_CHANGED")
check(buttonFor(8985)._attr.type2 == nil, "no right-click action without off hand weapon")
check(bar.hint._text == "左键主手", "click hint drops off hand without off hand weapon")
local beforeRest = shownItems()
resting = true
fire("PLAYER_UPDATE_RESTING")
local lowOnly = {}
for _, f in ipairs(poisonButtons()) do
  check(f.low._text == "数量不足", "rest area keeps only low icons: " .. tostring(f.itemID))
  lowOnly[#lowOnly + 1] = f.itemID
end
check(bar._shown and #lowOnly > 0 and shownItems() ~= beforeRest, "rest area drops the re-apply icons: " .. beforeRest .. " -> " .. shownItems())
check(bar.timer._text == "", "no countdown in a rest area")
local savedBags = {}
for id, n in pairs(bags) do savedBags[id] = n end
for id in pairs(bags) do bags[id] = 50 end
bags[8928] = 50
fire("BAG_UPDATE_DELAYED")
check(not bar._shown, "nothing low, bar hidden in a rest area")
setCombat(true)
resting = false
fire("PLAYER_UPDATE_RESTING")
check(#blocked == 0 and not bar._shown, "leaving a rest area in combat waits for combat to end")
setCombat(false)
fire("PLAYER_REGEN_ENABLED")
check(bar._shown, "bar back after leaving the rest area")
for id in pairs(bags) do bags[id] = savedBags[id] end
fire("BAG_UPDATE_DELAYED")
resting = true
ns.db.profile.locked = false
ns:RefreshAll()
check(bar._shown, "unlocked preview still shows in a rest area")
ns.db.profile.locked = true
resting = false
fire("PLAYER_UPDATE_RESTING")

ns.db.profile.locked = false
ns:RefreshAll()
check(bar._shown, "unlocked shows bar")
check(bar.hint._text == "", "no click hint while unlocked")
check(bar.timer._text == "", "no countdown while unlocked")
check(flash._shown and blind._shown, "unlocked previews flash and blinding powder icons")
ns:OpenOptions("checks")
check(ns._optionsFrame ~= nil, "options open")
setCombat(true)
fire("PLAYER_REGEN_DISABLED")
check(ns._optionsFrame == nil, "options closed in combat")
ns:OpenOptions()
check(ns._optionsFrame == nil, "options cannot open in combat")
setCombat(false)
fire("PLAYER_REGEN_ENABLED")
check(ns._optionsFrame ~= nil and ns._optionsTab.localstatus.selected == "checks", "options reopen on same tab after combat")
check(ns.db.profile.locked == false, "unlock state restored after combat")
local L = ns.L
check(ns.db.global.locale == "auto" and L["WARN_LOW_STOCK"] == "数量不足", "auto follows zhCN client")
local moverLabel
for _, f in ipairs(frames) do local lbl = rawget(f, "label"); if lbl then moverLabel = lbl end end
ns:SetLanguage("enUS")
check(L["WARN_LOW_STOCK"] == "Low stock", "switch to English")
check(moverLabel._text == "Drag to move", "mover label relocalized")
ns.db.profile.locked = true
ns:RefreshAll()
check(bar.hint._text == "Left: MH", "click hint relocalized")
check(bar.timer._text == "MH 9:00", "countdown relocalized: " .. tostring(bar.timer._text))
ns.db.profile.locked = false
ns:RefreshAll()
for _, fn in ipairs(deferred) do fn() end
ns:SetLanguage("zhTW")
check(L["WARN_LOW_STOCK"] == "數量不足", "switch to Traditional Chinese")
clientLocale = "deDE"
ns:SetLanguage("auto")
check(L["WARN_LOW_STOCK"] == "Low stock", "unsupported client falls back to English")
check(L["NO_SUCH_KEY"] == "NO_SUCH_KEY", "missing key returns key")
clientLocale = "zhCN"
ns:SetLanguage("auto")
knownSpells[1856] = nil
knownSpells[2094] = nil
bags[5140] = 1
bags[5530] = 1
fire("SPELLS_CHANGED")
check(not flash._shown and not blind._shown, "no reagent icons before spells are learned")
ns.db.profile.enabled = false
ns:RefreshAll()
check(not bar._shown, "disabled hides bar")

local merchant, purchases, money = {}, {}, 1000000
function GetMerchantNumItems() return #merchant end
function GetMerchantItemID(i) return merchant[i] and merchant[i].itemID end
function GetMerchantItemMaxStack(i) return merchant[i].maxStack or 20 end
function GetMoney() return money end
function BuyMerchantItem(i, n)
  purchases[#purchases+1] = merchant[i].itemID .. "x" .. n
  bags[merchant[i].itemID] = (bags[merchant[i].itemID] or 0) + n
end
C_MerchantFrame = { GetItemInfo = function(i)
  local m = merchant[i]
  return { price = m.price, stackCount = m.step or 1, numAvailable = m.available or -1, isPurchasable = true, hasExtendedCost = false }
end }
C_CurrencyInfo = { GetCoinTextureString = function(c) return "coin" .. c end }
local schematics = {
  [1] = { outputItemID = 8928, quantityMin = 1, reagentSlotSchematics = {
    { reagentType = 1, quantityRequired = 4, reagents = { { itemID = 8924 } } },
    { reagentType = 1, quantityRequired = 1, reagents = { { itemID = 8925 } } } } },
  [2] = { outputItemID = 5530, quantityMin = 1, reagentSlotSchematics = {
    { reagentType = 1, quantityRequired = 1, reagents = { { itemID = 2452 } } } } },
  [3] = { outputItemID = 12404, quantityMin = 1, reagentSlotSchematics = {
    { reagentType = 1, quantityRequired = 1, reagents = { { itemID = 12365 } } } } },
}
local tradeSkillLinked = false
C_TradeSkillUI = {
  GetRecipeSchematic = function(id) return schematics[id] end,
  GetRecipeInfo = function(id) return schematics[id] and { recipeID = id, learned = schematics[id].learned ~= false } end,
  IsTradeSkillLinked = function() return tradeSkillLinked end,
  IsTradeSkillGuild = function() return false end,
  IsTradeSkillGuildMember = function() return false end,
  IsNPCCrafting = function() return false end,
  GetFilteredRecipeIDs = function() local ids = {} for id in pairs(schematics) do ids[#ids+1] = id end table.sort(ids) return ids end,
}
local selectedRecipe = 1
function hooksecurefunc(t, name, fn)
  local orig = t[name]
  t[name] = function(...) local r = orig(...); fn(...); return r end
end
ProfessionsFrame = newObj()
local page = newObj(ProfessionsFrame)
ProfessionsFrame.CraftingPage = page
page.CreateAllButton = newObj(page)
page.SchematicForm = newObj(page)
page.SchematicForm.GetRecipeInfo = function() return { recipeID = selectedRecipe, learned = true } end
page.SchematicForm.Init = function() end
fire("ADDON_LOADED", "Blizzard_Professions")
local buyPanel
for _, f in ipairs(frames) do if rawget(f, "_parent") == page and rawget(f, "rows") then buyPanel = f end end
check(buyPanel ~= nil and not buyPanel._shown, "buy panel created hidden above Create All")
check(buyPanel._point[2] == page.CreateAllButton, "buy panel anchored to Create All")
local function selectRecipe(id) selectedRecipe = id; page.SchematicForm:Init() end
local function buyButton(mode) return buyPanel.rows[mode].button end

ns.db.profile.enabled = true
merchant = { { itemID = 8924, price = 300 }, { itemID = 8925, price = 200, step = 5 } }
selectRecipe(1)
check(not buyPanel._shown, "no buy panel without a merchant")
fire("MERCHANT_SHOW")
check(buyPanel._shown, "buy panel shown at a poison vendor")
check(buyPanel.rows.stacks.unit._text == "组" and buyPanel.rows.items.unit._text == "个" and buyButton("items")._text == "购买", "buy row labels")
check(buyPanel.rows.stacks.box._text == 1, "amount defaults to 1")
bags[8924], bags[8925] = 15, 3
fire("BAG_UPDATE_DELAYED")
check(buyButton("items")._enabled == false, "buy 1 disabled when bags hold enough")
buyButton("items")._scripts.OnEnter(buyButton("items"))
check(tipLines[1] == "背包中材料已足够", "tooltip says reagents are enough")
check(buyButton("stacks")._enabled == true, "buy 1 stack enabled")
buyButton("stacks")._scripts.OnEnter(buyButton("stacks"))
check(table.concat(tipLines, ";") == "Item8924|x65;Item8925|x20", "stack tooltip lists missing reagents: " .. table.concat(tipLines, ";"))
check(buyPanel.rows.stacks.cost._text == "coin20300" and buyPanel.rows.stacks.cost._color[2] == 1, "stack cost shown after its button")
check(buyPanel.rows.items.cost._text == "", "no cost when bags hold enough")
local stacksPt, itemsPt = buyPanel.rows.stacks.box._point, buyPanel.rows.items.box._point
check(stacksPt[2] == buyPanel and itemsPt[2] == buyPanel and stacksPt[4] == 29 and itemsPt[4] == 29, "rows left-aligned with Create All")
check(buyPanel.rows.stacks.unit._point[2] == buyPanel.rows.stacks.box.IncrementButton, "unit label after the > arrow")
check(stacksPt[5] > itemsPt[5], "stacks row above items row")
check(buyButton("stacks")._point[2] == buyPanel.rows.stacks.unit and buyButton("items")._point[4] == buyButton("stacks")._point[4], "buy buttons line up")
check(buyPanel.rows.stacks.cost._point[2] == buyButton("stacks"), "cost anchored after the buy button")
bags[8924], bags[8925] = 0, 0
buyButton("items")._scripts.OnClick(buyButton("items"))
check(table.concat(purchases, ",") == "8924x4", "first purchase sent alone: " .. table.concat(purchases, ","))
check(buyButton("items")._enabled == false and buyButton("stacks")._enabled == false, "buttons disabled while buying")
fire("BAG_UPDATE_DELAYED")
check(table.concat(purchases, ",") == "8924x4,8925x5", "vials rounded up to the vendor bundle: " .. table.concat(purchases, ","))
fire("BAG_UPDATE_DELAYED")
check(buyButton("stacks")._enabled == true, "buttons re-enabled after the job")
check(tipLines[1] == "Item8924|x76", "hovered stack tooltip refreshed after the job: " .. tostring(tipLines[1]))
wipe(purchases)
bags[8924], bags[8925] = 0, 0
ns.db.profile.buyAmount.stacks = 2
buyButton("stacks")._scripts.OnClick(buyButton("stacks"))
for _ = 1, 9 do fire("BAG_UPDATE_DELAYED") end
check(table.concat(purchases, ",") == "8924x20,8924x20,8924x20,8924x20,8924x20,8924x20,8924x20,8924x20,8925x20,8925x20",
  "2 stacks bought in max-stack chunks: " .. table.concat(purchases, ","))
fire("BAG_UPDATE_DELAYED")
wipe(purchases)
bags[8924], bags[8925] = 0, 0
buyButton("stacks")._scripts.OnClick(buyButton("stacks"))
lastPrint = nil
fire("UI_ERROR_MESSAGE", 51, "Ability is not ready yet.")
check(lastPrint == nil and buyButton("stacks")._enabled == false, "unrelated red error keeps the run going")
fire("UI_ERROR_MESSAGE", 2, ERR_INV_FULL)
fire("BAG_UPDATE_DELAYED")
check(#purchases == 1 and buyButton("stacks")._enabled == true, "full bags stop the purchase run")
check(lastPrint and lastPrint:find("材料购买已中断"), "stopped run is reported: " .. tostring(lastPrint))
wipe(purchases)
bags[8924], bags[8925] = 0, 0
buyButton("items")._scripts.OnClick(buyButton("items"))
fire("BAG_UPDATE_DELAYED")
lastPrint = nil
fire("BAG_UPDATE_DELAYED")
check(lastPrint == nil, "finished run prints nothing")
wipe(purchases)
bags[8924], bags[8925] = 0, 0
buyButton("items")._scripts.OnClick(buyButton("items"))
fire("MERCHANT_UPDATE")
check(#purchases == 1 and lastPrint == nil and buyButton("items")._enabled == false, "unchanged merchant list keeps the run going")
merchant[1], merchant[2] = merchant[2], merchant[1]
fire("MERCHANT_UPDATE")
check(lastPrint and lastPrint:find("材料购买已中断") and buyButton("items")._enabled == true, "reshuffled merchant list stops the run")
merchant[1], merchant[2] = merchant[2], merchant[1]
lastPrint = nil
fire("MERCHANT_UPDATE")
wipe(purchases)
bags[8924], bags[8925] = 0, 0
merchant[2].available = 3
fire("MERCHANT_UPDATE")
check(buyButton("items")._enabled == true and buyButton("stacks")._enabled == false, "limited stock disables only the plan it cannot cover")
buyButton("stacks")._scripts.OnEnter(buyButton("stacks"))
check(tipLines[1] == "商人库存不足", "tooltip says the vendor is short")
buyButton("stacks")._scripts.OnClick(buyButton("stacks"))
check(#purchases == 0, "nothing bought when the vendor is short")
merchant[2].available = nil
fire("MERCHANT_UPDATE")
ns.db.profile.enabled = false
ns:RefreshAll()
check(not buyPanel._shown, "hidden when the addon is disabled")
ns.db.profile.enabled = true
ns:RefreshAll()
check(buyPanel._shown, "shown again when re-enabled")

buyButton("stacks")._scripts.OnEnter(buyButton("stacks"))
check(GameTooltip._shown and GameTooltip:IsOwned(buyButton("stacks")), "stack tooltip open")
local unloaded, loadRequests = { [8928] = true }, {}
C_Item.GetItemMaxStackSizeByID = function(id) if not unloaded[id] then return 20 end end
C_Item.GetItemNameByID = function(id) if not unloaded[id] then return "Item" .. id end end
C_Item.RequestLoadItemDataByID = function(id) loadRequests[#loadRequests+1] = id end
local buyer = ns.modules.reagentBuyer
local origUpdate, updates = buyer.Update, 0
buyer.Update = function(self) updates = updates + 1; return origUpdate(self) end
bags[8924], bags[8925] = 0, 0
fire("MERCHANT_UPDATE")
check(buyButton("stacks")._enabled == false and buyButton("items")._enabled == true, "stack button waits for the max stack size")
check(table.concat(loadRequests, ",") == "8928", "max stack size requested once: " .. table.concat(loadRequests, ","))
check(not GameTooltip._shown, "hovered tooltip hidden when its plan cannot be computed")
updates = 0
fire("ITEM_DATA_LOAD_RESULT", 8928, false)
check(updates == 0, "failed load does not refresh")
fire("MERCHANT_UPDATE")
check(table.concat(loadRequests, ",") == "8928", "failed load is not requested again")
updates = 0
fire("ITEM_DATA_LOAD_RESULT", 9999, true)
check(updates == 0, "unrequested item data does not refresh")
unloaded[8928] = nil
fire("ITEM_DATA_LOAD_RESULT", 8928, true)
check(updates == 1 and buyButton("stacks")._enabled == true, "one refresh once the max stack size loads")
fire("ITEM_DATA_LOAD_RESULT", 8928, true)
check(updates == 1, "repeat load result ignored")
wipe(loadRequests)
unloaded[8924] = true
buyButton("stacks")._scripts.OnEnter(buyButton("stacks"))
check(tipLines[1] == "item:8924|x160" and table.concat(loadRequests, ",") == "8924", "missing reagent name requested: " .. tostring(tipLines[1]))
unloaded[8924] = nil
fire("ITEM_DATA_LOAD_RESULT", 8924, true)
check(tipLines[1] == "Item8924|x160", "tooltip redrawn with the loaded name: " .. tostring(tipLines[1]))
wipe(loadRequests)
unloaded[8928] = true
fire("MERCHANT_UPDATE")
check(table.concat(loadRequests, ",") == "8928", "max stack size requested while shown")
buyButton("items")._scripts.OnEnter(buyButton("items"))
merchant = {}
fire("MERCHANT_UPDATE")
check(not buyPanel._shown, "panel hidden before the data arrives")
check(not GameTooltip._shown, "hovered tooltip hidden with the panel")
merchant = { { itemID = 8924, price = 300 }, { itemID = 8925, price = 200, step = 5 } }
updates = 0
unloaded[8928] = nil
fire("ITEM_DATA_LOAD_RESULT", 8928, true)
check(updates == 0, "no refresh while the panel is hidden")
fire("MERCHANT_UPDATE")
buyer.Update = origUpdate

local itemsBox, stacksBox = buyPanel.rows.items.box, buyPanel.rows.stacks.box
bags[8924], bags[8925] = 0, 0
fire("MERCHANT_UPDATE")
itemsBox:Decrement()
check(itemsBox._text == 1 and ns.db.profile.buyAmount.items == 1, "< arrow stops at 1")
itemsBox:Increment()
check(itemsBox._text == 2 and ns.db.profile.buyAmount.items == 2 and buyPanel.rows.items.cost._text == "coin2600", "> arrow adds one and reprices: " .. tostring(buyPanel.rows.items.cost._text))
itemsBox:Decrement()
check(ns.db.profile.buyAmount.items == 1 and buyPanel.rows.items.cost._text == "coin1400", "< arrow removes one")
stacksBox:Increment(200)
check(stacksBox._text == 99 and ns.db.profile.buyAmount.stacks == 99, "spinner capped at 99")
stacksBox:Decrement(98)
itemsBox:SetFocus()
itemsBox._text = "0"
itemsBox._scripts.OnTextChanged(itemsBox, true)
check(itemsBox._text == 1 and ns.db.profile.buyAmount.items == 1 and buyButton("items")._enabled == true, "typed zero clamps to 1")
itemsBox._text = "3"
itemsBox._scripts.OnTextChanged(itemsBox, true)
check(ns.db.profile.buyAmount.items == 3 and buyButton("items")._enabled == true, "valid input saved while focused")
stacksBox:SetFocus()
wipe(purchases)
buyButton("items")._scripts.OnClick(buyButton("items"))
check(not itemsBox:HasFocus() and not stacksBox:HasFocus(), "buy click clears both inputs' focus")
check(table.concat(purchases, ",") == "8924x12", "click buys for the typed amount: " .. table.concat(purchases, ","))
fire("BAG_UPDATE_DELAYED")
fire("BAG_UPDATE_DELAYED")
ns.db.profile.buyAmount.items = 1
bags[8924], bags[8925] = 0, 0
fire("MERCHANT_UPDATE")
wipe(purchases)
bags[8924], bags[8925] = 0, 0
money = 100
fire("PLAYER_MONEY")
check(buyButton("items")._enabled == false, "buy disabled without enough gold")
check(buyPanel.rows.items.cost._text == "coin1400  金币不足" and buyPanel.rows.items.cost._color[2] == 0.3, "cost in red with not-enough-gold: " .. tostring(buyPanel.rows.items.cost._text))
buyButton("items")._scripts.OnClick(buyButton("items"))
check(#purchases == 0, "nothing bought without enough money")
money = 1000000
fire("PLAYER_MONEY")
check(buyButton("items")._enabled == true and buyPanel.rows.items.cost._text == "coin1400", "re-enabled when gold arrives")
merchant = { { itemID = 8925, price = 200 } }
fire("MERCHANT_UPDATE")
check(not buyPanel._shown, "hidden when the vendor does not sell every reagent")
merchant = { { itemID = 8924, price = 300 }, { itemID = 8925, price = 200 }, { itemID = 2452, price = 10 } }
selectRecipe(2)
check(not buyPanel._shown, "blinding powder recipe excluded")
merchant = { { itemID = 12365, price = 50 } }
selectRecipe(3)
check(not buyPanel._shown, "sharpening stone recipe excluded")
selectRecipe(1)
merchant = { { itemID = 8924, price = 300 }, { itemID = 8925, price = 200 } }
fire("MERCHANT_UPDATE")
ns:SetLanguage("enUS")
check(buyPanel.rows.stacks.unit._text == "stack(s)" and buyButton("stacks")._text == "Buy", "buy row relocalized")
bags[8924], bags[8925] = 0, 0
buyButton("items")._scripts.OnClick(buyButton("items"))
lastPrint = nil
fire("MERCHANT_CLOSED")
check(not buyPanel._shown, "hidden when the merchant closes")
check(lastPrint and lastPrint:find("reagent purchase stopped"), "closing mid-run is reported")

check(_G["BINDING_NAME_CLICK RoguePoisonApplyMain:LeftButton"] == "Apply poison to main hand"
  and _G.BINDING_HEADER_ROGUEPOISON == "Rogue Poison", "binding names follow the language")
local bindMain, bindOff = _G.RoguePoisonApplyMain, _G.RoguePoisonApplyOff
equipped[16], equipped[17] = 1000, 1001
enchants[16], enchants[17] = {}, {}
bags[8928], bags[8985], bags[20844] = 25, 5, 0
wipe(ns.db.char.lastPoison)
fire("PLAYER_ENTERING_WORLD")
check(bindMain._attr.macrotext == "/use item:8928\n/use 16" and bindOff._attr.macrotext == "/use item:8928\n/use 17",
  "keybinds fall back to the first poison: " .. tostring(bindMain._attr.macrotext))
enchants[16].poison = { hasEnchant = true, enchantType = 2, enchantID = 627, timeLeft = 30 * 60000, charges = 0 }
fire("WEAPON_ENCHANT_CHANGED")
check(ns.db.char.lastPoison[16] == "deadly" and bindMain._attr.macrotext == "/use item:8985\n/use 16", "main hand keybind remembers deadly")
check(bindOff._attr.macrotext == "/use item:8928\n/use 17", "off hand keybind unaffected")
wipe(sounds)
enchants[16].poison = nil
fire("WEAPON_ENCHANT_CHANGED")
check(#sounds == 1, "sound when the main hand poison wears off")
check(bindMain._attr.macrotext == "/use item:8985\n/use 16", "remembered poison kept after it wears off")
tick()
check(#sounds == 1, "sound plays once")
bags[8985] = 0
fire("BAG_UPDATE_DELAYED")
check(bindMain._attr.type == nil, "no keybind action when the remembered poison is out of stock")
bags[8985] = 5
enchants[17].poison = P(30 * 60000, 50)
fire("WEAPON_ENCHANT_CHANGED")
wipe(sounds)
equipped[17] = 1002
enchants[17].poison = nil
fire("PLAYER_EQUIPMENT_CHANGED")
check(#sounds == 0, "no sound when the weapon is swapped")
equipped[17] = 1001
enchants[17].poison = P(30 * 60000, 50)
fire("PLAYER_EQUIPMENT_CHANGED")
ns.db.profile.expireSound = false
enchants[17].poison = nil
fire("WEAPON_ENCHANT_CHANGED")
check(#sounds == 0, "sound setting off")
ns.db.profile.expireSound = true
enchants[17].poison = P(30 * 60000, 50)
fire("WEAPON_ENCHANT_CHANGED")
setCombat(true)
wipe(blocked)
enchants[16].poison = P(30 * 60000, 50)
fire("WEAPON_ENCHANT_CHANGED")
check(#blocked == 0, "keybind update deferred in combat")
setCombat(false)
fire("PLAYER_REGEN_ENABLED")
check(bindMain._attr.macrotext == "/use item:8928\n/use 16", "keybind updated after combat")

enchants[16].poison = P(4 * 60000, 50)
enchants[16].stone, enchants[17].stone = S(30 * 60000), S(30 * 60000)
fire("WEAPON_ENCHANT_CHANGED")
wipe(warnings); wipe(sounds)
fire("READY_CHECK", "Leader", 30)
check(warnings[1] == "Ready check: MH 4:00  50 charges" and #sounds == 1, "ready check warns about the expiring hand: " .. tostring(warnings[1]))
check(ns._broker.text == "MH |cffff4d4d4m|r  OH 30m", "broker shows minutes per hand: " .. ns._broker.text)
local brokerLines = {}
ns._broker.OnTooltipShow({ AddLine = function(_, t) brokerLines[#brokerLines+1] = t end,
  AddDoubleLine = function(_, l, r) brokerLines[#brokerLines+1] = l .. "|" .. r end })
check(brokerLines[2] == "MH|Instant Poison  4:00  50 charges" and brokerLines[3] == "MH|Elemental Sharpening Stone  30:00",
  "broker tooltip lists each hand: " .. table.concat(brokerLines, ";"))
enchants[17].poison = nil
fire("WEAPON_ENCHANT_CHANGED")
check(ns._broker.text == "MH |cffff4d4d4m|r  OH |cffff4d4d-|r", "broker marks a missing poison: " .. ns._broker.text)
wipe(warnings)
fire("READY_CHECK", "Leader", 30)
check(warnings[1] == "Ready check: MH 4:00  50 charges  OH No poison", "ready check lists both hands: " .. tostring(warnings[1]))
ns.db.profile.readyCheck = false
wipe(warnings)
fire("READY_CHECK", "Leader", 30)
check(#warnings == 0, "ready check setting off")
ns.db.profile.readyCheck = true
enchants[16].poison, enchants[17].poison = P(30 * 60000, 50), P(30 * 60000, 50)
fire("WEAPON_ENCHANT_CHANGED")
fire("READY_CHECK", "Leader", 30)
check(#warnings == 0, "no ready check warning when weapons are fine")

tradeSkillLinked = true
fire("TRADE_SKILL_SHOW")
check(next(ns.db.char.craftable) == nil, "linked profession not recorded as the player's")
tradeSkillLinked = false
fire("TRADE_SKILL_SHOW")
check(ns.db.char.craftable[8928] and ns.db.char.craftable[12404] and not ns.db.char.craftable[5530], "learned poison and stone recipes recorded")
check(ns:BetterCraftable(8927) == 8928 and ns:BetterCraftable(8928) == nil, "higher craftable rank found")
schematics[4] = { outputItemID = 18262, quantityMin = 1, learned = false, reagentSlotSchematics = {} }
fire("TRADE_SKILL_LIST_UPDATE")
check(not ns.db.char.craftable[18262], "unlearned recipe not recorded")
schematics[4].learned = true
fire("NEW_RECIPE_LEARNED", 4)
check(ns.db.char.craftable[18262], "newly learned recipe recorded")
bags[8928], bags[8927] = 0, 10
enchants[16].poison = nil
fire("BAG_UPDATE_DELAYED")
buttonFor(8927)._scripts.OnEnter(buttonFor(8927))
local tipText = table.concat(tipLines, ";")
check(tipText:find("Higher rank craftable: Item8928", 1, true), "tooltip suggests the higher rank: " .. tipText)
buttonFor(12404)._scripts.OnEnter(buttonFor(12404))
check(not table.concat(tipLines, ";"):find("Higher rank", 1, true), "no suggestion for the top rank")
bags[8928], bags[8927] = 25, 0

wipe(purchases)
knownSpells[1856] = true
bags[5140] = 2
money = 1000000
merchant = { { itemID = 5140, price = 25 } }
fire("MERCHANT_SHOW")
check(table.concat(purchases, ",") == "5140x18" and lastPrint:find("restocking Flash Powder x18", 1, true), "flash powder restocked to 20: " .. table.concat(purchases, ","))
fire("BAG_UPDATE_DELAYED")
fire("MERCHANT_UPDATE")
check(#purchases == 1, "restock runs once per visit")
fire("MERCHANT_CLOSED")
fire("MERCHANT_SHOW")
check(#purchases == 1, "nothing bought when already stocked")
fire("MERCHANT_CLOSED")
bags[5140] = 0
ns.db.profile.flashRestockTo = 45
local items = merchant
merchant = { { itemID = 9999, price = 1 } }
fire("MERCHANT_SHOW")
check(#purchases == 1, "waits for the Flash Powder entry")
merchant = { { itemID = 9999, price = 1 }, items[1] }
fire("MERCHANT_UPDATE")
for _ = 1, 3 do fire("BAG_UPDATE_DELAYED") end
check(table.concat(purchases, ",") == "5140x18,5140x20,5140x20,5140x5", "restock split into max-stack chunks: " .. table.concat(purchases, ","))
fire("MERCHANT_CLOSED")
wipe(purchases)
bags[5140] = 0
money = 100
lastPrint = nil
fire("MERCHANT_SHOW")
for _ = 1, 3 do fire("BAG_UPDATE_DELAYED") end
check(table.concat(purchases, ",") == "5140x4", "restock limited to what the player can afford: " .. table.concat(purchases, ","))
fire("MERCHANT_CLOSED")
wipe(purchases)
bags[5140] = 0
money = 10
fire("MERCHANT_SHOW")
check(#purchases == 0 and lastPrint:find("not enough gold to restock", 1, true), "no gold, no restock")
fire("MERCHANT_CLOSED")
money = 1000000
ns.db.profile.flashRestock = false
fire("MERCHANT_SHOW")
check(#purchases == 0, "restock setting off")
fire("MERCHANT_CLOSED")
ns.db.profile.flashRestock = true
knownSpells[1856] = nil
fire("MERCHANT_SHOW")
check(#purchases == 0, "no restock without Vanish")
fire("MERCHANT_CLOSED")
knownSpells[1856] = true

local function E(id) return { hasEnchant = true, enchantType = 2, enchantID = id, timeLeft = 30 * 60000, charges = 0 } end
ns.db.profile.locked = true
equipped[16], equipped[17] = 1000, 1002
enchants[16], enchants[17] = { poison = P(30 * 60000, 50) }, { poison = P(30 * 60000, 50) }
bags[12404], bags[12643], bags[18262], bags[23122] = 12, 12, 0, 0
fire("PLAYER_EQUIPMENT_CHANGED")
local dense, weight = buttonFor(12404), buttonFor(12643)
check(dense and weight and not buttonFor(18262), "dense for the dagger, weightstone for the mace: " .. shownItems())
check(dense._attr.macrotext1 == "/use item:12404\n/use 16" and dense._attr.type2 == nil, "sharpening stone only onto the dagger")
check(weight._attr.type1 == nil and weight._attr.macrotext2 == "/use item:12643\n/use 17", "weightstone only onto the mace")
weight._scripts.OnEnter(weight)
check(table.concat(tipLines, ";") == " ;OH|No sharpening stone; ;Right-click: apply to off hand", "weightstone tooltip covers only the mace: " .. table.concat(tipLines, ";"))
check(bar.hint._text == "Left: MH  Right: OH", "hint covers both stones: " .. tostring(bar.hint._text))
bags[18262] = 12
fire("BAG_UPDATE_DELAYED")
local elemental = buttonFor(18262)
check(elemental and elemental._attr.macrotext1 == "/use item:18262\n/use 16" and elemental._attr.macrotext2 == "/use item:18262\n/use 17", "elemental fits any melee weapon")
enchants[17].stone = E(1703)
fire("WEAPON_ENCHANT_CHANGED")
check(not buttonFor(12643) and buttonFor(12404) and buttonFor(18262), "weighted mace needs no more stone: " .. shownItems())
enchants[16].stone = E(2684)
fire("WEAPON_ENCHANT_CHANGED")
check(not buttonFor(12404) and not buttonFor(18262) and not buttonFor(12643), "consecrated stone counts as the dagger's stone: " .. shownItems())
wipe(sounds)
enchants[17].stone = nil
fire("WEAPON_ENCHANT_CHANGED")
check(#sounds == 1 and buttonFor(12643), "weightstone wearing off sounds and offers it again")
equipped[17] = 1001
enchants[17].stone = nil
bags[12643] = 3
fire("PLAYER_EQUIPMENT_CHANGED")
weight = buttonFor(12643)
check(weight and weight.low._text == "Low stock" and weight._attr.type1 == nil and weight._attr.type2 == nil, "low weightstone with two daggers shows but cannot be applied")
bags[12643] = 12
fire("BAG_UPDATE_DELAYED")
check(not buttonFor(12643), "stocked weightstone hidden with no blunt weapon")
ns.db.profile.poisons.weightstone = false
ns.db.profile.poisons.elemental = false
equipped[17] = 1002
fire("PLAYER_EQUIPMENT_CHANGED")
check(not buttonFor(12643), "unchecked weightstone not offered for the mace")
check(ns._broker.text:find("OH 30m", 1, true), "no checked stone fits the mace, so it is not asked for one: " .. ns._broker.text)
ns.db.profile.poisons.weightstone = true
ns.db.profile.poisons.elemental = true

enchants[16], enchants[17] = { poison = P(30 * 60000, 50) }, { poison = P(30 * 60000, 50) }
bags[12404], bags[12643], bags[23122], bags[18262], bags[287980] = 0, 0, 0, 5, 20
fire("BAG_UPDATE_DELAYED")
local elem = buttonFor(18262)
check(elem and not buttonFor(287980), "original and Forever elemental share one icon: " .. shownItems())
check(elem.count._text == 25 and elem.low._text == "", "both copies counted together: " .. tostring(elem.count._text))
check(elem._attr.macrotext1 == "/use item:18262\n/use 16", "uses the original while it is in the bags")
bags[18262] = 0
fire("BAG_UPDATE_DELAYED")
elem = buttonFor(287980)
check(elem and elem.count._text == 20 and elem._attr.macrotext2 == "/use item:287980\n/use 17", "falls back to the Forever copy in the bags")
wipe(ns.db.char.craftable)
ns.db.char.craftable[18262], ns.db.char.craftable[2862] = true, true
elem._scripts.OnEnter(elem)
check(not table.concat(tipLines, ";"):find("Higher rank", 1, true), "Forever elemental not told the original is a higher rank")
check(ns:BetterCraftable(287978) == nil and ns:BetterCraftable(287980) == nil, "same-rank originals are not higher ranks")
ns.db.char.craftable[2863] = true
check(ns:BetterCraftable(287978) == 2863, "a real higher rank still found for the Forever rough stone")
bags[287980] = 0
print("ALL PASSED")
