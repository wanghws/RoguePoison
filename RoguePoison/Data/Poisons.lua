local _, ns = ...

ns.ITEM = {
    FLASH_POWDER = 5140,
}

ns.POISON_TYPES = {
    { key = "instant",     ranks = { 8928, 8927, 8926, 6950, 6949, 6947 } },
    { key = "deadly",      ranks = { 20844, 8985, 8984, 2893, 2892 } },
    { key = "wound",       ranks = { 10922, 10921, 10920, 10918 } },
    { key = "crippling",   ranks = { 3776, 3775 } },
    { key = "mindnumbing", ranks = { 9186, 6951, 5237 } },
    { key = "sharpening",  ranks = { 18262, 12404, 7964, 2871, 2863, 2862 } },
}

ns.RANK_INDEX = {}
for _, poison in ipairs(ns.POISON_TYPES) do
    for index, itemID in ipairs(poison.ranks) do
        ns.RANK_INDEX[itemID] = index
    end
end
