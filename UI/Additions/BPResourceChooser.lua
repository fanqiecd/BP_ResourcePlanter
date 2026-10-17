-- ===========================================================================
-- Builder Plants Resources  -  资源选择器弹窗
--
-- 按 Firaxis 官方模态弹窗模式实现(参考蓝本:
--   DLC/Babylon/UI/Additions/HeroesPopup.lua
--   Base/Assets/UI/Popups/GreatPeoplePopup.lua
--   Base/Assets/UI/Screens/ReportScreen.lua  ← 资源分类筛选标签条
-- )。本文件由同名 BPResourceChooser.xml 自动加载到 InGame 的一个子
-- context,挂在 /InGame/AdditionalUserInterfaces 下。
--
-- 可见性由 UIManager:QueuePopup / DequeuePopup 统一管理:
--   - Open   : QueuePopup(ContextPtr, PopupPriority.Low, {AlwaysVisibleInQueue=true})
--   - Close  : DequeuePopup(ContextPtr)   (Dequeue 自带隐藏,不调 SetHide)
-- 不采用旧实现的"把 context 重新挂到 /InGame/WorldPopups"那类非官方
-- reparent —— add-in context 由 InGame.lua 的 LoadNewContext 循环自动挂载到
-- /InGame/AdditionalUserInterfaces,Firaxis 官方文件从不 reparent popup context。
--
-- 触发端(BPResourceLauncher.lua)通过
--   LuaEvents.BP_ResourceChooser_Open(entries)
-- 发起;结束端通过
--   LuaEvents.BP_ResourceChooser_PlantSelected(targetKind, targetIndex)
--   LuaEvents.BP_ResourceChooser_Canceled()
-- 回传结果。entries 每条携带:
--   TargetKind         -- "RESOURCE" 或 "FEATURE"
--   TargetIndex        -- Resources / Features 表索引
--   Name               -- 本地化资源名
--   IconId             -- 资源图标
--   ResourceType       -- 资源项时为 "RESOURCE_*"，供 UI 端按别名兜底找图
--   ResourceClassType  -- "RESOURCECLASS_BONUS"/"LUXURY"/"STRATEGIC" 或 nil
--   EntryKind          -- "RESOURCE" 或 "FEATURE"
--   FeatureType        -- 地貌项时为 "FEATURE_FOREST"/"FEATURE_JUNGLE"
--   FilterKey          -- "BONUS"/"LUXURY"/"STRATEGIC"/"FEATURE"；非标准类别
--                         （如秘密结社地脉）为 nil，只在“全部”标签下可见
-- ===========================================================================
include("InstanceManager");
include("TabSupport");

-- ===========================================================================
-- 常量 / 模块状态
-- ===========================================================================
local DATA_FIELD_SELECTION:string = "Selection";  -- 复用 ReportScreen.lua 的选中态约定

-- 内部过滤键。第一个 "ALL" 是"全部"占位(对应 ResourceClassType=nil 也归入展示);
-- 后三个对应 GameInfo.Resources[].ResourceClassType 的标准值。
local FILTER_ALL:string       = "ALL";
local FILTER_BONUS:string      = "BONUS";
local FILTER_LUXURY:string     = "LUXURY";
local FILTER_STRATEGIC:string  = "STRATEGIC";
local FILTER_FEATURE:string    = "FEATURE";
-- 把官方 ResourceClassType 长名映射成简短过滤键,便于在 Lua 里按用户选择筛。
local function ClassTypeToFilterKey(classType)
    if classType == "RESOURCECLASS_BONUS" then
        return FILTER_BONUS;
    elseif classType == "RESOURCECLASS_LUXURY" then
        return FILTER_LUXURY;
    elseif classType == "RESOURCECLASS_STRATEGIC" then
        return FILTER_STRATEGIC;
    end
    return nil;
end

local function EntryToFilterKey(entry:table)
    if entry == nil then
        return nil;
    end

    if entry.FilterKey ~= nil then
        return entry.FilterKey;
    end

    return ClassTypeToFilterKey(entry.ResourceClassType);
end

