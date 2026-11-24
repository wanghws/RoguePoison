local _, ns = ...

local defaults = {
    profile = {
        enabled           = true,
        locked            = true,
        iconSize          = 36,
        spacing           = 4,
        fontSize          = 14,
        anchor            = { point = "TOP", relativePoint = "TOP", x = 0, y = -120 },
        timeThreshold     = 10,
        chargesThreshold  = 10,
        showWarnings      = true,
        poisonThreshold   = 10,
        trackFlash        = true,
        flashThreshold    = 10,
        trackBlind        = true,
        blindThreshold    = 10,
        buyAmount         = { stacks = 1, items = 1 },
        poisons = {
            instant     = true,
            deadly      = true,
            wound       = true,
            crippling   = true,
            mindnumbing = true,
            sharpening  = true,
        },
    },
    char = {
        seen = {},
    },
    global = {
        minimap = { hide = false },
        locale  = "auto",
    },
}

function ns:InitializeDB()
    self.db = LibStub("AceDB-3.0"):New("RoguePoisonDB", defaults, true)
    self.db.RegisterCallback(self, "OnProfileChanged", function() self:RefreshAll() end)
    self.db.RegisterCallback(self, "OnProfileCopied",  function() self:RefreshAll() end)
    self.db.RegisterCallback(self, "OnProfileReset",   function() self:RefreshAll() end)
end

ns.defaults = defaults
