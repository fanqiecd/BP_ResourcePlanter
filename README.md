# BP_ResourcePlanter

这是一个《席德·梅尔的文明VI》模组，核心目标是让建造者通过 Lua + SQL 驱动的假改良流程，在合法地块上种植资源。

## 当前技术栈

- `Lua`：监听地块改良事件，并把占位改良转换为真实资源
- `SQL`：注册假改良、建造限制、前置条件与本地化描述
- `.modinfo`：声明模组元数据与加载顺序

## 主要文件

```text
BP_ResourcePlanter/
├── BP_ResourcePlanter.modinfo
├── BP_ResourcePlanter.sql
├── BP_ResourcePlanter_Text.sql
├── BP_ResourcePlanter.lua
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
3. 检查 `BP_ResourcePlanter.modinfo` 的加载动作和顺序是否仍正确。
4. 进入游戏验证建造菜单、资源名称、资源落地效果和地块视觉表现。

## 安装与验证

将整个文件夹放到 Civilization VI 的 `Mods` 目录后启用模组，再在游戏内检查：

- 建造者菜单是否出现对应资源项目
- 资源名称和图标是否正确显示
- 资源种植完成后是否只留下真实资源
- 旧存档重载后是否仍能正确清理占位改良

## AI 协作

- 通用项目指令在 `AGENTS.md`
- Claude Code 适配层在 `CLAUDE.md`
- 重要变更需要同步记录到 `CHANGELOG.md`
- 协作过程默认记录到 `docs/contribution.bac`
