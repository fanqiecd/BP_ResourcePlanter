# BP_ResourcePlanter

`Builder Plants Resources`

让建造者通过独立入口在格子上直接种植资源与地貌，最终留下真实对象，而不是假的占位改良。

## 内容

- 加成、奢侈、战略资源
- 海域资源
- 森林与雨林的同入口选择

## 关键文件

- `BP_ResourcePlanter.lua`：种植逻辑与校验
- `BP_ResourcePlanter.sql`：游戏数据注册
- `BP_ResourcePlanter_Compatibility.sql`：兼容层包装
- `BP_ResourcePlanter_Text.sql`：本地化文本
- `UI/Additions/*`：建造者入口和选择器 UI

## 使用

- 放到《文明 VI》的 Mods 目录并在游戏内启用
- 规则和文案变更时，一起更新 `BP_ResourcePlanter.modinfo`、`docs/workshop_description_bilingual.md` 和 `CHANGELOG.md`

## 文档

- 协作指令：`AGENTS.md` / `CLAUDE.md`
- 公开介绍：`docs/workshop_description_bilingual.md`
- 计划文档：`docs/plans/`
