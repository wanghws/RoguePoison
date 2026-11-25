local _, ns = ...

ns.ITEM = {
    FLASH_POWDER    = 5140,
    BLINDING_POWDER = 5530,
}

ns.POISON_TYPES = {
    { key = "instant", kind = "poison",
      ranks    = { 8928, 8927, 8926, 6950, 6949, 6947 },
      enchants = { 625, 624, 623, 325, 324, 323 } },
    { key = "deadly", kind = "poison",
      ranks    = { 20844, 8985, 8984, 2893, 2892 },
      enchants = { 2630, 627, 626, 8, 7 } },
    { key = "wound", kind = "poison",
      ranks    = { 10922, 10921, 10920, 10918 },
      enchants = { 706, 705, 704, 703 } },
    { key = "crippling", kind = "poison",
      ranks    = { 3776, 3775 },
      enchants = { 603, 22 } },
    { key = "mindnumbing", kind = "poison",
      ranks    = { 9186, 6951, 5237 },
      enchants = { 643, 23, 35 } },
    { key = "sharpening", kind = "stone",
      ranks    = { 18262, 12404, 7964, 2871, 2863, 2862 },
      enchants = { 2506, 1643, 483, 14, 13, 40, 2684 } },
}

ns.RANK_INDEX = {}
ns.ITEM_KIND = {}
ns.ENCHANT_KIND = {}
for _, poison in ipairs(ns.POISON_TYPES) do
    for index, itemID in ipairs(poison.ranks) do
        ns.RANK_INDEX[itemID] = index
        ns.ITEM_KIND[itemID] = poison.kind
    end
    for _, enchantID in ipairs(poison.enchants) do
        ns.ENCHANT_KIND[enchantID] = poison.kind
    end
end
