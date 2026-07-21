# BP_ResourcePlanter - 项目指令

## 项目目标

BP_ResourcePlanter 是《文明 VI》模组 "Builder Plants Resources"。它让建造者通过独立入口直接种植资源与地貌，最终落地为真实游戏对象，而不是假的占位改良。

## 核心工作流

1. 先读需求，再确认影响范围。
2. 优先检查现有 Lua / SQL / UI / `modinfo` / 本地化逻辑，找共享入口再改。
3. 修改时保持最小 diff，优先复用现有校验与选择器逻辑。
4. 任何影响种植规则、UI 文案、兼容层或加载顺序的改动，都要同步检查 `BP_ResourcePlanter.modinfo`、`docs/workshop_description_bilingual.md` 和 `README.md`。
5. 完成后更新 `CHANGELOG.md` 的 `[Unreleased]`。

## 工程原则

- 真实落地优先，正常流程不要留下假的改良。
- 保持 `BP_ResourcePlanter.sql`、`BP_ResourcePlanter_Compatibility.sql`、`BP_ResourcePlanter_Text.sql` 与 Lua 行为一致。
- 优先复用现有 helper、validator 和 UI 数据收集逻辑。
- 兼容层和加载顺序改动要谨慎，先看 `modinfo` 再动代码。
- 中英文本要同步，公开介绍以 `docs/workshop_description_bilingual.md` 为准。

## 默认语言

默认使用简体中文。

## 联网与搜索

优先使用本地文件和 `codebase-memory-mcp`；只有在本地信息不足或信息可能变化时才联网。

## 贡献记录

默认使用 `docs/contribution.bac` 记录协作过程。不要写入密钥、私密提示词或无关隐私。

## Codex CLI 特定说明

- 代码发现优先用 `search_graph`、`trace_path`、`get_code_snippet`。
- 引用文件时用绝对路径。
- 只改当前任务相关文件，避免无关重构。

## 变更记录与版本

- 影响行为、结构、工作流、指令文件或关键配置的变更，都要记到 `CHANGELOG.md` 的 `[Unreleased]`。
- `docs/` 里非 `plans/` 的说明文档如果过时了，要一起更新。

## 有机更新原则

- `AGENTS.md` 是唯一长期维护的通用指令源。
- `CLAUDE.md` 只做适配层，保持 `@./AGENTS.md` 引用。
- 规则变更时，优先同步 README、workshop 文案和模组描述。
