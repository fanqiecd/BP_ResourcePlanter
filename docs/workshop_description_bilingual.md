# Workshop Description

## 中文版（BBCode）

```text
[h1]建造者可建造资源[/h1]

让建造者在地块上直接种植资源与地貌。

本模组会先放下一个隐藏的占位改良，再立刻把它转换成真实资源或真实地貌，因此地图上最终留下的是原版对象本身，而不是假的改良设施。

[h2]支持内容[/h2]
[list]
[*]加成资源、奢侈资源、战略资源
[*]海域资源
[*]森林与雨林（作为地貌项目加入同一选择器）
[/list]

[h2]种植规则[/h2]
[list]
[*]陆地资源可种在全部陆地地形与普通陆地地貌上（包含泛滥平原、沼泽、森林、雨林、绿洲等）
[*]海洋资源可种在海岸 / 远洋与普通海洋地貌上
[*]不能在已有资源、自然奇观、已有区域或他国领土上种植资源
[*]森林与雨林可与已有资源共存，但不能叠加到现有地貌上
[*]AI 默认禁用，避免 AI 无限制刷资源
[/list]

[h2]实现效果[/h2]
[list]
[*]建造者面板使用单一入口，再弹出当前格子的可种植项目列表
[*]完成后会立刻转成真实资源 / 地貌
[*]不会永久留下假的占位改良
[*]读档后会自动尝试清理残留的占位改良
[/list]

[h2]说明[/h2]
[list]
[*]这是“种植资源 / 地貌”，不是自动附带矿井、农场、种植园、牧场、渔船等开发改良
[*]若地块底层本来就有一个尚未因科技解锁而显示出来的资源，资源种植入口会被隐藏，避免白白消耗建造者充能
[*]已兼容“和而不同”等大型 UnitPanel 替换模组的单入口资源按钮方案
[*]资源列表会自动读取 Resources 表，通常可兼容遵循标准定义的 DLC 与大多数资源模组
[*]若第三方资源模组使用了非常规定义，可能需要单独适配
[/list]
```

## English Version (BBCode)

```text
[h1]Builder Plants Resources[/h1]

This mod lets Builders plant resources and features directly on tiles.

Each plantable entry first places a hidden placeholder improvement, then immediately converts it into a real resource or real feature. The final map object is the original game object, not a fake improvement left behind.

[h2]Supported Content[/h2]
[list]
[*]Bonus, Luxury, and Strategic resources
[*]Sea resources
[*]Forest and Rainforest (added as feature entries in the same chooser)
[/list]

[h2]Placement Rules[/h2]
[list]
[*]Land resources can be planted on all land terrains and ordinary land features, including Floodplains, Marsh, Forest, Rainforest, and Oasis
[*]Sea resources can be planted on coast / ocean and ordinary sea features
[*]Resources cannot be planted on tiles that already have a resource, natural wonder, district, or foreign ownership
[*]Forest and Rainforest can coexist with an existing resource, but cannot be placed on top of an existing feature
[*]AI is disabled by default to prevent unlimited resource spam
[/list]

[h2]How It Works[/h2]
[list]
[*]Builders use a single menu entry, then open a chooser for valid entries on the current tile
[*]Finished placement is immediately converted into a real resource / feature
[*]No fake placeholder improvement is left behind permanently
[*]Save reload will attempt to clean up leftover placeholder improvements automatically
[/list]

[h2]Notes[/h2]
[list]
[*]This mod plants resources / features, but does not automatically add Mines, Farms, Plantations, Camps, Fishing Boats, or other improvements
[*]If a tile already contains a hidden resource that is not revealed yet by your current tech, the resource planting entry stays hidden to avoid wasting Builder charges
[*]The single-entry resource button is already adapted for large UnitPanel replacement mods such as Harmony in Diversity / DL
[*]The resource list is data-driven from the Resources table, so it usually works with DLC and most resource mods that follow standard definitions
[*]Some heavily customized third-party resource mods may still need manual compatibility work
[/list]
```