local BP_ICON_LOOKUP_SIZES:table = {38, 32, 50, 22, 64, 80, 256};
local m_iconAtlasCache:table = {};   -- [iconId] = {X=, Y=, Sheet=} 或 false(整轮尺寸都没命中)

local function TrySetIconFromId(iconControl:table, iconId:string)
    if iconControl == nil or iconId == nil or iconId == "" then
        return false;
    end

    -- IconManager:FindIconAtlas 是引擎调用，未命中时还要逐尺寸试探。同一个图标在每次
    -- 打开弹窗 / 切换筛选时都会被重新查询，这里按图标名缓存查询结果（false = 全部尺寸都没命中）。
    -- 注意：这个 local 会依次承载 nil(未缓存) / table(命中) / false(整轮尺寸都没命中)，
    -- 而 Civ6 的 Lua 会强制检查类型注解——写成 local cached:table 的话，
    -- cached = false 会在加载时直接抛 "Attempting to set local variable of type
    -- 'table' to type 'boolean'"，整个选择器文件加载失败，表现为点按钮毫无反应。
    -- 所以这里必须用无注解的 local。
    local cached = m_iconAtlasCache[iconId];
    if cached == nil then
        for _, iconSize in ipairs(BP_ICON_LOOKUP_SIZES) do
            local textureOffsetX:number, textureOffsetY:number, textureSheet:string = IconManager:FindIconAtlas(iconId, iconSize);
            if textureSheet ~= nil then
                cached = { X = textureOffsetX, Y = textureOffsetY, Sheet = textureSheet };
                break;
            end
        end
        if cached == nil then
            cached = false;
        end
        m_iconAtlasCache[iconId] = cached;
    end

    if cached == false then
        return false;
    end

    iconControl:SetTexture(cached.X, cached.Y, cached.Sheet);
    return true;
end

