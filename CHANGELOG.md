# Changelog

本文件记录项目重要变更，格式遵循 Keep a Changelog，并优先维护 `[Unreleased]`。

## [Unreleased]

### Changed（变更）

- 将根目录的 `verify_resource_chooser.py` 迁移为 `tests/test_resource_chooser_static.py`，并从 `.modinfo` 文件清单移除该测试脚本，避免把开发期校验文件打进模组包
- 修正文档项目类型：将 `AGENTS.md` 与 `README.md` 从误判的“数据科学项目”调整为 Civilization VI 游戏模组（Lua / SQL / `.modinfo`）语境
- 将建造者面板中的 BP 资源种植入口收拢为单一按钮，并改为点击后弹出“当前格子可种植资源”选择框

### Added（新增）

- 资源选择器新增"全部 / 加成 / 奢侈 / 战略"分类筛选标签条：按官方 ReportScreen + TabSupport 模式实现（`include("TabSupport")` + `Style="TabButton"`/`TabButtonSelected` 切换选中贴图 + `m_kTabs.SameSizedTabs/CenterAlignTabs` 等宽居中）；打开弹窗默认选中"全部"，点其他标签客户端过滤 `m_pendingEntries` 后重渲染，免于回 Shared 端要新数据；某类无可种资源时列表区显示 `LOC_BP_RESOURCE_CHOOSER_EMPTY_HINT` 占位提示并隐藏 Stack 内容；为承载筛选，`Shared.lua` 在 `chooserEntries` 条目新增 `ResourceClassType` 字段（取自 `GameInfo.Resources[...].ResourceClassType`），XML 在提示与列表区之间插入 `FilterTabArea`/`FilterTabContainer` 与 `TabInstance` 实例，并把 `ChooserListFrame` 下移并缩高 44px 以留出标签条空间，`Text.sql` 补 4 条标签 + 空类提示的中英文本地化串
- 扩充 `verify_resource_chooser.py`：新增对 `Text.sql` 必含 `LOC_BP_FILTER_*` 4 条 + `LOC_BP_RESOURCE_CHOOSER_EMPTY_HINT` 的断言；对 `Shared.lua` 必含 `chooserEntries` 的 `ResourceClassType` 字段转发的断言；对 XML 必含 `FilterTabArea`/`FilterTabContainer`/`Name="TabInstance"`/`ID="EmptyHint"` 的断言；对 `BPResourceChooser.lua` 必含 `include("TabSupport")`+`AddFilterTab`+`RefreshList`+`m_kTabs.SelectTab`+4 条 `LOC_BP_FILTER_*` 标签键+空类 `Controls.EmptyHint:SetHide`/`Controls.ChooserListStack:SetHide` 切换逻辑的断言；新增对 `BP_ResourcePlanter.sql` 必含 `(R.Frequency > 0 OR R.SeaFrequency > 0)` 频率过滤谓词的断言（防回退到只按 `ResourceClassType` 过滤、从而把不会被地图自然生成的资源一并种植并触发引擎崩溃）

### Fixed（修复）

