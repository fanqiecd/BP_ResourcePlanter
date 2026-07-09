# BP_ResourcePlanter

这是一个《席德·梅尔的文明VI》模组，核心目标是让建造者通过 Lua + SQL 驱动的占位改良流程，在合法地块上种植资源与森林/雨林地貌，并把大量可种植项目收敛成单一入口后再弹出选择框。

## 当前功能

- 建造者面板只显示一个“种植资源”入口，不再把几十个资源按钮平铺在原版 BUILD 列表里
- 点击入口后，只展示当前地块真正允许种植、且当前玩家已经解锁的资源 / 地貌
- 资源图标与名称直接复用游戏资源表定义，避免手工维护一份资源清单
- 森林与雨林作为独立地貌项接入同一选择器，不伪装成 `RESOURCE_*`
- 资源落地后会在同帧清除占位改良，地块最终只留下真实资源
- 森林和雨林落地后同样会在同帧清除占位改良，地块最终只留下真实地貌
- 占位改良不再把资源前置回写到 `Improvements.PrereqTech` / `PrereqCivic`，因此科技树 / 市政树不会再出现多余的占位图标
- 森林与雨林不再绑定科技 / 市政前置，只要格子合法就能种植
- 读档或旧存档加载时会自动清理残留占位改良，避免假改良长期留在地图上

## 当前技术栈

- `Lua`：监听地块改良事件，并把占位改良转换为真实资源或真实地貌
- `SQL`：注册占位改良、建造限制与本地化描述
- `UI XML / UI Lua`：把资源种植动作折叠成单入口，并弹出资源选择器
- `.modinfo`：声明模组元数据与加载顺序

## 主要文件

```text
BP_ResourcePlanter/
├── BP_ResourcePlanter.modinfo
├── BP_ResourcePlanter.sql
├── BP_ResourcePlanter_Text.sql
├── BP_ResourcePlanter.lua
├── tests/
│   ├── test_feature_only_resource_terrains.py
│   ├── test_buildable_features.py
│   ├── test_resource_chooser_static.py
│   └── test_visible_resource_wrapper.py
├── UI/
│   ├── Additions/
│   │   ├── BPResourceChooser.lua
│   │   └── BPResourceChooser.xml
│   └── Replacements/
│       ├── BP_ResourcePlantUnitPanel_Shared.lua
│       └── UnitPanel_BP_All.lua
├── AGENTS.md
├── CLAUDE.md
├── CHANGELOG.md
└── docs/
    ├── contribution.bac
    └── plans/
```

## 开发工作流

1. 修改 `BP_ResourcePlanter.sql` 或 `BP_ResourcePlanter_Text.sql` 调整数据层、可建条件和文本。
2. 修改 `BP_ResourcePlanter.lua` 调整资源生成、校验和清理逻辑。
3. 修改 `UI/Additions/` 或 `UI/Replacements/` 调整资源选择器与建造者面板入口。
4. 检查 `BP_ResourcePlanter.modinfo` 的加载动作和顺序是否仍正确。
5. 运行 `python tests/test_resource_chooser_static.py` 做静态回归检查。
6. 进入游戏验证建造菜单、资源 / 地貌名称、落地效果、科技/市政树显示和地块视觉表现。

## 安装与验证

将整个文件夹放到 Civilization VI 的 `Mods` 目录后启用模组，再在游戏内检查：

- 建造者菜单是否出现单一的“种植资源”入口
- 点击后是否只弹出当前格子真正可种植的资源列表
- 点击后是否能在“地貌”分类里看到森林 / 雨林
- 尚未解锁对应科技 / 市政的资源是否不会提前出现在列表中
- 森林 / 雨林是否在未解锁任何相关科技或市政时也能正常出现在“地貌”分类里
- 资源名称和图标是否正确显示
- 森林 / 雨林名称与图标是否正确显示
- 科技树 / 市政树中是否不再出现额外的占位资源图标
- 资源种植完成后是否只留下真实资源
- 森林 / 雨林种植完成后是否只留下真实地貌，且可与已有资源共存
- 旧存档重载后是否仍能正确清理占位改良

## AI 协作

- 通用项目指令在 `AGENTS.md`
- Claude Code 适配层在 `CLAUDE.md`
- 重要变更需要同步记录到 `CHANGELOG.md`
- 协作过程默认记录到 `docs/contribution.bac`