local function ResolveEntryIcon(iconControl:table, entry:table)
    local candidateIds:table = {};
    local seen:table = {};

    local function AddCandidate(iconId:string)
        if iconId ~= nil and iconId ~= "" and not seen[iconId] then
            seen[iconId] = true;
            candidateIds[#candidateIds + 1] = iconId;
        end
    end

    AddCandidate(entry and entry.IconId or nil);

    if entry ~= nil and entry.ResourceType ~= nil then
        candidateIds[#candidateIds + 1] = entry.ResourceType;
        candidateIds[#candidateIds + 1] = "ICON_" .. entry.ResourceType;
    end

    if entry ~= nil and entry.FeatureType ~= nil then
        AddCandidate("ICON_" .. entry.FeatureType);
        AddCandidate(entry.FeatureType);
    end

    for _, iconId in ipairs(candidateIds) do
        if TrySetIconFromId(iconControl, iconId) then
            return iconId;
        end
    end

    return nil;
end

local m_resourceEntryIM:table = nil;       -- InstanceManager,延迟在 OnInit 内构造
local m_tabIM:table           = nil;       -- 筛选标签 InstanceManager
local m_kTabs:table           = nil;       -- TabSupport 标签组
local m_pendingEntries:table  = {};        -- 当前呈现的条目缓存
local m_currentFilter:string = FILTER_ALL; -- 当前选中的筛选键

-- 前向声明:筛选标签的注册回调里要调 RefreshList,而 RefreshList 定义在下方。
local RefreshList;

-- ===========================================================================
-- 关闭弹窗:只 DequeuePopup,不手动 SetHide。
-- ===========================================================================
local function Close()
    if not UIManager:IsInPopupQueue(ContextPtr) then
        return;
    end
    UIManager:DequeuePopup(ContextPtr);
    print("[BP_ResourcePlanter] BPResourceChooser closed (DequeuePopup).");
end

local function Invalidate()
    Close();
    m_pendingEntries = {};
end

-- ===========================================================================
-- 握手应答：入口在点击按钮时 Ping 一次，本 context 只要完成了 OnInit 就能 Pong。
-- 入口据此把“选择器没起来”和“起来了但弹窗没显示”区分开——add-in context 没有
-- 日志通道，静默失败否则完全不可观测。
-- ===========================================================================
local function BPRespondPing()
    LuaEvents.BP_ResourceChooser_Pong();
end

-- ===========================================================================
-- 按当前过滤键刷新资源条目列表。
-- 若过滤后无任何条目,显示 EmptyHint 占位提示并隐藏滚动条内容。
-- ===========================================================================
function RefreshList()
    if m_resourceEntryIM == nil then
        print("[BP_ResourcePlanter] BPResourceChooser InstanceManager is nil; cannot refresh list.")
        return
    end

    m_resourceEntryIM:ResetInstances();

    -- m_pendingEntries 在 Open 时已被赋值,这里按 m_currentFilter 客户端过滤即可,
    -- 无需回到 Shared 端要新一轮 entries(减少跨 context 来回)。
    local visible:table = {};
    for _, entry in ipairs(m_pendingEntries) do
        if m_currentFilter == FILTER_ALL then
            table.insert(visible, entry);
        else
            if EntryToFilterKey(entry) == m_currentFilter then
                table.insert(visible, entry);
            end
        end
    end

    if #visible == 0 then
        -- 当前类别无可种资源:隐藏 Stack 内容、显示占位提示。
        -- ChooserListStack 在空内容时不占位,EmptyHint 居中显示在列表区。
        Controls.EmptyHint:SetHide(false);
        Controls.ChooserListStack:SetHide(true);
    else
        Controls.EmptyHint:SetHide(true);
        Controls.ChooserListStack:SetHide(false);

        for _, entry in ipairs(visible) do
            local instance:table = m_resourceEntryIM:GetInstance();
            if instance ~= nil then
                local resolvedIconId:string = ResolveEntryIcon(instance.ResourceIcon, entry);
                if resolvedIconId == nil then
                    instance.ResourceIcon:SetHide(true);
                    instance.MissingIcon:SetHide(false);
                    print(string.format(
                        "[BP_ResourcePlanter] BPResourceChooser icon lookup failed for %s (IconId=%s, ResourceType=%s, FeatureType=%s).",
                        tostring(entry.Name),
                        tostring(entry.IconId),
                        tostring(entry.ResourceType),
                        tostring(entry.FeatureType)
                    ));
                else
                    instance.ResourceIcon:SetHide(false);
                    instance.MissingIcon:SetHide(true);
                end
                instance.ResourceName:SetText(entry.Name);
                instance.Button:SetToolTipString(entry.Name);
                -- 选中条目:先关闭弹窗,再回传目标类型与表索引。
                instance.Button:RegisterCallback(Mouse.eLClick, function()
                    print("[BP_ResourcePlanter] BPResourceChooser selected " .. tostring(entry.TargetKind) .. "/" .. tostring(entry.TargetIndex) .. " / " .. tostring(entry.Name))
                    Close();
                    LuaEvents.BP_ResourceChooser_PlantSelected(entry.TargetKind, entry.TargetIndex);
                end);
                instance.Button:RegisterCallback(Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
            end
        end
    end

    Controls.ChooserListStack:CalculateSize();
    Controls.ChooserScrollPanel:CalculateSize();
end

-- ===========================================================================
-- 注册一个筛选标签(参 ReportScreen.lua:1710-1727)。
-- 选中态:隐藏旧标签的 Selection、显示本标签的 Selection、刷新过滤后的列表。
-- ===========================================================================
local function AddFilterTab(nameKey:string, filterKey:string)
    local kTab:table = m_tabIM:GetInstance();
    if kTab == nil then
        return;
    end

    -- 把内层 Selection 控件挂到 Button 上,回调里好取出来切换隐藏。
    kTab.Button[DATA_FIELD_SELECTION] = kTab.Selection;

    local callback:ifunction = function()
        if m_kTabs.prevSelectedControl ~= nil and m_kTabs.prevSelectedControl[DATA_FIELD_SELECTION] ~= nil then
            m_kTabs.prevSelectedControl[DATA_FIELD_SELECTION]:SetHide(true);
        end
        kTab.Selection:SetHide(false);
        m_currentFilter = filterKey;
        print("[BP_ResourcePlanter] BPResourceChooser filter tab: " .. tostring(filterKey));
        RefreshList();
    end

    kTab.Button:GetTextControl():SetText(Locale.Lookup(nameKey));
    kTab.Button:SetSizeToText(40, 20);
    kTab.Button:RegisterCallback(Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
    m_kTabs.AddTab(kTab.Button, callback);
end

-- ===========================================================================
-- 打开弹窗
-- ===========================================================================
local function BPOpenChooser(entries:table)
    if entries == nil or #entries == 0 then
        print("[BP_ResourcePlanter] BPResourceChooser open requested with no entries; ignoring.")
        return;
    end

    -- 回执 1：入口据此判断“请求到底有没有到达选择器”。本 context 是 add-in，
    -- 静默失败时既没有弹窗也没有日志，只能靠回执把故障点暴露到按钮提示上。
    LuaEvents.BP_ResourceChooser_Received();

    -- 已经在队列里就不再重复入队,避免重复声音/动画。
    if UIManager:IsInPopupQueue(ContextPtr) then
        print("[BP_ResourcePlanter] BPResourceChooser already open; refreshing entries.")
    else
        -- PopupPriority.Low 与官方 GreatPeople / Heroes 一档;
        -- AlwaysVisibleInQueue 让本弹窗即便有更高优先级弹窗也不被丢弃。
        UIManager:QueuePopup(ContextPtr, PopupPriority.Low, { AlwaysVisibleInQueue = true });
        print("[BP_ResourcePlanter] BPResourceChooser queued at PopupPriority.Low.")
    end

    m_pendingEntries = entries;
    -- (重)打开时回到"全部",避免沿用上一格的筛选(玩家很可能新格子已换类别)。
    m_currentFilter = FILTER_ALL;
    if m_kTabs ~= nil and m_kTabs.tabControls ~= nil and m_kTabs.tabControls[1] ~= nil then
        -- SelectTab 会走标签回调里的 RefreshList,因此这里不能再补一次,否则每次打开
        -- 都会把整张列表(含图标查询)连建两遍。
        m_kTabs.SelectTab(m_kTabs.tabControls[1]);
    else
        RefreshList();
    end

    Controls.ChooserTitle:SetText(Locale.ToUpper(Locale.Lookup("LOC_BP_RESOURCE_CHOOSER_TITLE")));
    Controls.ChooserPrompt:SetText(Locale.Lookup("LOC_BP_RESOURCE_CHOOSER_PROMPT"));
    UI.PlaySound("UI_Screen_Open");

    -- 回执 2：整段 Open 走完（入队 + 列表渲染都没有抛错）。
    LuaEvents.BP_ResourceChooser_Opened();
end

-- ===========================================================================
-- 打开入口的包装：add-in context 里一旦抛错，弹窗不会出现、日志也不一定留得下来。
-- 这里把真实错误文本回传给 launcher，让它显示在按钮提示上。
-- ===========================================================================
local function Open(entries:table)
    local ok, err = pcall(BPOpenChooser, entries);
    if not ok then
        print("[BP_ResourcePlanter] BPResourceChooser open failed: " .. tostring(err));
        LuaEvents.BP_ResourceChooser_OpenFailed(tostring(err));
    end
end

-- ===========================================================================
-- 取消(Esc / Cancel 按钮 / ScreenConsumer 右键):关闭并显式发 Canceled,
-- 让独立 launcher 刷新当前单位与地块状态。
-- ===========================================================================
local function OnCancel()
    print("[BP_ResourcePlanter] BPResourceChooser canceled.")
    Close();
    LuaEvents.BP_ResourceChooser_Canceled();
end

-- ===========================================================================
-- 输入处理:只处理 ESC(KeyUp)
-- ===========================================================================
local function KeyHandler(key:number)
    if key == Keys.VK_ESCAPE then
        OnCancel();
        return true;
    end
    return false;
end

local function OnInputHandler(pInputStruct:table)
    local uiMsg:number = pInputStruct:GetMessageType();
    if uiMsg == KeyEvents.KeyUp then
        return KeyHandler(pInputStruct:GetKey());
    end
    -- ScreenConsumer 会吞掉鼠标点击/滚轮,不需在此手动处理。
    return false;
end

-- ===========================================================================
-- 初始化(由 SetInitHandler 在 context 就绪后触发)
-- ===========================================================================
local function BPInitChooser()
    -- 此刻同名的 BPResourceChooser.xml 已与本 context 绑定,Controls.* 可用。
    m_resourceEntryIM = InstanceManager:new("ResourceEntryInstance", "Button", Controls.ChooserListStack);
    m_tabIM           = InstanceManager:new("TabInstance",       "Button", Controls.FilterTabContainer);

    -- 标签组:CreateTabs 容器、贴图尺寸、选中态文字颜色(深褐 0xFF331D05,
    -- 与官方 ReportScreen.lua:1771 一致)。
    m_kTabs = CreateTabs(Controls.FilterTabContainer, 42, 34, UI.GetColorValueFromHexLiteral(0xFF331D05));

    AddFilterTab("LOC_BP_FILTER_ALL",      FILTER_ALL);
    AddFilterTab("LOC_BP_FILTER_BONUS",    FILTER_BONUS);
    AddFilterTab("LOC_BP_FILTER_LUXURY",   FILTER_LUXURY);
    AddFilterTab("LOC_BP_FILTER_STRATEGIC", FILTER_STRATEGIC);
    AddFilterTab("LOC_BP_FILTER_FEATURE",  FILTER_FEATURE);

    -- 让 4 个标签等宽并居中排开(参 ReportScreen.lua:1781-1783)。
    m_kTabs.SameSizedTabs(20);
    m_kTabs.CenterAlignTabs(0);
    -- 默认选中"全部":SelectTab 会触发该标签的回调,从而完成首次列表渲染。
    -- 但首次 Init 时 m_pendingEntries 还是空数组,RefreshList 会落到 EmptyHint;
    -- 真正有内容时由 Open() 再次 SelectTab("全部") 触发 RefreshList。
    if m_kTabs.tabControls ~= nil and m_kTabs.tabControls[1] ~= nil then
        m_kTabs.SelectTab(m_kTabs.tabControls[1]);
    end

    Controls.CancelButton:RegisterCallback(Mouse.eLClick, OnCancel);
    Controls.CancelButton:RegisterCallback(Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
    -- 右键空白处即关闭:与 HeroesPopup 的 ScreenConsumer 右键行为一致。
    Controls.ScreenConsumer:RegisterCallback(Mouse.eRClick, OnCancel);

    LuaEvents.BP_ResourceChooser_Open.Add(Open);
    LuaEvents.BP_ResourceChooser_Invalidate.Add(Invalidate);
    LuaEvents.BP_ResourceChooser_Ping.Add(BPRespondPing);
    print("[BP_ResourcePlanter] BPResourceChooser initialized (context " .. tostring(ContextPtr:GetID()) .. ").")
end

-- ===========================================================================
-- 初始化包装：初始化中途抛错时，处理器不会被注册（表现为"点了没反应"）。
-- 这里把真实错误文本回传，让 launcher 直接把它显示在按钮提示上。
-- ===========================================================================
local function OnInit()
    local ok, err = pcall(BPInitChooser);
    if not ok then
        print("[BP_ResourcePlanter] BPResourceChooser init failed: " .. tostring(err));
        LuaEvents.BP_ResourceChooser_InitFailed(tostring(err));
    end
end

local function OnShutdown()
    LuaEvents.BP_ResourceChooser_Open.Remove(Open);
    LuaEvents.BP_ResourceChooser_Invalidate.Remove(Invalidate);
    LuaEvents.BP_ResourceChooser_Ping.Remove(BPRespondPing);
    if m_resourceEntryIM ~= nil then
        m_resourceEntryIM:ResetInstances();
    end
    if m_tabIM ~= nil then
        m_tabIM:ResetInstances();
    end
    m_pendingEntries = {};
    print("[BP_ResourcePlanter] BPResourceChooser shutdown.")
end

ContextPtr:SetInitHandler(OnInit);
ContextPtr:SetShutdown(OnShutdown);
ContextPtr:SetInputHandler(OnInputHandler, true);   -- true = 模态,吞未处理输入