- 更新资源选择器静态回归检查：移除已过时的 `BP_StrategicResourceVisible` 维多利亚专属断言，改为检查当前通用 `BP_VISIBLE_RESOURCE_WRAPPER_*` / `BP_RESOURCE_CLASS_WRAPPER_*` 与 Lua 地块 property 同步方案
- 修复真实 Civ6 Gameplay 数据库中第 6 步 wrapper SQL 半加载失败的问题：`Database.log` 报 `no such column: RequirementId` 后只替换了 `REQUIREMENT_PLOT_RESOURCE_VISIBLE`，没有继续把蒸汽时代维多利亚 `PLOT_HAS_STRATEGIC_RESOURCE_ENGLAND` 里的 `REQUIRES_PLOT_HAS_STRATEGIC` 包装成资源类别 property 兜底，导致种植出来的战略资源仍吃不到“所有战略资源 +2 [ICON_Production] 生产力”。现已给临时表关键列显式加 `AS RequirementId`，并把 `RequirementSetRequirements` 的引用替换改为限定目标表列的 `EXISTS` 写法，避免 Civ6 SQLite 执行器对未限定 `RequirementId` 的解析差异；本次保留 Lua property 同步设计不变
- 补齐“种出来的资源吃不到依赖资源类别判定的领袖/加成”这一半兼容层：此前 `BP_ResourcePlanter.sql` / `BP_ResourcePlanter.lua` 只兜底了 `REQUIREMENT_PLOT_RESOURCE_VISIBLE`，但蒸汽时代维多利亚的“所有战略资源 +2 [ICON_Production] 生产力”实际要求 `REQUIRES_PLOT_HAS_STRATEGIC`（即 `REQUIREMENT_PLOT_RESOURCE_CLASS_TYPE_MATCHES`）与 `REQUIRES_PLOT_HAS_VISIBLE_RESOURCE` 同时成立，因此运行时种出来的煤/铁/石油仍会漏掉这 2 生产。现已新增对 `REQUIREMENT_PLOT_RESOURCE_CLASS_TYPE_MATCHES` 中 `BONUS/LUXURY/STRATEGIC` 三类 requirement 的同类 wrapper，并在 `BP_ResourcePlanter.lua` 同步 `BP_HasBonusResourceForYieldBonuses` / `BP_HasLuxuryResourceForYieldBonuses` / `BP_HasStrategicResourceForYieldBonuses` 三个地块 property，使这类按资源类别发放的标准数据驱动加成也能在种植后立即生效
- 修复种植"地图不会随机生成的资源"导致游戏崩溃：根因是 `BP_ResourcePlanter.sql` 收集可种植资源时仅按 `ResourceClassType IN (BONUS/LUXURY/STRATEGIC)` 过滤，把原版 6 个垄断/独特奢侈（`Resources.xml:207-212` 的 `RESOURCE_JEANS`/`PERFUME`/`COSMETICS`/`TOYS`/`CINNAMON`/`CLOVES`，`ResourceClassType=LUXURY` 但 `Frequency=0` 且 `SeaFrequency=0`）一并注册成占位改良；这些资源不会被地图自然刷出、也没有 `Resource_ValidTerrains` 行，引擎对它们的 spawn/渲染路径未初始化，`ResourceBuilder.SetResourceType` 在客户端会崩溃。已在该 INSERT 的 WHERE 叠加 `(R.Frequency > 0 OR R.SeaFrequency > 0)` 谓词——这是 Civ6 `Resources` 表里唯一可判"是否随机生成"的列（参 `Base/Assets/Gameplay/Data/Schema/01_GameplaySchema.sql:2325-2344`，两列均 NOT NULL DEFAULT 0），单一频率谓词可同时排除 6 个垄断奢侈并自动适配未来 DLC/第三方资源，无需维护黑名单
- 修复“种出来的资源吃不到依赖可见性判定的领袖/加成”只兼容蒸汽时代维多利亚的问题：根因不是某个领袖数值写错，而是 Civ6 引擎对 gameplay 运行时 `ResourceBuilder.SetResourceType` 新塞进去的资源，不会稳定重算这类 `REQUIREMENT_PLOT_RESOURCE_VISIBLE` 参与的 modifier 判定。现已把 `BP_ResourcePlanter.sql` 从维多利亚专属补丁改成标准 requirement 泛兼容层：自动扫描全部 `RequirementType = REQUIREMENT_PLOT_RESOURCE_VISIBLE` 的 requirement，为每个命中项包一层 `TEST_ANY` wrapper，保留原版“资源可见”判定，同时新增 `BP_VisibleResourceForYieldBonuses` 地块属性兜底；`BP_ResourcePlanter.lua` 会在种植成功和读档初始化时同步所有资源格的该属性，使运行时种出的资源也能立即触发同类官方/模组领袖、总督、万神殿、建筑等标准数据驱动加成，而不再依赖固定的 Firaxis `ModifierId` / `RequirementId`
- 修复香蕉、可可豆、染料、丝绸、香料、糖、松露被误判成海洋资源，导致能种进海岸/湖泊却不能正常种在陆地：根因是 `BP_ResourcePlanter.sql` 第 1 步只用 `Resource_ValidTerrains` 推 `BPBuildableResources.Domain`，而这 7 个原版资源只有 `Resource_ValidFeatures`、没有 `Resource_ValidTerrains`，于是被错误回退成 `DOMAIN_SEA`；第 3 步再把“无显式地形规则”的资源整桶套上海洋地形白名单，最终把纯陆地资源送进海里。现已把 Domain 推导升级为“先看资源合法地形，再看资源合法地貌对应的 `Feature_ValidTerrains`”，并把 `Improvement_ValidTerrains` 的 fallback 改成优先取地貌对应地形并集；只有资源既没有地形规则也没有地貌规则时，才回退到 Domain 白名单。这样上述 7 个资源会落回贴近原版自然生成规则的陆地地形，不再出现在海岸/湖泊建造菜单里

