local addonName, ns = ...

local AceGUI          = LibStub("AceGUI-3.0")
local AceConfig       = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceDBOptions    = LibStub("AceDBOptions-3.0")

local PROFILES_APP = addonName .. "_Profiles"

local ANCHOR_POINTS = {
    "CENTER", "LEFT", "RIGHT", "TOP", "BOTTOM",
    "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT",
}

local function AddSeparator(container, text)
    local heading = AceGUI:Create("Heading")
    heading:SetText(text or " ")
    heading:SetFullWidth(true)
    container:AddChild(heading)
    return heading
end

local function AddCheckbox(container, label, getValue, setValue)
    local w = AceGUI:Create("CheckBox")
    w:SetLabel(label)
    w:SetValue(getValue())
    w:SetCallback("OnValueChanged", function(_, _, val)
        setValue(val)
        ns:RefreshAll()
    end)
    container:AddChild(w)
    return w
end

local function AddSlider(container, label, minV, maxV, step, getValue, setValue, relativeWidth)
    local w = AceGUI:Create("Slider")
    w:SetLabel(label)
    w:SetSliderValues(minV, maxV, step)
    w:SetValue(getValue())
    w:SetRelativeWidth(relativeWidth or 0.5)
    w:SetCallback("OnValueChanged", function(_, _, val)
        setValue(val)
        ns:RefreshAll()
    end)
    container:AddChild(w)
    return w
end

local function AddDropdown(container, label, values, order, getValue, setValue)
    local w = AceGUI:Create("Dropdown")
    w:SetLabel(label)
    w:SetList(values, order)
    w:SetValue(getValue())
    w:SetRelativeWidth(0.5)
    w:SetCallback("OnValueChanged", function(_, _, val)
        setValue(val)
        ns:RefreshAll()
    end)
    container:AddChild(w)
    return w
end

local function AddLabel(container, text)
    local w = AceGUI:Create("Label")
    w:SetText(text)
    w:SetFullWidth(true)
    container:AddChild(w)
    return w
end

local function AnchorValueTable(L)
    local values = {}
    for _, p in ipairs(ANCHOR_POINTS) do
        values[p] = L["ANCHOR_" .. p]
    end
    return values
end

