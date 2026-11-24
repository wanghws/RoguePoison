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

function CreateFrame(_, name, parent, template)
  local f = newObj(parent, template)
  frames[#frames+1] = f
  if name then _G[name] = f end
  return f
end

UIParent = newObj()
NumberFontNormal = newObj()
GameTooltip = newObj()
local tipLines = {}
GameTooltip.SetOwner = function() wipe(tipLines) end
GameTooltip.AddLine = function(_, text) tipLines[#tipLines+1] = text end
GameTooltip.AddDoubleLine = function(_, left, right) tipLines[#tipLines+1] = left .. "|" .. right end
INVSLOT_MAINHAND, INVSLOT_OFFHAND = 16, 17
Enum = {
  ItemClass = { Weapon = 2 },
  ItemWeaponSubclass = { Axe1H = 0, Axe2H = 1, Mace1H = 4, Polearm = 6, Sword1H = 7, Sword2H = 8, Unarmed = 13, Dagger = 15 },
  WeaponSlot = { MainHand = 0, OffHand = 1, Ranged = 2 },
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
function GetInventoryItemID(_, slot) return equipped[slot] end
local clientLocale = "zhCN"
function GetLocale() return clientLocale end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
local SECRET = {}
function issecretvalue(v) return v == SECRET end
C_AddOns = { GetAddOnMetadata = function() return "1.0.0" end }
C_Item = {
  GetItemCount = function(id) return bags[id] or 0 end,
  GetItemInfoInstant = function(id) return id, "Weapon", "Dagger", "INVTYPE_WEAPON", 1, 2, id == 1002 and 4 or 15 end,
  GetItemNameByID = function(id) return "Item" .. id end,
  GetItemIconByID = function(id) return 100000 + id end,
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
function print(...) io.write("[print] ", table.concat({...}, " "), "\n") end

local libs = {}
LibStub = setmetatable({ NewLibrary = function() end }, { __call = function(_, name)
  if name == "AceGUI-3.0" then
    return FakeAceGUI
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
  "Init.lua", "Config.lua", "Modules/PoisonBar.lua", "Options.lua" }) do load(f) end

local function fire(event, ...)
  for f in pairs(eventFrames) do
    if f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
  end
end
local function tick() for _, fn in ipairs(tickers) do fn() end end

local function check(cond, msg) if not cond then error("FAIL: " .. msg, 2) end print("ok  " .. msg) end
local bar

bags = { [8928] = 25, [8985] = 5, [8925] = 3, [5140] = 2, [5173] = 20, [8924] = 15, [12404] = 4, [18262] = 12 }
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
check(shownItems() == "8928,8985,18262,flash", "instant, deadly, sharpening stone, low flash powder: " .. shownItems())
check(buttonFor(8928)._attr.macrotext1 == "/use item:8928\n/use 16", "left click macro main hand")
check(buttonFor(8928)._attr.macrotext2 == "/use item:8928\n/use 17", "right click macro off hand")
check(buttonFor(8985)._attr.macrotext1 == "/use item:8985\n/use 16", "deadly V macro")
check(buttonFor(18262)._attr.macrotext1 == "/use item:18262\n/use 16", "sharpening stone picks elemental over dense")
check(buttonFor(8985).low._text == "数量不足", "low label under deadly poison")
check(buttonFor(8985).count._text == 5 and buttonFor(8985).count._color[2] == 0.3, "deadly count in red")
check(buttonFor(8928).low._text == "" and buttonFor(18262).low._text == "", "no label under stocked items")
check(flash.low._text == "数量不足", "low label under flash powder")
check(flash.count._text == 2 and flash.count._color[2] == 0.3, "flash powder shows owned count in red")
check(flash._point[4] == 120, "flash powder icon after the poison buttons")
check(bar.hint._text == "左键主手,右键副手", "click hint above the icons")
check(bar.timer._text == "", "no countdown when weapons have no poison")
check(not blind._shown, "no blinding powder icon before Blind is learned")

enchants[16].poison = P(30 * 60000, 50)
enchants[17].poison = P(25 * 60000, 40)
tick()
check(bar._shown and shownItems() == "8985,18262,flash", "stone still offered when weapons only poisoned: " .. shownItems())
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
check(bar._shown and shownItems() == "18262", "expiring stone offers only the stone: " .. shownItems())
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
check(bar._shown and shownItems() == "18262", "dagger main hand still asks for a stone: " .. shownItems())
local stone = buttonFor(18262)
check(stone._attr.type1 == "macro" and stone._attr.type2 == nil, "stone has no right-click onto a mace off hand")
check(bar.hint._text == "左键主手", "hint omits the mace off hand for the stone")
stone._scripts.OnEnter(stone)
check(table.concat(tipLines, ";") == " ;主手|无磨刀石; ;左键:涂抹主手武器", "stone tooltip skips the mace off hand: " .. table.concat(tipLines, ";"))
equipped[16], equipped[17] = 1002, 1001
enchants[17].stone = nil
fire("PLAYER_EQUIPMENT_CHANGED")
stone = buttonFor(18262)
check(stone._attr.type1 == nil and stone._attr.macrotext2 == "/use item:18262\n/use 17", "stone only right-clicks onto a dagger off hand")
check(bar.hint._text == "右键副手", "hint names only the off hand: " .. tostring(bar.hint._text))
equipped[17] = 1002
bags[18262] = 3
fire("PLAYER_EQUIPMENT_CHANGED")
stone = buttonFor(18262)
check(stone and stone._attr.type1 == nil and stone._attr.type2 == nil, "low stone with two maces has no click action")
check(bar.hint._text == "", "no hint when no hand takes the shown stone")
stone._scripts.OnEnter(stone)
check(#tipLines == 0, "no blank lines in the stone tooltip with two maces: " .. #tipLines)
bags[18262] = 12
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
check(bar.hint._text == "Left: main hand", "click hint relocalized")
check(bar.timer._text == "Main hand 9:00", "countdown relocalized: " .. tostring(bar.timer._text))
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
print("ALL PASSED")