- 修复资源选择器文字模糊：标题与正文原用 `WindowHeader` / `BodyTextDark18`，二者均带 `FontStyle="glow"` + 低 alpha 浅蓝光晕（见 `Base/Assets/UI/Civ6_Styles.xml:47,89`），渲染出来发糊；改用官方 `EventPopup` 系列同款样式 `EventPopupTitle`（`FontStyle="Shadow"`）与 `EventPopupDescription`（MyriadPro-Regular 16、无 glow，靠低 alpha 近黑描边保证清晰），与 `DLC/Babylon/UI/Additions/HeroesPopup` 同位置一致。
- 修复资源选择器滚轮只在滚动条上才生效：根因是外层 `<Grid ID="ChooserPanel" ConsumeMouse="1">` 吞掉了悬停在面板空白区的鼠标事件，导致滚轮只在直接命中 ScrollBar 时才命中测试通过；官方同类弹窗（HeroesPopup `Window`、EventPopup `Window`、GreatPeoplePopup `RecruitedArea`、ReportScreen `Main`）的 Grid/Box 都不设此属性，`AutoScrollBar="1"` 已隐含“悬停在面板任意位置可滚”。已将 `ConsumeMouse="1"` 改为 `ConsumeMouseOver="1"`（与 EspionagePopup 同款，仅阻止鼠标穿透到背后世界，不阻断滚轮），并去掉实例行按钮 `Button` 上的 `ConsumeMouse="1"`，使悬停在条目上时滚轮仍能驱动列表滚动。
- 修复资源选择框 UI 按钮点击无反应：原因是 `BP_ResourcePlanter.modinfo` 在 `InGameActions` 的 `ImportFiles` 段重复声明了已被 `AddUserInterfaces`（同名 `.lua` 自动加载到 InGame 子 context）和 `ReplaceUIScript`（加载到 UnitPanel context）接管的 `BPResourceChooser.lua` 与 `UnitPanel_BP_All.lua`，导致它们在顶层 context 再次执行时 `Controls.*` 解析为 `nil`，按钮回调无法注册；已从 `ImportFiles` 移除这两条，仅保留供 `include()` 使用的 `BP_ResourcePlantUnitPanel_Shared.lua`
- 收紧 `BPResourceChooser.lua` 初始化：移除脚本顶层立即调用的 `BPEnsureTopLevelParent()`，改为在 `BPInitializeChooser()` 内统一注册回调并防御性检查 `Controls` 是否已绑定，避免加载早期 WorldPopups 未就绪导致的竞态
- 修复资源选择弹窗底部取消按钮跑出边框、标题与说明未居中：经核对官方 `Base/Assets/UI/Popups/` 与 `DLC/Babylon/UI/Additions/HeroesPopup.xml` 后按 EventPopup/HeroesPopup 模式重排内部布局——`ChooserTitle` 放进 `EventPopupTitleBar` 标题栏 Grid，Label 不设 `Size`，仅用 `Anchor="C,C" + Align="Center" + WrapWidth` 居中（参 `EventPopup.xml:32`）；`ChooserPrompt` 套一层 `Anchor="C,T"` 的固定宽 Container，Label 同样不设 `Size`、靠 `Align="Center" + WrapWidth` 居中（参 `EventPopup.xml:34-35`），避免直接给 Label 设 `Size` 时 `WrapWidth` 换行造成视觉错位；`CancelButton` 的 `Anchor="C,B" Offset="0,-34"` 改为 `Offset="0,15"`，因 ForgeUI 中 `C,B` 配【负】y 偏移会把元素推到 Grid 底边之外，官方所有底部主按钮一律用【正】y 偏移贴回 Grid 内底（`BoostUnlockedPopup.xml:38=0,15`、`TechCivicCompletedPopup.xml:55=0,25`、`EventPopup.xml:68=0,23`、`HeroesPopup.xml:36=0,26`；唯一负值 `GreatPeoplePopup.xml:107=0,-10` 是装饰性计数小按钮，不可类比）
- 修复科技/市政树中资源旁边多出一张额外图标：根因是把资源的 `PrereqTech` / `PrereqCivic` 直接同步进了占位改良 `Improvements`，导致科技树把 `IMPROVEMENT_BP_*` 也当成正式解锁项展示；现已去掉这层 SQL 回写，改由 `UnitPanel` 共享 Lua 在本地按玩家已拥有科技/市政过滤可种植资源，因此建造解锁时机不变，但科技树不再展示占位改良
- 修复 `verify_resource_chooser.py` 中方向错误的回归断言：旧断言要求 `ChooserTitle` 保留 `Size="parent,parent"`、`CancelButton` 保留 `Offset="0,-34"`——这两条恰好把"bug 状态"当成了"必须保持的状态"，反而会在按官方模式重排居中、按钮回贴 Grid 内底时误报失败；已改成正向断言：`ChooserTitle` 不得含 `Size="parent,parent"` 且必须含 `Align="Center"` 与 `WrapWidth`，`ChooserPrompt` 必须含 `Align="Center"` 与 `WrapWidth`，`CancelButton` 不得出现 `Offset="0,-` 负 y 偏移
- 扩充 `verify_resource_chooser.py`：新增对 `InGameActions.ImportFiles` 段不得重复声明 `BPResourceChooser.lua` / `UnitPanel_BP_All.lua` 的回归断言；新增对 `<AddUserInterfaces>` 段不得写 `<LoadOrder>`、XML 必须含 `FullScreenVignetteConsumer` / `ScreenConsumer`、Lua 必须用 `PopupPriority.Low` 且不得再出现 `ChangeParent` / `LookUpControl("/InGame/WorldPopups")` / `PopupPriority.Current` 的断言；新增对 XML 必须使用 `EventPopupTitle`/`EventPopupDescription`、不得使用 `WindowHeader`/`BodyTextDark18`、`ChooserPanel` 不得设 `ConsumeMouse="1"` 的字体与滚轮回归断言

## [1.0.0] - 2026-07-05

### Added（新增）

- 初始化 AI 项目指令文件：生成 `AGENTS.md`、`CLAUDE.md`、`README.md` 与 `.gitignore`
- 配置项目工程原则、工作流和变更记录规范
- 初始化 BAC 贡献记录：默认托管文件为 `docs/contribution.bac`

### Changed（变更）

### Fixed（修复）

---

## 记录规则

- 必须记录影响项目行为、结构、工作流、工程原则、指令文件或关键配置的变更
- 记录应说明改了什么、为什么改，以及影响范围
- 版本号遵循 SemVer：bug fix 递增修订号，新功能递增次版本号，破坏性变更递增主版本号

```markdown
## [版本号] - YYYY-MM-DD

### Added（新增）
- 新增了 XXX：用途是 YYY

### Changed（变更）
- 修改了 XXX：原因是 YYY，影响是 ZZZ

### Fixed（修复）
- 修复了 XXX：表现是 YYY，修复方式是 ZZZ
```
