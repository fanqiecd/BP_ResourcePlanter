from pathlib import Path


ROOT = Path(__file__).resolve().parent

modinfo = (ROOT / "BP_ResourcePlanter.modinfo").read_text(encoding="utf-8")
main_sql = (ROOT / "BP_ResourcePlanter.sql").read_text(encoding="utf-8")
text_sql = (ROOT / "BP_ResourcePlanter_Text.sql").read_text(encoding="utf-8")
shared_lua = (ROOT / "UI" / "Replacements" / "BP_ResourcePlantUnitPanel_Shared.lua").read_text(encoding="utf-8")
chooser_xml = (ROOT / "UI" / "Additions" / "BPResourceChooser.xml").read_text(encoding="utf-8")
chooser_lua = (ROOT / "UI" / "Additions" / "BPResourceChooser.lua").read_text(encoding="utf-8")

assert "ReplaceUIScript" in modinfo, "modinfo 缺少 ReplaceUIScript"
assert "<LuaContext>UnitPanel</LuaContext>" in modinfo, "UnitPanel 替换未接入"
assert "UnitPanel_BP_All.lua" in modinfo, "modinfo 未引用总包装脚本"
assert "BPResourceChooser.xml" in modinfo, "modinfo 未接入资源选择器 UI"

# AddUserInterfaces 同名 .lua 会自动在 InGame 子 context 加载；如果再被
# InGameActions 内的 ImportFiles 段导入，则该 .lua 会在顶层 context 再执行一次，
# 此时 Controls.* 全为 nil，按钮注册回调失败 -> 点击无反应。
# 注意：只检查 InGameActions 内的 ImportFiles 段，<Files> 清单段照列不构成加载行为。
ingame_actions_start = modinfo.find("<InGameActions>")
ingame_actions_end = modinfo.find("</InGameActions>")
assert ingame_actions_start != -1 and ingame_actions_end != -1, "modinfo 缺少 <InGameActions> 段"
ingame_actions = modinfo[ingame_actions_start:ingame_actions_end]

assert "<File>UI/Additions/BPResourceChooser.lua</File>" not in ingame_actions, (
    "BPResourceChooser.lua 不能通过 ImportFiles 重复导入；同名 .lua 由 "
    "AddUserInterfaces 的 BPResourceChooser.xml 自动加载到子 context。"
)
# UnitPanel_BP_All.lua 已由 ReplaceUIScript 加载到 UnitPanel context，重复出现在
# ImportFiles 会让它在顶层 context 再执行一份，include / 事件订阅双双失效。
assert "<File>UI/Replacements/UnitPanel_BP_All.lua</File>" not in ingame_actions, (
    "UnitPanel_BP_All.lua 只应通过 ReplaceUIScript 的 LuaReplace 加载到 "
    "UnitPanel context，不能用 ImportFiles 在 InGameActions 内重复声明。"
)

# <AddUserInterfaces> 段内不应有 <LoadOrder>:
# 遍历所有官方 .modinfo(DLC/Babylon 等)无一在 AddUserInterfaces 块内写 LoadOrder。
addui_start = modinfo.find("<AddUserInterfaces")
assert addui_start != -1, "modinfo 缺少 <AddUserInterfaces> 段"
addui_end = modinfo.find("</AddUserInterfaces>", addui_start)
addui_block = modinfo[addui_start:addui_end]
assert "<LoadOrder>" not in addui_block, (
    "<AddUserInterfaces> 段内不应声明 <LoadOrder>；"
    "Firaxis 官方约定(参 DLC/Babylon/Babylon.modinfo 的 Heroes_InGameUI)只写 <Context>InGame</Context>。"
)
assert "<Context>InGame</Context>" in addui_block, "<AddUserInterfaces> 段缺少 <Context>InGame</Context>"

for tag in (
    "LOC_BP_RESOURCE_CHOOSER_TITLE",
    "LOC_BP_RESOURCE_CHOOSER_PROMPT",
    "LOC_BP_RESOURCE_CHOOSER_ACTION_DESCRIPTION",
    "LOC_BP_RESOURCE_CHOOSER_AVAILABLE",
    # 资源分类筛选标签 + 空类提示(全部/加成/奢侈/战略)
    "LOC_BP_FILTER_ALL",
    "LOC_BP_FILTER_BONUS",
    "LOC_BP_FILTER_LUXURY",
    "LOC_BP_FILTER_STRATEGIC",
    "LOC_BP_RESOURCE_CHOOSER_EMPTY_HINT",
):
    assert tag in text_sql, f"缺少本地化标签: {tag}"

# 占位改良不应再把资源前置同步到 Improvements.PrereqTech / PrereqCivic：
# 这会让科技树 / 市政树把占位改良也当成正式解锁项显示，出现资源旁边多一张图标。
for forbidden_sql in (
    "UPDATE Improvements\nSET PrereqTech =",
    "UPDATE Improvements\nSET PrereqCivic =",
):
    assert forbidden_sql not in main_sql, (
        "占位改良的科技/市政前置不应直接写回 Improvements；"
        "应改由 UnitPanel 在本地按玩家已解锁内容过滤可种植资源。"
    )

