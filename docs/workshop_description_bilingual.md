# Workshop Description

## 中文版（BBCode）

```text
[h1]建造者可建造资源[/h1]

让建造者通过独立入口在地块上直接种植资源与地貌。

正常流程会直接落下真实资源或真实地貌，地图上不会留下假的改良设施。旧版本存档中残留的占位改良会在读档时自动尝试清理。

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
[*]资源必须满足当前科技 / 市政解锁，并且不能种在已有资源、改良、区域、自然奇观或他国领土上
[*]森林与雨林可与已有资源共存，但不能叠加到现有地貌上
[*]AI 默认禁用，避免 AI 无限制刷资源
[/list]

[h2]实现效果[/h2]
[list]
[*]建造者面板使用单一入口；有多个可选项目时弹出当前格子的资源 / 地貌列表
[*]完成后会立刻转成真实资源 / 地貌
[*]不会在正常流程中留下假的占位改良
[*]读档后会自动尝试清理旧版本残留的占位改良
[/list]

[h2]说明[/h2]
[list]
[*]这是“种植资源 / 地貌”，不是自动附带矿井、农场、种植园、牧场、渔船等开发改良
[*]若地块底层本来就有一个尚未因科技解锁而显示出来的资源，资源种植入口会被隐藏，避免白白消耗建造者充能
[*]仅收录地图可以自然生成的加成、奢侈和战略资源；不会自然生成的特殊资源会被排除
[*]本模组不替换 UnitPanel，可直接兼容 Builder Lag Fix、“和而不同”及其他建造者面板模组
[*]资源列表会自动读取 Resources 表，通常可兼容遵循标准定义且按常规顺序加载的 DLC 与资源模组
[*]若第三方资源模组使用了非常规定义或极晚的数据库加载顺序，可能需要单独适配
[/list]
```

## English Version (BBCode)

```text
[h1]Builder Plants Resources[/h1]

This mod lets Builders plant resources and features directly on tiles through an independent entry.

The normal flow places the real resource or feature directly, without leaving a fake improvement on the map. Leftover placeholder improvements from older saves are cleaned up when the save is loaded.

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
[*]Resources must be unlocked by the current technology / civic and cannot be planted on tiles with an existing resource, improvement, district, natural wonder, or foreign ownership
[*]Forest and Rainforest can coexist with an existing resource, but cannot be placed on top of an existing feature
[*]AI is disabled by default to prevent unlimited resource spam
[/list]

[h2]How It Works[/h2]
[list]
[*]Builders use a single menu entry; when multiple entries are available, a chooser lists valid resources and features for the current tile
[*]Finished placement is immediately converted into a real resource / feature
[*]The normal flow does not leave a fake placeholder improvement behind
[*]Save reload will attempt to clean up leftover placeholder improvements from older versions
[/list]

[h2]Notes[/h2]
[list]
[*]This mod plants resources / features, but does not automatically add Mines, Farms, Plantations, Camps, Fishing Boats, or other improvements
[*]If a tile already contains a hidden resource that is not revealed yet by your current tech, the resource planting entry stays hidden to avoid wasting Builder charges
[*]Only map-spawnable Bonus, Luxury, and Strategic resources are included; special resources that never spawn naturally are excluded
[*]This mod does not replace UnitPanel, so it works alongside Builder Lag Fix, Harmony in Diversity / DL, and other Builder panel mods
[*]The resource list is data-driven from the Resources table, so it usually works with DLC and resource mods that follow standard definitions and normal database load order
[*]Third-party resource mods with non-standard definitions or very late database load order may need manual compatibility work
[/list]
```
