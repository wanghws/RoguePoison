local addonName, ns = ...
_G.RoguePoison = ns

ns.name    = addonName
ns.version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "0.0.0"
ns.modules = {}
ns.ICON    = [[Interface\AddOns\RoguePoison\Media\icon]]

local CHAT_PREFIX = "|cff6fdc6f" .. addonName .. "|r: "

function ns:Print(msg)
    print(CHAT_PREFIX .. msg)
end

function ns:IsRogue()
    local _, class = UnitClass("player")
    return class == "ROGUE"
end

function ns:RegisterModule(id, mod)
    self.modules[id] = mod
end

function ns:RefreshAll()
    for _, mod in pairs(self.modules) do
        if type(mod.Refresh) == "function" then
            mod:Refresh()
        end
    end
end

function ns:SetLocked(locked)
    self.db.profile.locked = locked
    self:RefreshAll()
    if self.RefreshOptionsUI then self:RefreshOptionsUI() end
end

function ns:SetLanguage(choice)
    self.db.global.locale = choice
    self:ApplyLocale(choice)
    if self._broker then self._broker.label = self.L["ADDON_TITLE"] end
    self:ApplyBindingNames()
    self:RefreshAll()
    if self.RelocalizeOptions then
        C_Timer.After(0, function() self:RelocalizeOptions() end)
    end
end

function ns:ApplyBindingNames()
    local L = self.L
    _G.BINDING_HEADER_ROGUEPOISON = L["ADDON_TITLE"]
    _G["BINDING_NAME_CLICK RoguePoisonApplyMain:LeftButton"] = L["BIND_APPLY_MAIN"]
    _G["BINDING_NAME_CLICK RoguePoisonApplyOff:LeftButton"] = L["BIND_APPLY_OFF"]
end

function ns:SetupMinimapIcon()
    if self._minimapReady then return end
    local LDB     = LibStub("LibDataBroker-1.1", true)
    local LDBIcon = LibStub("LibDBIcon-1.0", true)
    if not LDB or not LDBIcon then return end
    local L = self.L
    local broker = LDB:NewDataObject(addonName, {
        type  = "data source",
        icon  = ns.ICON,
        label = L["ADDON_TITLE"],
        text  = "",
        OnClick = function(_, button)
            if button == "RightButton" then
                self:SetLocked(not self.db.profile.locked)
            elseif self.OpenOptions then
                self:OpenOptions()
            end
        end,
        OnTooltipShow = function(tip)
            tip:AddLine(L["ADDON_TITLE"])
            if self.AddWeaponStatus and self:AddWeaponStatus(tip) then tip:AddLine(" ") end
            tip:AddLine(L["MINIMAP_TIP_LEFT"], 1, 1, 1)
            tip:AddLine(L["MINIMAP_TIP_RIGHT"], 1, 1, 1)
            tip:AddLine("|cff9d9d9d/rpoison|r")
        end,
    })
    LDBIcon:Register(addonName, broker, self.db.global.minimap)
    self._broker = broker
    self._minimapReady = true
end

local bootstrap = CreateFrame("Frame")
bootstrap:RegisterEvent("ADDON_LOADED")
bootstrap:RegisterEvent("PLAYER_LOGIN")
bootstrap:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        ns:InitializeDB()
        ns:ApplyLocale(ns.db.global.locale)
        ns:ApplyBindingNames()
        for _, mod in pairs(ns.modules) do
            if type(mod.OnDBReady) == "function" then mod:OnDBReady() end
        end
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterAllEvents()
        if not ns:IsRogue() then return end
        ns.active = true
        ns:SetupMinimapIcon()
        for _, mod in pairs(ns.modules) do
            if type(mod.OnPlayerLogin) == "function" then mod:OnPlayerLogin() end
        end
    end
end)

SLASH_ROGUEPOISON1 = "/rpoison"
SLASH_ROGUEPOISON2 = "/poison"
SlashCmdList["ROGUEPOISON"] = function(msg)
    if not ns.active then
        ns:Print(ns.L["MSG_NOT_ROGUE"])
        return
    end
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "reset" then
        ns.db:ResetProfile()
        ns:Print(ns.L["MSG_RESET"])
    elseif msg == "unlock" then
        ns:SetLocked(false)
        ns:Print(ns.L["MSG_UNLOCKED"])
    elseif msg == "lock" then
        ns:SetLocked(true)
        ns:Print(ns.L["MSG_LOCKED"])
    elseif ns.OpenOptions then
        ns:OpenOptions()
    end
end