local function LanguageValues(L)
    local values, order = { auto = L["LANG_AUTO"] }, { "auto" }
    for _, lang in ipairs(ns.LANGUAGES) do
        values[lang.code] = lang.name
        order[#order + 1] = lang.code
    end
    return values, order
end

local function DrawGeneralTab(container)
    local L, db = ns.L, ns.db.profile

    AddSeparator(container, L["TAB_GENERAL"])
    local languages, languageOrder = LanguageValues(L)
    AddDropdown(container, L["OPT_LANGUAGE"], languages, languageOrder,
        function() return ns.db.global.locale end,
        function(v) ns:SetLanguage(v) end)
    AddCheckbox(container, L["OPT_ENABLED"],
        function() return db.enabled end,
        function(v) db.enabled = v end)
    AddCheckbox(container, L["OPT_LOCKED"],
        function() return db.locked end,
        function(v) db.locked = v end)
    AddCheckbox(container, L["OPT_MINIMAP_ICON"],
        function() return not ns.db.global.minimap.hide end,
        function(v)
            ns.db.global.minimap.hide = not v
            ns:SetupMinimapIcon()
            local icon = LibStub("LibDBIcon-1.0", true)
            if icon and icon:IsRegistered(addonName) then
                icon:Refresh(addonName, ns.db.global.minimap)
            end
        end)

    AddSeparator(container, L["SEC_APPEARANCE"])
    AddSlider(container, L["OPT_ICON_SIZE"], 16, 80, 1,
        function() return db.iconSize end,
        function(v) db.iconSize = v end)
    AddSlider(container, L["OPT_ICON_SPACING"], 0, 30, 1,
        function() return db.spacing end,
        function(v) db.spacing = v end)
    AddSlider(container, L["OPT_FONT_SIZE"], 8, 32, 1,
        function() return db.fontSize end,
        function(v) db.fontSize = v end)

    AddSeparator(container, L["SEC_POSITION"])
    local anchorValues = AnchorValueTable(L)
    AddDropdown(container, L["OPT_ANCHOR_POINT"], anchorValues, ANCHOR_POINTS,
        function() return db.anchor.point end,
        function(v) db.anchor.point = v end)
    AddDropdown(container, L["OPT_RELATIVE_POINT"], anchorValues, ANCHOR_POINTS,
        function() return db.anchor.relativePoint end,
        function(v) db.anchor.relativePoint = v end)
    AddSlider(container, L["OPT_X_OFFSET"], -1200, 1200, 1,
        function() return db.anchor.x end,
        function(v) db.anchor.x = v end)
    AddSlider(container, L["OPT_Y_OFFSET"], -800, 800, 1,
        function() return db.anchor.y end,
        function(v) db.anchor.y = v end)
end

local function DrawChecksTab(container)
    local L, db = ns.L, ns.db.profile

    AddSeparator(container, L["SEC_BUFF_CHECK"])
    AddSlider(container, L["OPT_TIME_THRESHOLD"], 0, 60, 1,
        function() return db.timeThreshold end,
        function(v) db.timeThreshold = v end)
    AddSlider(container, L["OPT_CHARGES_THRESHOLD"], 0, 100, 1,
        function() return db.chargesThreshold end,
        function(v) db.chargesThreshold = v end)

    AddSeparator(container, L["SEC_STOCK_CHECK"])
    AddCheckbox(container, L["OPT_SHOW_WARNINGS"],
        function() return db.showWarnings end,
        function(v) db.showWarnings = v end)
    AddCheckbox(container, L["OPT_TRACK_FLASH"],
        function() return db.trackFlash end,
        function(v) db.trackFlash = v end)
    AddCheckbox(container, L["OPT_TRACK_BLIND"],
        function() return db.trackBlind end,
        function(v) db.trackBlind = v end)
    AddSlider(container, L["OPT_POISON_THRESHOLD"], 0, 100, 1,
        function() return db.poisonThreshold end,
        function(v) db.poisonThreshold = v end)
    AddSlider(container, L["OPT_FLASH_THRESHOLD"], 0, 100, 1,
        function() return db.flashThreshold end,
        function(v) db.flashThreshold = v end)
    AddSlider(container, L["OPT_BLIND_THRESHOLD"], 0, 100, 1,
        function() return db.blindThreshold end,
        function(v) db.blindThreshold = v end)
end

local function DrawPoisonsTab(container)
    local L, db = ns.L, ns.db.profile

    AddSeparator(container, L["TAB_POISONS"])
    for _, poison in ipairs(ns.POISON_TYPES) do
        local key = poison.key
        local w = AddCheckbox(container, L["POISON_" .. key],
            function() return db.poisons[key] end,
            function(v) db.poisons[key] = v end)
        w:SetImage(C_Item.GetItemIconByID(poison.ranks[#poison.ranks]))
    end
    AddLabel(container, L["OPT_POISONS_HELP"])
end

local function RegisterProfileOptions()
    if ns._profileOptionsRegistered then return end
    ns._profileOptionsRegistered = true
    AceConfig:RegisterOptionsTable(PROFILES_APP, AceDBOptions:GetOptionsTable(ns.db))
end

local function BuildTabContent(container, group)
    container:ReleaseChildren()
    if group == "profiles" then
        RegisterProfileOptions()
        AceConfigDialog:Open(PROFILES_APP, container)
        return
    end
    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("Flow")
    container:AddChild(scroll)
    if group == "general" then DrawGeneralTab(scroll)
    elseif group == "checks" then DrawChecksTab(scroll)
    elseif group == "poisons" then DrawPoisonsTab(scroll)
    end
end

local function TabList(L)
    return {
        { text = L["TAB_GENERAL"],  value = "general"  },
        { text = L["TAB_CHECKS"],   value = "checks"   },
        { text = L["TAB_POISONS"],  value = "poisons"  },
        { text = L["TAB_PROFILES"], value = "profiles" },
    }
end

local function SelectedGroup()
    local tab = ns._optionsTab
    local status = tab and (tab.status or tab.localstatus)
    return status and status.selected
end

function ns:OpenOptions(group)
    local L = self.L
    if InCombatLockdown() then
        self._reopenOptions = self._reopenOptions or { group = group }
        return
    end
    if self._optionsFrame then
        self._optionsFrame:Show()
        if group then self._optionsTab:SelectTab(group) end
        return
    end

    local f = AceGUI:Create("Frame")
    f:SetTitle(L["ADDON_TITLE"])
    f:SetStatusText("v" .. ns.version)
    f:SetLayout("Fill")
    f:SetWidth(640)
    f:SetHeight(520)
    f:SetCallback("OnClose", function(widget)
        ns.db.profile.locked = true
        ns:RefreshAll()
        AceGUI:Release(widget)
        ns._optionsFrame = nil
        ns._optionsTab = nil
    end)
    self._optionsFrame = f

    local tab = AceGUI:Create("TabGroup")
    tab:SetLayout("Fill")
    tab:SetTabs(TabList(L))
    tab:SetCallback("OnGroupSelected", function(container, _, group)
        BuildTabContent(container, group)
    end)
    tab:SelectTab(group or "general")
    f:AddChild(tab)
    self._optionsTab = tab
end

function ns:RefreshOptionsUI()
    local group = SelectedGroup()
    if group then self._optionsTab:SelectTab(group) end
end

function ns:RelocalizeOptions()
    if not self._optionsFrame then return end
    self._optionsFrame:SetTitle(self.L["ADDON_TITLE"])
    self._optionsTab:SetTabs(TabList(self.L))
    self:RefreshOptionsUI()
end

local function HideForCombat()
    if not ns._optionsFrame then return end
    ns._reopenOptions = { group = SelectedGroup(), locked = ns.db.profile.locked }
    ns._optionsFrame:Hide()
end

local function RestoreAfterCombat()
    local state = ns._reopenOptions
    if not state then return end
    ns._reopenOptions = nil
    ns:OpenOptions(state.group)
    if state.locked ~= nil then ns:SetLocked(state.locked) end
end

local function RegisterBlizzardCategory()
    local L = ns.L
    local panel = CreateFrame("Frame")
    panel.name = L["ADDON_TITLE"]

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(L["ADDON_TITLE"])

    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -16)
    button:SetSize(180, 22)
    button:SetText("/rpoison")
    button:SetScript("OnClick", function()
        HideUIPanel(SettingsPanel)
        HideUIPanel(GameMenuFrame)
        ns:OpenOptions()
    end)

    local category = Settings.RegisterCanvasLayoutCategory(panel, L["ADDON_TITLE"])
    Settings.RegisterAddOnCategory(category)
end

local options = {}
ns:RegisterModule("options", options)

function options:OnPlayerLogin()
    RegisterBlizzardCategory()
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            HideForCombat()
        else
            RestoreAfterCombat()
        end
    end)
end
