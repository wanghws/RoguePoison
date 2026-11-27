# RoguePoison

Poison bar for Rogues on **WoW Forever**.

- Shows the poisons and weapon stones (sharpening, weightstone, elemental,
  consecrated) in your bags at the top of the screen, one icon per type
  (highest rank you carry) with the stack count. Each stone is offered only
  for weapons it fits: sharpening for blades, weightstones for maces, staves
  and fist weapons, Elemental and Consecrated for any melee weapon.
- Appears only when a weapon has no poison, less than 10 minutes left, or fewer
  than 10 charges; when a weapon's remaining time is below the threshold, a
  live countdown (`4:59`) shows under the bar. Poison and stone are
  checked separately, so with only one of them applied the other still shows.
- Left-click applies to the main hand, right-click to the off hand (a hint
  above the icons says so).
- Hidden in combat, settings window included (it reopens after combat). In
  rest areas (inns, cities) only low-stock icons show, without the re-apply
  prompts or countdown.
- When poisons, stones, Flash Powder or Blinding Powder drop below
  10, their icon shows up with the count you have and "Low stock" under it.
- With a poison vendor and the crafting window open, two rows above "Create
  All" buy the reagents for N stacks or N items of the selected poison (set N
  by typing or with the < > arrows), with
  the total cost after each Buy button ("Not enough gold" in red when you
  cannot afford it). Only what your bags lack is bought, rounded up to the
  vendor's bundle size. Shown only at vendors that sell every reagent;
  Blinding Powder is excluded.
- Keybinds (Key Bindings → AddOns → Rogue Poison) apply poison to the main or
  off hand, reusing the poison that hand last had.
- On a ready check, a raid warning names any weapon whose poison or stone is
  missing or about to run out; a sound plays when one wears off.
- Data broker (Titan Panel, ChocolateBar…) shows the minutes left per hand,
  e.g. `MH 29m  OH 12m`.
- Flash Powder is topped up to 20 automatically at vendors that sell it.
- The poison tooltip says when you know a higher rank than the one you carry.
- Position, anchor, icon size, time/charges thresholds and stock thresholds
  are all configurable, and so is the language (English / 简体中文 / 繁體中文).
  `/rpoison` opens the settings; `/rpoison unlock` to move.

## 简体中文

**WoW Forever** 盗贼毒药栏。

- 在屏幕上方按类型显示背包中的毒药和武器石(磨刀石、平衡石、元素磨刀石、神圣磨刀石)图标(取背包里的最高等级),并显示堆叠数量。每种石头只对适用的武器提示:磨刀石用于利刃武器,平衡石用于锤、法杖和拳套,元素磨刀石和神圣磨刀石适用所有近战武器。
- 只有当武器没有毒药、剩余时间少于 10 分钟或剩余次数少于 10 时才显示;剩余时间低于阈值时会在图标栏下方显示实时倒计时(如 `主手 4:59`)。毒药和磨刀石分开检查,只涂了其中一种时,另一种仍会显示。
- 左键涂抹主手武器,右键涂抹副手武器(图标上方有提示)。
- 战斗中自动隐藏,设置界面也一样(脱战后自动恢复);在休息区域(旅店、主城)只显示库存不足的图标,不提示补涂,也不显示倒计时。
- 毒药、武器石、闪光粉或致盲粉少于 10 个时,显示它的图标和现有数量,并在图标下方提示"数量不足"。
- 同时打开商人和制造界面时,"全部制造"上方分两行显示「[< N >] 组 购买」「[< N >] 个 购买」(可输入或用左右箭头加减),一键购买制造 N 组或 N 个所选毒药所需的材料,按钮后显示总价(金币不足时红字提示):只买背包里缺的部分,并按商人的出售单位向上取整。仅在商人出售该配方全部材料时显示;致盲粉除外。
- 快捷键(按键设置 → 插件 → 盗贼毒药):主手 / 副手涂毒药,自动沿用这只手上次涂的毒药。
- 就位确认时,如果武器缺毒药 / 磨刀石或快要到期,屏幕中央会提示;毒药或磨刀石消失时播放提示音。
- 支持信息条插件(Titan Panel、ChocolateBar 等),显示每只手剩余分钟数,如 `主手 29分  副手 12分`。
- 在出售闪光粉的商人处自动补充到 20 个。
- 已学会更高等级的配方时,毒药图标的鼠标提示里会提醒。
- 位置锚点、图标大小、时间/次数阈值、库存阈值和界面语言都可在设置中修改。`/rpoison` 打开设置,`/rpoison unlock` 解锁拖动。

Changelog: [CHANGELOG.md](CHANGELOG.md)
