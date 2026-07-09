# Changelog

本文件记录项目重要变更，格式遵循 Keep a Changelog，并优先维护 `[Unreleased]`。

## [Unreleased]

### Changed（变更）

- 将根目录的 `verify_resource_chooser.py` 迁移为 `tests/test_resource_chooser_static.py`，并从 `.modinfo` 文件清单移除该测试脚本，避免把开发期校验文件打进模组包
- 修正文档项目类型：将 `AGENTS.md` 与 `README.md` 从误判的“数据科学项目”调整为 Civilization VI 游戏模组（Lua / SQL / `.modinfo`）语境
- 将建造者面板中的 BP 资源种植入口收拢为单一按钮，并改为点击后弹出“当前格子可种植资源”选择框

### Added（新增）

- 资源选择器新增"全部 / 加成 / 奢侈 / 战略"分类筛选标签条：按官方 ReportScreen + TabSupport 模式实现（`include("TabSupport")` + `Style="TabButton"`/`TabButtonSelected` 切换选中贴图 + `m_kTabs.SameSizedTabs/CenterAlignTabs` 等宽居中）；打开弹窗默认选中"全部"，点其他标签客户端过滤 `m_pendingEntries` 后重渲染，免于回 Shared 端要新数据；某类无可种资源时列表区显示 `LOC_BP_RESOURCE_CHOOSER_EMPTY_HINT` 占位提示并隐藏 Stack 内容；为承载筛选，`Shared.lua` 在 `chooserEntries` 条目新增 `ResourceClassType` 字段（取自 `GameInfo.Resources[...].ResourceClassType`），XML 在提示与列表区之间插入 `FilterTabArea`/`FilterTabContainer` 与 `TabInstance` 实例，并把 `ChooserListFrame` 下移并缩高 44px 以留出标签条空间，`Text.sql` 补 4 条标签 + 空类提示的中英文本地化串
- 资源选择器新增“地貌”分类，并把森林与原版雨林 `FEATURE_JUNGLE` 并入同一个选择器：新增 `BPBuildableFeatures` 独立数据源与 `IMPROVEMENT_BP_FEATURE_FOREST` / `IMPROVEMENT_BP_FEATURE_JUNGLE` 占位改良，图标直接复用 `ICON_FEATURE_FOREST` / `ICON_FEATURE_JUNGLE`；Lua 在 `ImprovementAddedToMap` 事件中按占位改良映射分流，资源仍走 `ResourceBuilder.SetResourceType`，地貌改走 `TerrainBuilder.SetFeatureType`；选择器条目扩展为混合结构（`EntryKind` / `FeatureType` / `FilterKey`），使森林和雨林可以和资源一样统一排序、统一筛选、统一走单入口按钮；森林按 `CIVIC_CONSERVATION` 解锁、雨林按 `TECH_BRONZE_WORKING` 解锁，并允许在已有资源但没有现有地貌的合法地块上种植
- 新增资源/地貌种植调试日志：现在从统一选择器确认、`BUILD_IMPROVEMENT` 请求发起，到 gameplay 侧资源/地貌转换尝试、成功与失败，都会打印目标资源/地貌类型、名称、玩家、单元格坐标、地形、地貌、当前资源、区域与改良状态，便于直接从 `Lua.log` 追踪“在哪个单元格上试种了什么、最后是否成功”
- 扩充 `verify_resource_chooser.py`：新增对 `Text.sql` 必含 `LOC_BP_FILTER_*` 4 条 + `LOC_BP_RESOURCE_CHOOSER_EMPTY_HINT` 的断言；对 `Shared.lua` 必含 `chooserEntries` 的 `ResourceClassType` 字段转发的断言；对 XML 必含 `FilterTabArea`/`FilterTabContainer`/`Name="TabInstance"`/`ID="EmptyHint"` 的断言；对 `BPResourceChooser.lua` 必含 `include("TabSupport")`+`AddFilterTab`+`RefreshList`+`m_kTabs.SelectTab`+4 条 `LOC_BP_FILTER_*` 标签键+空类 `Controls.EmptyHint:SetHide`/`Controls.ChooserListStack:SetHide` 切换逻辑的断言；新增对 `BP_ResourcePlanter.sql` 必含 `(R.Frequency > 0 OR R.SeaFrequency > 0)` 频率过滤谓词的断言（防回退到只按 `ResourceClassType` 过滤、从而把不会被地图自然生成的资源一并种植并触发引擎崩溃）
- 新增 [docs/workshop_description_bilingual.md](C:\Users\Echo\Documents\My Games\Sid Meier's Civilization VI\Mods\BP_ResourcePlanter\docs\workshop_description_bilingual.md)，提供基于当前功能状态的精简版 Steam Workshop 中英双语 BBCode 说明模板

### Fixed（修复）

- 修复取消资源地块限制后，泛滥平原等地貌格上的资源按钮整颗发灰：此前为去掉资源自己的细分地块要求，`BP_ResourcePlanter.sql` 把资源占位改良的 `Improvement_ValidFeatures` 全部清空，结果底层 `BUILD_IMPROVEMENT` 校验在带 `Feature` 的格子上直接判“改良不可建造”，即使该格没有资源、也只是普通泛滥平原，按钮仍会变灰。现已把资源占位改良的普通地貌白名单改为按 Domain 整桶放开：陆地资源允许全部陆地地貌（含泛滥平原/沼泽/森林/雨林/绿洲），海洋资源允许全部海洋地貌，同时继续排除自然奇观等特殊地貌
- 取消资源种植所需的具体地块限制：`BP_ResourcePlanter.sql` 现在不再按 `Resource_ValidTerrains` / `Resource_ValidFeatures` 为资源占位改良收窄合法格子，而是统一回退到 Domain 白名单，陆地资源可种在全部陆地地形、海洋资源可种在海岸 / 远洋；同时不再给资源写入任何 `Improvement_ValidFeatures`。`UI/Replacements/BP_ResourcePlantUnitPanel_Shared.lua` 与 `BP_ResourcePlanter.lua` 中的资源落点 helper 也改为不再检查具体地形 / 地貌，因此香蕉、钻石、煤等资源都不再要求原版自然生成时的细分地块条件。现仍保留已有资源不可覆盖、陆海域区分、自然奇观 / 区域 / 别国领土不可种等基础限制
- 修复“隐藏资源格仍显示资源种植项，点击后白白消耗建造者充能”：此前 `UI/Replacements/BP_ResourcePlantUnitPanel_Shared.lua` 只按科技解锁与当前地形/地貌规则过滤资源动作，没有前置检查当前格子是否已经挂了底层资源；因此像“科技未解锁所以地图上没显示，但地块实际已有资源”的草原丘陵，仍会把资源项放进统一选择器，点击后建造者先完成占位改良并消耗充能，再在 gameplay 侧因 `plot:GetResourceType() ~= -1` 被取消。现已在 Shared 端资源分支增加 `plot:GetResourceType() ~= -1` 过滤：已有任何底层资源的格子不再显示资源种植项，只保留允许共存的森林/雨林地貌入口
- 修复草原丘陵资源选择器误放行：此前统一选择器沿用了占位改良可建结果，导致裸 `TERRAIN_GRASS_HILLS` 也会显示 `可可豆 / 染料 / 丝绸 / 松露 / 香料 / 香蕉` 这类实际依赖森林或雨林的资源。现已在 `UI/Replacements/BP_ResourcePlantUnitPanel_Shared.lua` 增加按原始 `Resource_ValidTerrains` / `Resource_ValidFeatures` 判定的当前地块过滤 helper，使裸草原丘陵只保留 `羊 / 石头 / 铜 / 钻石` 等真实可落地资源；森林与雨林入口保持不变
- 修复资源点击后“消耗充能但没资源”的静默失败：此前资源分支在 `BP_ResourcePlanter.lua` 中直接调用 `ResourceBuilder.SetResourceType`，没有按资源原始落点规则再校验当前地块，也没有验证落地是否真的成功。现已在 Gameplay 侧补同语义的 plot 规则 helper，并在 `SetResourceType` 后立即检查 `plot:GetResourceType()`；若资源规则不匹配或引擎拒绝落地，会清掉占位改良、同步 property，并输出带 `resource / terrain / feature` 的明确日志，避免无提示失败
- 新增 `tests/test_grass_hill_resource_visibility.py`，覆盖“裸草原丘陵 / 森林草原丘陵 / 雨林草原丘陵”的资源可见性预期，并要求 Shared / Gameplay Lua 必须保留对应 helper 与落地校验调用点，防止后续回退到“列表误放行”或“静默失败”路径
- 修复草原丘陵上部分资源“有入口但种不下”：根因是 `BP_ResourcePlanter.sql` 之前会把同一资源的 `Resource_ValidTerrains` 与 `Resource_ValidFeatures` 一起回写到同一个占位改良上，而 Civ6 会把这两张限制表按“地形 + 地貌同时满足”处理，不是资源天然落点里的并集语义；在 Gathering Storm 给煤等资源补了额外地貌后，裸 `TERRAIN_GRASS_HILLS` 会被误判成缺森林而无法种植。现已把 `Improvement_ValidFeatures` 收紧为仅对“没有任何 `Resource_ValidTerrains` 的纯地貌资源”生成，保留香蕉/可可/丝绸等地貌资源的正确限制，同时让煤这类混合资源恢复按合法地形直接种植
- 新增 `tests/test_mixed_resource_feature_constraints.py` 回归测试：覆盖“混合地形 + 地貌资源不再被写成双重约束”与“纯地貌资源仍保留地貌要求”两类场景，防止后续回退

- 修复与“和而不同”(`DL.modinfo`) 同开时建造者 UI 回退成旧版原生列表：根因是该模组用 `LoadOrder=150000` 替换了 `UnitPanel`，高于本模组原来的 `12000`，导致 `BP_ResourcePlantUnitPanel_Shared.lua` 根本没有机会接管最终 `GetUnitActionsTable`，资源种植入口就退回成长条旧列表。现已把本模组 `BP_Resource_UnitPanel_Replace` 的 `LoadOrder` 提高到 `200000`，并让 `UnitPanel_BP_All.lua` 优先 `include("DL_UnitPanel.lua")` 后再叠加本模组的单入口选择器逻辑，这样既保留和而不同自己的 `UnitPanel` 改动，又能稳定恢复最新版独立选择器 UI
- 修复森林与雨林在选择器中的图标不合适：原先直接复用 `ICON_FEATURE_FOREST` / `ICON_FEATURE_JUNGLE`，在当前列表样式里更像灰色徽章，识别度不高；现改为统一复用原版 `ICON_UNITOPERATION_PLANT_FOREST`，让两类地貌在小尺寸按钮中更接近“树木/植树”语义
- 取消森林与雨林的解锁限制：`BPBuildableFeatures` 不再写入 `PrereqTech` / `PrereqCivic`，`BPHasPlayerUnlockedFeature` 也不再检查 `FEATURE_FOREST` 的 `AddCivic` 或 `FEATURE_JUNGLE` 的 `RemoveTech`；现在两类地貌只要地块合法就会出现在统一选择器中，资源分支仍保持原有科技 / 市政过滤不变
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
