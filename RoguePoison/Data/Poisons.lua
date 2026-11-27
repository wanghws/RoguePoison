local _, ns = ...

ns.ITEM = {
    FLASH_POWDER    = 5140,
    BLINDING_POWDER = 5530,
}

ns.SPELLS = {
    VANISH = { 1856, 1857 },
    BLIND  = { 2094 },
}

ns.POISON_TYPES = {
    { key = "instant", kind = "poison", fits = "any",
      ranks    = { 8928, 8927, 8926, 6950, 6949, 6947 },
      enchants = { 625, 624, 623, 325, 324, 323 } },
    { key = "deadly", kind = "poison", fits = "any",
      ranks    = { 20844, 8985, 8984, 2893, 2892 },
      enchants = { 2630, 627, 626, 8, 7 } },
    { key = "wound", kind = "poison", fits = "any",
      ranks    = { 10922, 10921, 10920, 10918 },
      enchants = { 706, 705, 704, 703 } },
    { key = "crippling", kind = "poison", fits = "any",
      ranks    = { 3776, 3775 },
      enchants = { 603, 22 } },
    { key = "mindnumbing", kind = "poison", fits = "any",
      ranks    = { 9186, 6951, 5237 },
      enchants = { 643, 23, 35 } },
    { key = "sharpening", kind = "stone", fits = "bladed",
      ranks    = { 12404, 7964, 2871, 2863, 2862 },
      reissues = { [2862] = { 287978 } },
      enchants = { 1643, 483, 14, 13, 40 } },
    { key = "weightstone", kind = "stone", fits = "blunt",
      ranks    = { 12643, 7965, 3241, 3240, 3239 },
      enchants = { 1703, 484, 21, 20, 19 } },
    { key = "elemental", kind = "stone", fits = "melee",
      ranks    = { 18262 },
      reissues = { [18262] = { 287980 } },
      enchants = { 2506 } },
    { key = "consecrated", kind = "stone", fits = "melee",
      ranks    = { 23122 },
      enchants = { 2684, 7896 } },
}

ns.RANK_INDEX = {}
ns.ITEM_KIND = {}
ns.ITEM_TYPE = {}
ns.SAME_RANK = {}
ns.ENCHANT_KIND = {}
ns.ENCHANT_TYPE = {}
ns.TYPE_BY_KEY = {}
for _, poison in ipairs(ns.POISON_TYPES) do
    ns.TYPE_BY_KEY[poison.key] = poison
    for index, rankItem in ipairs(poison.ranks) do
        local same = { rankItem }
        for _, copy in ipairs(poison.reissues and poison.reissues[rankItem] or {}) do
            same[#same + 1] = copy
        end
        for _, itemID in ipairs(same) do
            ns.RANK_INDEX[itemID] = index
            ns.ITEM_KIND[itemID] = poison.kind
            ns.ITEM_TYPE[itemID] = poison
            ns.SAME_RANK[itemID] = same
        end
    end
    for _, enchantID in ipairs(poison.enchants) do
        ns.ENCHANT_KIND[enchantID] = poison.kind
        ns.ENCHANT_TYPE[enchantID] = poison
    end
end

function ns:KnowsAny(spells)
    for _, spellID in ipairs(spells) do
        if IsPlayerSpell(spellID) then return true end
    end
    return false
end