# 可种植资源必须叠加"地图自然生成"过滤（参 Base/Assets/Gameplay/Data/
# Schema/01_GameplaySchema.sql:2325-2344 的 Resources.Frequency/SeaFrequency）：
# 原版 6 个垄断/独特奢侈 RESOURCE_JEANS/PERFUME/COSMETICS/TOYS/CINNAMON/CLOVES
# 的两个频率都为 0,不会被地图刷出,引擎未初始化其种植/渲染路径；
# 强行种植会触发 ResourceBuilder.SetResourceType 在客户端崩溃,必须排除。
# 用单一频率谓词而非黑名单,以自动适配未来 DLC/模组新增资源。
assert "R.Frequency" in main_sql and "R.SeaFrequency" in main_sql, (
    "BP_ResourcePlanter.sql 必须基于 Resources.Frequency / SeaFrequency 过滤可种植资源"
)
# 用精确谓词串匹配,确保后续改动不会把过滤悄悄删掉。
# 两列都是 NOT NULL DEFAULT 0,无需 COALESCE；这里只要求语义上"至少一侧 > 0"。
assert "(R.Frequency > 0 OR R.SeaFrequency > 0)" in main_sql, (
    "BPBuildableResources 收集 SQL 必须叠加 (R.Frequency > 0 OR R.SeaFrequency > 0) 谓词,"
    "排除不会随机生成的资源以避免引擎崩溃"
)

for needle in (
    "BPCollectResourcePlantActions",
    "BPCreateResourceChooserAction",
    "BPShowResourceChooser",
    "LuaEvents.BP_ResourceChooser_Open",
    "LuaEvents.BP_ResourceChooser_PlantSelected.Add",
    "BPHasPlayerUnlockedResource",
    "playerTechs:HasTech",
    "playerCulture:HasCivic",
    'table.insert(actionsTable["SPECIFIC"], 1, chooserAction)',
    # 资源分类字段必须转发给选择器,供 UI 端按 全部/加成/奢侈/战略 过滤
    "ResourceClassType = resourceInfo and resourceInfo.ResourceClassType or nil",
):
    assert needle in shared_lua, f"替换脚本缺少关键逻辑: {needle}"

for needle in (
    'ID="ChooserRoot"',
    'ID="ChooserScrollPanel"',
    'ID="ChooserListStack"',
    'Name="ResourceEntryInstance"',
    # 官方模态弹窗骨架的必备元素(FullScreenVignetteConsumer 暗化背景 +
    # BoxButton ScreenConsumer 吞世界点击/滚轮 / 右键关闭)。
    'FullScreenVignetteConsumer',
    'ID="ScreenConsumer"',
    'ConsumeMouseButton="1"',
    'ConsumeMouseWheel="1"',
    # 官方 EventPopup 系列字体样式:无 glow、用 Shadow/低 alpha 描边,文字清晰。
    # 见 Base/Assets/UI/Civ6_Styles.xml:96-100。
    'Style="EventPopupTitle"',
    'Style="EventPopupDescription"',
    # 资源分类筛选标签条(参 ReportScreen.xml:15-26 的 TabArea/TabContainer)。
    'ID="FilterTabArea"',
    'ID="FilterTabContainer"',
    # 筛选标签实例(参 ReportScreen.xml:151-157 的 TabInstance)。
    'Name="TabInstance"',
    # 空类占位提示:某个类别无可种资源时显示。
    'ID="EmptyHint"',
):
    assert needle in chooser_xml, f"选择器 XML 缺少关键结构: {needle}"

# 禁止回到带 glow 的旧字体样式:
#   WindowHeader / BodyTextDark18 均含 FontStyle="glow" + 低 alpha 光晕,文字偏糊
# (Base/Assets/UI/Civ6_Styles.xml:47, 89)。官方 EventPopup/HeroesPopup 同位置
# 用 EventPopupTitle / EventPopupDescription。
for forbidden_style in (
    'Style="WindowHeader"',
    'Style="BodyTextDark18"',
):
    assert forbidden_style not in chooser_xml, f"选择器 XML 不应再使用会导致文字模糊的字体样式: {forbidden_style}"

# ChooserPanel 不得设 ConsumeMouse="1":
# 该属性会吞掉悬停在面板空白区的鼠标事件,导致滚轮只在直接命中 ScrollBar 时才生效
# (官方 HeroesPopup/EventPopup/GreatPeoplePopup 的弹窗 Grid 都不设此属性)。
assert 'ID="ChooserPanel"' in chooser_xml, "选择器 XML 缺少 ChooserPanel"
chooser_panel_start = chooser_xml.find('ID="ChooserPanel"')
chooser_panel_grid_end = chooser_xml.find(">", chooser_panel_start)
chooser_panel_open_tag = chooser_xml[chooser_panel_start:chooser_panel_grid_end]
assert 'ConsumeMouse="1"' not in chooser_panel_open_tag, (
    'ChooserPanel 不应设 ConsumeMouse=\"1\"，否则滚轮只能停在滚动条上才能滚动'
)

