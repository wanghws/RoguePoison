local _, ns = ...

local DEFAULT = "enUS"
local active = GetLocale()

ns.locales = {}

ns.LANGUAGES = {
    { code = "enUS", name = "English" },
    { code = "zhCN", name = "简体中文" },
    { code = "zhTW", name = "繁體中文" },
}

function ns:NewLocale(code)
    local strings = {}
    self.locales[code] = strings
    return strings
end

function ns:ApplyLocale(choice)
    active = (choice and choice ~= "auto") and choice or GetLocale()
end

ns.L = setmetatable({}, {
    __index = function(_, key)
        local strings = ns.locales[active]
        local value = strings and strings[key]
        if value == nil then value = ns.locales[DEFAULT][key] end
        return value or key
    end,
})
