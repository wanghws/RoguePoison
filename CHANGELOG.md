# Changelog

## v1.2.0

- At a poison vendor with the crafting window open, two rows above "Create
  All" buy the reagents for N stacks or N items of the selected poison: only
  what your bags lack, rounded up to the vendor's bundle size, with the total
  cost shown (red "Not enough gold" when you cannot afford it). The poison bar
  no longer shows in rest areas (inns, cities).
- 在毒药商处打开制造界面时，"全部制造"上方新增两行「[N] 组 购买」「[N] 个 购买」，
  一键购买制造所选毒药所需的材料：只买背包里缺的部分，按商人出售单位向上取整，
  并显示总价（金币不足时红字提示）。在休息区域（旅店、主城）不再显示毒药栏。

## v1.1.0

- Added a live countdown (`4:59`) under the bar for each weapon whose poison or
  sharpening stone is about to expire, and Blinding Powder low-stock tracking
  after learning Blind (own toggle and threshold). Poisons and sharpening
  stones are now checked separately, so the bar stays up when a weapon has only
  one of them (WoW Forever allows both at once); stones are only offered for
  bladed weapons, so maces and fist weapons get no stone prompt, click binding
  or hint.
- 武器毒药或磨刀石即将到期时，在图标栏下方显示各武器的实时倒计时（如
  `主手 4:59`），并新增「致盲粉」库存检查（学会致盲后生效，设置中有独立开关和
  数量阈值）。毒药和磨刀石改为分开检查，武器只涂了其中一种时图标栏不再消失
  （WoW Forever 可同时涂两者）；磨刀石只针对利刃武器，锤和拳套不再提示磨刀石，
  也不绑定点击、不显示点击提示。

## v1.0.0

- First public release for Rogues on WoW Forever. A poison and sharpening stone
  bar appears when a weapon's poison is missing, under 10 minutes or under 10
  charges (left-click main hand, right-click off hand); low poisons, stones and
  Flash Powder show their icon with a "Low stock" label. Hidden in combat, with
  a full settings panel and English / 简体中文 / 繁體中文 switchable in game.
- WoW Forever 盗贼专用插件首个公开版本。武器没有毒药、剩余不足 10 分钟或不足 10 次时
  显示毒药与磨刀石栏(左键主手,右键副手);毒药、磨刀石和闪光粉数量不足时显示图标并
  在下方提示"数量不足"。战斗中自动隐藏,提供完整设置界面,可在游戏内切换英文、
  简体中文、繁体中文。
