local ROOT = arg[1] or "RoguePoison"
local inCombat = false
local blocked = {}
local bags, enchants, equipped = {}, {}, { [16] = 1000, [17] = 1001 }
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
  return function() end
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
INVSLOT_MAINHAND, INVSLOT_OFFHAND = 16, 17
Enum = { ItemClass = { Weapon = 2 } }
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
function issecretvalue() return false end
C_AddOns = { GetAddOnMetadata = function() return "1.0.0" end }
C_Item = {
  GetItemCount = function(id) return bags[id] or 0 end,
  GetItemInfoInstant = function(id) return id, "Weapon", "Dagger", "INVTYPE_WEAPON", 1, 2, 15 end,
  GetItemNameByID = function(id) return "Item" .. id end,
  GetItemIconByID = function(id) return 100000 + id end,
  RequestLoadItemDataByID = function() end,
}
C_PaperDollInfo = { GetTemporaryEnchantmentInfo = function(slot) return enchants[slot] end }
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

check(bar._shown, "bar shown when weapons have no poison")
local btns = {}
for _, f in ipairs(frames) do if f._attr.type1 then btns[#btns+1] = f end end
check(#btns == 3, "three buttons (instant, deadly, sharpening stone)")
check(btns[3]._attr.macrotext1 == "/use item:18262\n/use 16", "sharpening stone picks elemental over dense")
check(btns[1]._attr.macrotext1 == "/use item:8928\n/use 16", "left click macro main hand: " .. btns[1]._attr.macrotext1)
check(btns[1]._attr.macrotext2 == "/use item:8928\n/use 17", "right click macro off hand")
check(btns[2]._attr.macrotext1 == "/use item:8985\n/use 16", "deadly V macro")
local warnText
for _, f in ipairs(frames) do local t = rawget(f, "text"); if t and t._text then warnText = t._text end end
print("warning: " .. tostring(warnText))
check(warnText and warnText:find("Item8985") and warnText:find("Item5140"), "warns deadly, flash powder")
check(not warnText:find("Item8925") and not warnText:find("Item5173") and not warnText:find("Item8924"), "no reagent warnings")
check(not warnText:find("Item8928 ") and not warnText:find("Item18262"), "no warning for stocked items")

enchants[16] = { remainingTimeMs = 30 * 60000, chargesRemaining = 50 }
enchants[17] = { remainingTimeMs = 25 * 60000, chargesRemaining = 40 }
tick()
check(not bar._shown, "bar hidden when both weapons poisoned")

enchants[17] = { remainingTimeMs = 25 * 60000, chargesRemaining = 8 }
tick()
check(bar._shown, "bar shown when off hand charges < 10")

enchants[17] = { remainingTimeMs = 25 * 60000, chargesRemaining = 40 }
tick()
check(not bar._shown, "hidden again")

setCombat(true)
fire("PLAYER_REGEN_DISABLED")
enchants[16] = { remainingTimeMs = 9 * 60000, chargesRemaining = 50 }
tick()
bags[8928] = 0
fire("BAG_UPDATE_DELAYED")
check(#blocked == 0, "no protected calls in combat (" .. table.concat(blocked, ",") .. ")")
check(not bar._shown, "visibility frozen in combat")
check(not visible(bar), "bar hidden by combat driver")
setCombat(false)
fire("PLAYER_REGEN_ENABLED")
check(bar._shown and visible(bar), "bar shown after combat when main hand < 10m")
local visible = 0
for _, f in ipairs(btns) do if f._shown then visible = visible + 1 end end
check(visible == 2, "instant hidden after running out, deadly and stone remain")
for _, f in ipairs(frames) do local t = rawget(f, "text"); if t and t._text then warnText = t._text end end
check(warnText:find("Item8928") ~= nil, "warns instant VI at 0 (remembered)")

equipped[17] = nil
fire("PLAYER_EQUIPMENT_CHANGED")
check(btns[1]._attr.type2 == nil, "no right-click action without off hand weapon")

ns.db.profile.locked = false
ns:RefreshAll()
check(bar._shown, "unlocked shows bar")
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
check(ns.db.global.locale == "auto" and L["WARN_LOW_STOCK"] == "数量不足:", "auto follows zhCN client")
local moverLabel
for _, f in ipairs(frames) do local lbl = rawget(f, "label"); if lbl then moverLabel = lbl end end
ns:SetLanguage("enUS")
check(L["WARN_LOW_STOCK"] == "Low stock:", "switch to English")
check(moverLabel._text == "Drag to move", "mover label relocalized")
for _, fn in ipairs(deferred) do fn() end
ns:SetLanguage("zhTW")
check(L["WARN_LOW_STOCK"] == "數量不足:", "switch to Traditional Chinese")
clientLocale = "deDE"
ns:SetLanguage("auto")
check(L["WARN_LOW_STOCK"] == "Low stock:", "unsupported client falls back to English")
check(L["NO_SUCH_KEY"] == "NO_SUCH_KEY", "missing key returns key")
clientLocale = "zhCN"
ns:SetLanguage("auto")
ns.db.profile.enabled = false
ns:RefreshAll()
check(not bar._shown, "disabled hides bar")
print("ALL PASSED")