# ChooserTitle 应遵循官方 EventPopup/HeroesPopup 居中模式：
# Label 不设 Size（直接给 Label 设 Size="parent,parent" 会让 WrapWidth 换行后
# 实际渲染错位），靠父级固定宽容器 + Anchor="C,C" + Align="Center" + WrapWidth
# 居中。见 EventPopup.xml:32 / HeroesPopup.xml:11。
chooser_title_start = chooser_xml.find('ID="ChooserTitle"')
chooser_title_end = chooser_xml.find("/>", chooser_title_start)
chooser_title_tag = chooser_xml[chooser_title_start:chooser_title_end]
assert 'Size="parent,parent"' not in chooser_title_tag, (
    'ChooserTitle 不应再设 Size="parent,parent"；改用无 Size + Anchor="C,C" + WrapWidth 居中（官方模式）'
)
assert 'Align="Center"' in chooser_title_tag, 'ChooserTitle 必须带 Align="Center"'
assert 'WrapWidth=' in chooser_title_tag, 'ChooserTitle 必须带 WrapWidth 让长标题可换行居中'

# ChooserPrompt 同理：不应在 Label 上直接设 Size，改用外层 Container + 无 Size Label
# （EventPopup.xml:34-35 / HeroesPopup.xml:16-18 官方模式）。
chooser_prompt_start = chooser_xml.find('ID="ChooserPrompt"')
chooser_prompt_end = chooser_xml.find("/>", chooser_prompt_start)
chooser_prompt_tag = chooser_xml[chooser_prompt_start:chooser_prompt_end]
assert 'Align="Center"' in chooser_prompt_tag, 'ChooserPrompt 应保持水平居中'
assert 'WrapWidth=' in chooser_prompt_tag, 'ChooserPrompt 必须带 WrapWidth 以便换行居中'

# CancelButton 的 Anchor="C,B" 必须配【正】y Offset，才会贴在 Grid 内底；
# 负值会把按钮推到 Grid 外下方。Base/Assets/UI/Popups 中所有主按钮一律正值
# （BoostUnlockedPopup.xml:38=0,15; TechCivicCompletedPopup.xml:55=0,25;
#  EventPopup.xml:68=0,23; HeroesPopup.xml:36=0,26），唯一一处负值
#  GreatPeoplePopup.xml:107=0,-10 是装饰性计数小按钮，不可类比。
cancel_button_start = chooser_xml.find('ID="CancelButton"')
cancel_button_end = chooser_xml.find("/>", cancel_button_start)
cancel_button_tag = chooser_xml[cancel_button_start:cancel_button_end]
assert 'Offset="0,-' not in cancel_button_tag, (
    'CancelButton 不得使用负 y Offset；Anchor="C,B" 配负值会把按钮推到弹窗下方'
)

for needle in (
    "LuaEvents.BP_ResourceChooser_Open.Add",
    "LuaEvents.BP_ResourceChooser_PlantSelected",
    'instance.ResourceIcon:SetTexture',
    # 官方弹窗模式必备:Queue/Dequeue + PopupPriority.Low + SetInputHandler + SetInitHandler
    "UIManager:QueuePopup(ContextPtr, PopupPriority.Low",
    "UIManager:DequeuePopup(ContextPtr)",
    'ContextPtr:SetInputHandler(OnInputHandler, true)',
    'ContextPtr:SetInitHandler(OnInit)',
    # 资源分类筛选(参 ReportScreen.lua + TabSupport.lua):
    # 必须引入 TabSupport、定义过滤键、注册标签、默认选"全部"、按过滤刷新列表。
    'include("TabSupport")',
    "FILTER_ALL",
    "ClassTypeToFilterKey",
    "AddFilterTab",
    "RefreshList",
    "m_kTabs.SelectTab",
    "LOC_BP_FILTER_ALL",
    "LOC_BP_FILTER_BONUS",
    "LOC_BP_FILTER_LUXURY",
    "LOC_BP_FILTER_STRATEGIC",
):
    assert needle in chooser_lua, f"选择器 Lua 缺少关键逻辑: {needle}"

# 空类占位提示路径必须实现:某类无可种资源时显示 EmptyHint 并隐藏 ListStack。
for needle in (
    'Controls.EmptyHint:SetHide',
    'Controls.ChooserListStack:SetHide',
):
    assert needle in chooser_lua, f"选择器 Lua 缺少空类处理逻辑: {needle}"

# 明确禁止回到旧的 ChangeParent / LookUpControl("/InGame/WorldPopups") 架构:
# Firaxis 官方从不 reparent add-in context 到 WorldPopups。
for forbidden in (
    "ChangeParent",
    'LookUpControl("/InGame/WorldPopups")',
    "PopupPriority.Current",
):
    assert forbidden not in chooser_lua, f"选择器 Lua 不应再出现旧的非官方 API: {forbidden}"

print("resource-chooser-check: ok")
