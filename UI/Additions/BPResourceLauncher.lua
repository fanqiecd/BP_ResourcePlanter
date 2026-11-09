-- ===========================================================================
-- Builder Plants Resources - 独立资源入口
--
-- 通过 AddUserInterfaces 常驻，不替换 UnitPanel，也不向原生建造列表注册
-- BP 占位改良。选择后用 EXECUTE_SCRIPT 请求 Gameplay 直接落地目标。
-- ===========================================================================

local BP_SINGLE_ACTION_ICON:string = "ICON_UNITOPERATION_PLANT_FOREST";
local BP_REMOVE_RESOURCE_ICON:string = "ICON_UNITOPERATION_REMOVE_FEATURE";
local BP_FEATURE_FILTER_KEY:string = "FEATURE";
local BP_VANILLA_RESOURCE_RULES_CONFIG:string = "BP_USE_VANILLA_RESOURCE_RULES";

local BP_RESOURCE_CLASS_PRIORITY:table = {
    RESOURCECLASS_STRATEGIC = 1,
    RESOURCECLASS_LUXURY = 2,
    RESOURCECLASS_BONUS = 3
};

local m_builderUnitTypes:table = nil;
local m_resourceDefinitions:table = nil;
local m_featureDefinitions:table = nil;
local m_featureTerrainsByType:table = nil;
local m_resourceTerrainsByType:table = nil;
local m_resourceFeaturesByType:table = nil;
local m_launcherAttached:boolean = false;
local m_actionStack:table = nil;
-- 选择器握手/回执状态：本模组跑在 add-in context 里，没有日志通道，静默失败必须
-- 变成可见信息，否则只能看到“点了没反应”。
local m_chooserPong:boolean = false;      -- 选择器完成了初始化(能应答握手)
local m_chooserReceived:boolean = false;  -- 选择器接收到了打开请求
local m_chooserOpened:boolean = false;    -- 选择器完整走完了一次打开
local m_chooserError:string = nil;        -- 选择器回传的本次打开错误文本(优先展示)
local m_chooserInitError:string = nil;    -- 选择器初始化失败的错误文本(常驻，不随点击清空)
local m_clickDiag:string = nil;           -- 最近一次点击的诊断结论(显示在按钮提示里)

-- 排序键只依赖静态数据（类别优先级 / 本地化名称 / 表索引），所以只在缓存构建时排一次。
local function BPSortDefinitions(definitions:table)
    table.sort(definitions, function(a:table, b:table)
        if a.SortPriority ~= b.SortPriority then
            return a.SortPriority < b.SortPriority;
        end
        local comparison:number = Locale.Compare(a.Name, b.Name);
        if comparison ~= 0 then
            return comparison == -1;
        end
        return a.Info.Index < b.Info.Index;
    end);
end

local function BPBuildDataCache()
    if m_resourceDefinitions ~= nil then
        return;
    end

    m_builderUnitTypes = {};
    m_resourceDefinitions = {};
    m_featureDefinitions = {};
    m_featureTerrainsByType = {};
    m_resourceTerrainsByType = {};
    m_resourceFeaturesByType = {};

    for row in GameInfo.TypeTags() do
        if row.Tag == "CLASS_BUILDER" then
            m_builderUnitTypes[row.Type] = true;
        end
    end

    for row in GameInfo.Feature_ValidTerrains() do
        if m_featureTerrainsByType[row.FeatureType] == nil then
            m_featureTerrainsByType[row.FeatureType] = {};
        end
        m_featureTerrainsByType[row.FeatureType][row.TerrainType] = true;
    end

    for row in GameInfo.Resource_ValidTerrains() do
        m_resourceTerrainsByType[row.ResourceType] = m_resourceTerrainsByType[row.ResourceType] or {};
        m_resourceTerrainsByType[row.ResourceType][row.TerrainType] = true;
    end

    for row in GameInfo.Resource_ValidFeatures() do
        m_resourceFeaturesByType[row.ResourceType] = m_resourceFeaturesByType[row.ResourceType] or {};
        m_resourceFeaturesByType[row.ResourceType][row.FeatureType] = true;
    end

    for row in GameInfo.BPBuildableResources() do
        local resourceInfo:table = GameInfo.Resources["RESOURCE_" .. row.ResourceName];
        if resourceInfo ~= nil then
            -- 非标准类别（例如秘密结社地脉 RESOURCECLASS_LEY_LINE）不映射任何过滤键，
            -- 因此只在“全部”标签里出现：它既不属于加成 / 奢侈 / 战略，也不是地貌。
            local filterKey:string = nil;
            if resourceInfo.ResourceClassType == "RESOURCECLASS_BONUS" then
                filterKey = "BONUS";
            elseif resourceInfo.ResourceClassType == "RESOURCECLASS_LUXURY" then
                filterKey = "LUXURY";
            elseif resourceInfo.ResourceClassType == "RESOURCECLASS_STRATEGIC" then
                filterKey = "STRATEGIC";
            end
            table.insert(m_resourceDefinitions, {
                Info = resourceInfo,
                Domain = row.Domain,
                CanPlantOnWater = row.CanPlantOnWater == 1 or row.CanPlantOnWater == true,
                Icon = "ICON_" .. resourceInfo.ResourceType,
                FilterKey = filterKey,
                RequiresVisibility = row.RequiresVisibility,
                SortPriority = BP_RESOURCE_CLASS_PRIORITY[resourceInfo.ResourceClassType] or 99,
                -- 名称在缓存构建时查一次：中期全解锁后条目上百条，选中单位时再逐条
                -- Locale.Lookup 会明显拖慢刷新。
                Name = Locale.Lookup(resourceInfo.Name)
            });
        end
    end

    for row in GameInfo.BPBuildableFeatures() do
        local featureInfo:table = GameInfo.Features[row.FeatureType];
        if featureInfo ~= nil then
            table.insert(m_featureDefinitions, {
                Info = featureInfo,
                Domain = row.Domain,
                Icon = row.Icon,
                FilterKey = BP_FEATURE_FILTER_KEY,
                SortPriority = 4,
                Name = Locale.Lookup(featureInfo.Name)
            });
        end
    end

    -- 资源优先级恒小于地貌的 4，所以两张表各自有序即可拼出与原全局排序相同的顺序，
    -- 不再需要每次刷新都对合并结果做一次 table.sort。
    BPSortDefinitions(m_resourceDefinitions);
    BPSortDefinitions(m_featureDefinitions);
end

local function BPIsBuilderUnit(pUnit:table)
    if pUnit == nil then
        return false;
    end

    BPBuildDataCache();
    local unitInfo:table = GameInfo.Units[pUnit:GetType()];
    return unitInfo ~= nil and m_builderUnitTypes[unitInfo.UnitType] == true;
end

local function BPHasPlayerUnlockedResource(resourceInfo:table, player:table)
    if resourceInfo == nil then
        return false;
    end

    local prereqTech:string = resourceInfo.PrereqTech;
    if prereqTech ~= nil then
        local playerTechs:table = player and player:GetTechs() or nil;
        local techInfo:table = GameInfo.Technologies[prereqTech];
        if playerTechs == nil or techInfo == nil or not playerTechs:HasTech(techInfo.Index) then
            return false;
        end
    end

    local prereqCivic:string = resourceInfo.PrereqCivic;
    if prereqCivic ~= nil then
        local playerCulture:table = player and player:GetCulture() or nil;
        local civicInfo:table = GameInfo.Civics[prereqCivic];
        if playerCulture == nil or civicInfo == nil or not playerCulture:HasCivic(civicInfo.Index) then
            return false;
        end
    end

    return true;
end

-- 效果解锁资源（原版只有秘密结社地脉）没有科技 / 市政前置，能否种植取决于玩家当前
-- 是否已经能看到它（GOVERNOR_PROMOTION_HERMETIC_ORDER_1 授予的免费资源可见性）。
-- 看不见就不列进选择器，免得种下一格玩家自己完全看不到的资源。
local function BPIsResourceAvailableToPlayer(resourceInfo:table, player:table, requiresVisibility)
    if not BPHasPlayerUnlockedResource(resourceInfo, player) then
        return false;
    end

    if requiresVisibility ~= true and requiresVisibility ~= 1 then
        return true;
    end

    local playerResources:table = player:GetResources();
    return playerResources ~= nil and playerResources:IsResourceVisible(resourceInfo.Hash) == true;
end

local function BPHasPlayerUnlockedFeature(featureInfo:table, player:table)
    return featureInfo ~= nil;
end

local function BPIsCommonPlotValid(plot:table, playerID:number)
    if plot == nil then
        return false;
    end

    if plot:IsNaturalWonder() or plot:GetDistrictType() ~= -1 or plot:GetImprovementType() ~= -1 then
        return false;
    end

    local plotOwner:number = plot:GetOwner();
    return plotOwner == -1 or plotOwner == playerID;
end

local function BPDomainMatchesPlot(domain:string, plot:table, canPlantOnWater:boolean)
    if plot:IsWater() then
        -- 可陆可海资源（原版石油 / 琥珀）的 Domain 记的是陆地，水域要靠这一位补上。
        return domain == "DOMAIN_SEA" or canPlantOnWater == true;
    end
    return domain == "DOMAIN_LAND";
end

local function BPResourceMatchesVanillaRules(resourceType:string, plot:table)
    local value = GameConfiguration.GetValue(BP_VANILLA_RESOURCE_RULES_CONFIG);
    if value ~= true and value ~= 1 then
        return true;
    end

    BPBuildDataCache();
    local featureInfo:table = GameInfo.Features[plot:GetFeatureType()];
    if featureInfo ~= nil then
        local validFeatures:table = m_resourceFeaturesByType[resourceType];
        return validFeatures ~= nil and validFeatures[featureInfo.FeatureType] == true;
    end

    local terrainInfo:table = GameInfo.Terrains[plot:GetTerrainType()];
    local validTerrains:table = m_resourceTerrainsByType[resourceType];
    return terrainInfo ~= nil and validTerrains ~= nil and validTerrains[terrainInfo.TerrainType] == true;
end

local function BPFeatureMatchesVanillaRules(featureType:string, plot:table)
    local value = GameConfiguration.GetValue(BP_VANILLA_RESOURCE_RULES_CONFIG);
    if (value ~= true and value ~= 1) or plot:GetResourceType() == -1 then
        return true;
    end

    BPBuildDataCache();
    local resourceInfo:table = GameInfo.Resources[plot:GetResourceType()];
    if resourceInfo == nil then
        return false;
    end
    -- 按目标地貌检查现有资源，不能沿用种植前裸地的地形判定。
    local validFeatures:table = m_resourceFeaturesByType[resourceInfo.ResourceType];
    return validFeatures ~= nil and validFeatures[featureType] == true;
end

local function BPFeatureMatchesTerrain(featureType:string, plot:table)
    BPBuildDataCache();
    local terrainInfo:table = GameInfo.Terrains[plot:GetTerrainType()];
    if terrainInfo == nil then
        return false;
    end
    local validTerrains:table = m_featureTerrainsByType[featureType];
    return validTerrains ~= nil and validTerrains[terrainInfo.TerrainType] == true;
end

local function BPDescribeTarget(targetKind:string, targetIndex:number)
    if targetKind == "RESOURCE" then
        local resourceInfo:table = GameInfo.Resources[targetIndex];
        if resourceInfo ~= nil then
            return resourceInfo.ResourceType, Locale.Lookup(resourceInfo.Name);
        end
    elseif targetKind == "FEATURE" then
        local featureInfo:table = GameInfo.Features[targetIndex];
        if featureInfo ~= nil then
            return featureInfo.FeatureType, Locale.Lookup(featureInfo.Name);
        end
    end
    return "UNKNOWN", "Unknown";
end

local function BPDescribeCurrentPlotForDebug(plot:table)
    if plot == nil then
        return "plot=nil";
    end

    local terrainInfo:table = GameInfo.Terrains[plot:GetTerrainType()];
    local featureInfo:table = GameInfo.Features[plot:GetFeatureType()];
    local resourceInfo:table = GameInfo.Resources[plot:GetResourceType()];

    return string.format(
        "plot=(%d,%d) terrain=%s feature=%s resource=%s owner=%s district=%s improvement=%s",
        plot:GetX(),
        plot:GetY(),
        terrainInfo and terrainInfo.TerrainType or "NONE",
        featureInfo and featureInfo.FeatureType or "NONE",
        resourceInfo and resourceInfo.ResourceType or "NONE",
        tostring(plot:GetOwner()),
        tostring(plot:GetDistrictType()),
        tostring(plot:GetImprovementType())
    );
end

local function BPCreateEntry(targetKind:string, definition:table)
    local info:table = definition.Info;
    local resourceInfo:table = targetKind == "RESOURCE" and info or nil;
    local featureInfo:table = targetKind == "FEATURE" and info or nil;
    return {
        TargetKind = targetKind,
        TargetIndex = info.Index,
        Name = definition.Name,
        IconId = definition.Icon or BP_SINGLE_ACTION_ICON,
        EntryKind = targetKind,
        ResourceType = resourceInfo and resourceInfo.ResourceType or nil,
        ResourceClassType = resourceInfo and resourceInfo.ResourceClassType or nil,
        FeatureType = featureInfo and featureInfo.FeatureType or nil,
        FilterKey = definition.FilterKey
    };
end

local function BPCollectPlantableEntries(pUnit:table)
    local entries:table = {};
    BPBuildDataCache();
    local localPlayerID:number = Game.GetLocalPlayer();
    if localPlayerID < 0
        or not BPIsBuilderUnit(pUnit)
        or pUnit:GetOwner() ~= localPlayerID
        or pUnit:GetBuildCharges() <= 0
        or pUnit:GetMovesRemaining() <= 0 then
        return entries;
    end

    local plot:table = Map.GetPlot(pUnit:GetX(), pUnit:GetY());
    local player:table = Players[localPlayerID];
    if player == nil or not BPIsCommonPlotValid(plot, localPlayerID) then
        return entries;
    end

    if plot:GetResourceType() == -1 then
        for _, definition in ipairs(m_resourceDefinitions) do
            local resourceInfo:table = definition.Info;
            if BPDomainMatchesPlot(definition.Domain, plot, definition.CanPlantOnWater)
                and BPResourceMatchesVanillaRules(resourceInfo.ResourceType, plot)
                and BPIsResourceAvailableToPlayer(resourceInfo, player, definition.RequiresVisibility) then
                table.insert(entries, BPCreateEntry("RESOURCE", definition));
            end
        end
    end

    if plot:GetFeatureType() == -1 then
        for _, definition in ipairs(m_featureDefinitions) do
            local featureInfo:table = definition.Info;
            if BPDomainMatchesPlot(definition.Domain, plot)
                and BPFeatureMatchesTerrain(featureInfo.FeatureType, plot)
                and BPFeatureMatchesVanillaRules(featureInfo.FeatureType, plot)
                and BPHasPlayerUnlockedFeature(featureInfo, player) then
                table.insert(entries, BPCreateEntry("FEATURE", definition));
            end
        end
    end

    return entries;
end

-- 资源写入地块后不会生成原版“移除资源”建造动作。种植入口与清除入口使用
-- 两个独立按钮，避免当前地貌可种资源时清除动作抢占种植按钮。
local function BPCanRemoveResource(pUnit:table)
    local localPlayerID:number = Game.GetLocalPlayer();
    if localPlayerID < 0 or pUnit == nil or not BPIsBuilderUnit(pUnit)
        or pUnit:GetOwner() ~= localPlayerID
        or pUnit:GetBuildCharges() <= 0
        or pUnit:GetMovesRemaining() <= 0 then
        return false;
    end

    local plot:table = Map.GetPlot(pUnit:GetX(), pUnit:GetY());
    if plot == nil or plot:GetResourceType() == -1
        or plot:GetProperty("BP_PlantedResource") ~= 1
        or plot:GetDistrictType() ~= -1
        or plot:GetImprovementType() ~= -1 then
        return false;
    end

    local plotOwner:number = plot:GetOwner();
    return plotOwner == -1 or plotOwner == localPlayerID;
end

local function BPCanRemoveFeature(pUnit:table)
    local localPlayerID:number = Game.GetLocalPlayer();
    if localPlayerID < 0 or pUnit == nil or not BPIsBuilderUnit(pUnit)
        or pUnit:GetOwner() ~= localPlayerID
        or pUnit:GetBuildCharges() <= 0
        or pUnit:GetMovesRemaining() <= 0 then
        return false;
    end

    local plot:table = Map.GetPlot(pUnit:GetX(), pUnit:GetY());
    if plot == nil or plot:GetFeatureType() == -1
        or plot:GetProperty("BP_PlantedFeature") ~= 1
        or plot:GetDistrictType() ~= -1
        or plot:GetImprovementType() ~= -1 then
        return false;
    end

    local plotOwner:number = plot:GetOwner();
    return plotOwner == -1 or plotOwner == localPlayerID;
end

local function BPRequestPlantTarget(targetKind:string, targetIndex:number)
    local pSelectedUnit:table = UI.GetHeadSelectedUnit();
    if pSelectedUnit == nil then
        return;
    end

    local targetType:string, targetName:string = BPDescribeTarget(targetKind, targetIndex);
    local selectedPlot:table = Map.GetPlot(pSelectedUnit:GetX(), pSelectedUnit:GetY());
    print(string.format(
        "[BP_ResourcePlanter] Requesting direct plant target=%s targetType=%s targetName=%s unitOwner=%d %s index=%s.",
        tostring(targetKind),
        tostring(targetType),
        tostring(targetName),
        pSelectedUnit:GetOwner(),
        BPDescribeCurrentPlotForDebug(selectedPlot),
        tostring(targetIndex)
    ));

    UI.RequestPlayerOperation(pSelectedUnit:GetOwner(), PlayerOperations.EXECUTE_SCRIPT, {
        OnStart = "BPPlantTarget",
        UnitID = pSelectedUnit:GetID(),
        X = pSelectedUnit:GetX(),
        Y = pSelectedUnit:GetY(),
        TargetKind = targetKind,
        TargetIndex = targetIndex
    });
    SimUnitSystem.SetAnimationState(pSelectedUnit, "ACTION_1", "IDLE");
    UI.PlaySound("Build_Improvement_2D");
    Controls.RemovalGrid:SetHide(true);
    Controls.LauncherGrid:SetHide(true);
end

local function BPRequestRemoveResource()
    local pSelectedUnit:table = UI.GetHeadSelectedUnit();
    if pSelectedUnit == nil then
        return;
    end

    local selectedPlot:table = Map.GetPlot(pSelectedUnit:GetX(), pSelectedUnit:GetY());
    print(string.format(
        "[BP_ResourcePlanter] Requesting resource removal unitOwner=%d %s.",
        pSelectedUnit:GetOwner(),
        BPDescribeCurrentPlotForDebug(selectedPlot)
    ));

    UI.RequestPlayerOperation(pSelectedUnit:GetOwner(), PlayerOperations.EXECUTE_SCRIPT, {
        OnStart = "BPRemoveResource",
        UnitID = pSelectedUnit:GetID(),
        X = pSelectedUnit:GetX(),
        Y = pSelectedUnit:GetY()
    });
    SimUnitSystem.SetAnimationState(pSelectedUnit, "ACTION_1", "IDLE");
    UI.PlaySound("Build_Improvement_2D");
    Controls.RemovalGrid:SetHide(true);
    Controls.LauncherGrid:SetHide(true);
end

local function BPRequestRemoveFeature()
    local pSelectedUnit:table = UI.GetHeadSelectedUnit();
    if pSelectedUnit == nil then
        return;
    end

    UI.RequestPlayerOperation(pSelectedUnit:GetOwner(), PlayerOperations.EXECUTE_SCRIPT, {
        OnStart = "BPRemoveFeature",
        UnitID = pSelectedUnit:GetID(),
        X = pSelectedUnit:GetX(),
        Y = pSelectedUnit:GetY()
    });
    SimUnitSystem.SetAnimationState(pSelectedUnit, "ACTION_1", "IDLE");
    UI.PlaySound("Build_Improvement_2D");
    Controls.RemovalGrid:SetHide(true);
    Controls.LauncherGrid:SetHide(true);
end

local function BPShowResourceChooser(entries:table)
    if entries == nil or #entries == 0 then
        return;
    end
    if #entries == 1 then
        -- 只有一种可种项时按原设计不弹窗，直接种植；把这件事也写进提示，免得被
        -- 当成“界面打不开”。
        m_clickDiag = Locale.Lookup("LOC_BP_CHOOSER_DIAG_SINGLE");
        BPRequestPlantTarget(entries[1].TargetKind, entries[1].TargetIndex);
        return;
    end

    -- Ping/Pong 先确认选择器是否真的完成了初始化，再发打开请求；两条回执把
    -- “请求没人接”和“打开途中中断”区分开。全部同步返回，所以这里能立刻判定。
    m_chooserPong = false;
    m_chooserReceived = false;
    m_chooserOpened = false;
    m_chooserError = nil;
    LuaEvents.BP_ResourceChooser_Ping();
    LuaEvents.BP_ResourceChooser_Open(entries);

    if m_chooserError ~= nil then
        -- 选择器把本次打开的真实错误文本回传了：直接显示，比“没反应”有用得多。
        m_clickDiag = string.sub(m_chooserError, 1, 240);
    elseif m_chooserInitError ~= nil then
        -- 初始化就失败了：处理器根本没注册，回执永远不会来。
        m_clickDiag = string.sub(m_chooserInitError, 1, 240);
    elseif not m_chooserPong then
        m_clickDiag = Locale.Lookup("LOC_BP_CHOOSER_DIAG_DEAD");
    elseif not m_chooserReceived then
        m_clickDiag = Locale.Lookup("LOC_BP_CHOOSER_DIAG_NO_HANDLER");
    elseif not m_chooserOpened then
        m_clickDiag = Locale.Lookup("LOC_BP_CHOOSER_DIAG_ABORTED");
    else
        m_clickDiag = nil;
    end

    print(string.format(
        "[BP_ResourcePlanter] Chooser request pong=%s received=%s opened=%s entries=%d.",
        tostring(m_chooserPong),
        tostring(m_chooserReceived),
        tostring(m_chooserOpened),
        #entries
    ));
end

local function BPBuildCollapsedTooltip(entries:table)
    local tooltip:string = Locale.Lookup("LOC_BP_RESOURCE_CHOOSER_ACTION_DESCRIPTION");
    tooltip = tooltip .. "[NEWLINE][NEWLINE]" .. Locale.Lookup("LOC_BP_RESOURCE_CHOOSER_AVAILABLE") .. " " .. tostring(#entries);
    if m_clickDiag ~= nil then
        tooltip = tooltip .. "[NEWLINE][COLOR:Red]" .. m_clickDiag .. "[ENDCOLOR]";
    end
    return tooltip;
end

local function BPAttachLauncher()
    if m_launcherAttached then
        return;
    end

    local actionStack:table = ContextPtr:LookUpControl("/InGame/UnitPanel/StandardActionsStack");
    if actionStack ~= nil then
        Controls.LauncherGrid:ChangeParent(actionStack);
        Controls.RemovalGrid:ChangeParent(actionStack);
        m_actionStack = actionStack;
        m_launcherAttached = true;
        print("[BP_ResourcePlanter] Independent launcher attached to StandardActionsStack.");
    end
end

local function BPRefreshLauncher()
    BPAttachLauncher();
    local selectedUnit:table = UI.GetHeadSelectedUnit();
    local localPlayerID:number = Game.GetLocalPlayer();
    local isBuilder:boolean = localPlayerID >= 0
        and selectedUnit ~= nil
        and selectedUnit:GetOwner() == localPlayerID
        and BPIsBuilderUnit(selectedUnit);
    local entries:table = BPCollectPlantableEntries(selectedUnit);
    local canRemoveResource:boolean = isBuilder and BPCanRemoveResource(selectedUnit);
    local canRemoveFeature:boolean = isBuilder and BPCanRemoveFeature(selectedUnit);
    Controls.LauncherGrid:SetHide(not isBuilder or #entries == 0);
    Controls.RemovalGrid:SetHide(not isBuilder or (not canRemoveResource and not canRemoveFeature));
    Controls.LauncherButton:SetDisabled(#entries == 0);
    Controls.LauncherButton:SetAlpha(#entries == 0 and 0.6 or 1);
    if isBuilder then
        Controls.LauncherIcon:SetIcon(BP_SINGLE_ACTION_ICON);
        Controls.LauncherButton:SetToolTipString(BPBuildCollapsedTooltip(entries));
        if canRemoveResource or canRemoveFeature then
            Controls.RemovalIcon:SetIcon(BP_REMOVE_RESOURCE_ICON);
            Controls.RemovalButton:SetToolTipString(Locale.Lookup(
                canRemoveResource and "LOC_BP_RESOURCE_REMOVE_ACTION_DESCRIPTION"
                    or "LOC_BP_FEATURE_REMOVE_ACTION_DESCRIPTION"
            ));
        end
    end
    if m_actionStack ~= nil then
        m_actionStack:CalculateSize();
        m_actionStack:ReprocessAnchoring();
    end
end

local function BPOnLauncherClicked()
    local entries:table = BPCollectPlantableEntries(UI.GetHeadSelectedUnit());
    if #entries == 0 then
        BPRefreshLauncher();
        return;
    end
    UI.PlaySound("Play_UI_Click");
    BPShowResourceChooser(entries);
end

local function BPOnRemovalClicked()
    if BPCanRemoveResource(UI.GetHeadSelectedUnit()) then
        BPRequestRemoveResource();
    elseif BPCanRemoveFeature(UI.GetHeadSelectedUnit()) then
        BPRequestRemoveFeature();
    else
        BPRefreshLauncher();
    end
end

local function BPOnChooserPlantSelected(targetKind:string, targetIndex:number)
    local entries:table = BPCollectPlantableEntries(UI.GetHeadSelectedUnit());
    for _, entry in ipairs(entries) do
        if entry.TargetKind == targetKind and entry.TargetIndex == targetIndex then
            BPRequestPlantTarget(targetKind, targetIndex);
            return;
        end
    end
    print("[BP_ResourcePlanter] Chooser ignored stale target " .. tostring(targetKind) .. "/" .. tostring(targetIndex) .. ".");
    BPRefreshLauncher();
end

local function BPOnLocalUnitChanged(playerID:number)
    if playerID == Game.GetLocalPlayer() then
        LuaEvents.BP_ResourceChooser_Invalidate();
        -- 这里必须直接刷新，不能改走 ContextPtr:RequestRefresh() + SetRefreshHandler：
        -- 本 context 是 add-in（InGame.lua 用 LoadNewContext(..., isHidden=true) 把它挂在
        -- AdditionalUserInterfaces 下），而官方所有 add-in 界面都只用 Events 直接驱动，
        -- 没有任何一处在用引擎的刷新回调。回调一旦不来，按钮就永远停在 OnInit 的
        -- “初始隐藏”状态，表现为选中建造者也看不到按钮。
        -- 直接刷新的代价可忽略：定义缓存只构建一次，每次只做一轮过滤。
        BPRefreshLauncher();
    end
end

local function OnInit()
    -- 先把按钮挂进 UnitPanel 的 StandardActionsStack，再配置其它回调：
    -- 这样即使后面某一步失败，按钮也不会残留在不可见的 add-in 根容器里。
    BPAttachLauncher();
    LuaEvents.BP_ResourceChooser_Pong.Add(function() m_chooserPong = true; end);
    LuaEvents.BP_ResourceChooser_Received.Add(function() m_chooserReceived = true; end);
    LuaEvents.BP_ResourceChooser_Opened.Add(function() m_chooserOpened = true; end);
    LuaEvents.BP_ResourceChooser_InitFailed.Add(function(message) m_chooserInitError = tostring(message); end);
    LuaEvents.BP_ResourceChooser_OpenFailed.Add(function(message) m_chooserError = tostring(message); end);
    Controls.LauncherIcon:SetIcon(BP_SINGLE_ACTION_ICON);
    Controls.LauncherButton:RegisterCallback(Mouse.eLClick, BPOnLauncherClicked);
    Controls.LauncherButton:RegisterCallback(Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
    Controls.RemovalIcon:SetIcon(BP_REMOVE_RESOURCE_ICON);
    Controls.RemovalButton:RegisterCallback(Mouse.eLClick, BPOnRemovalClicked);
    Controls.RemovalButton:RegisterCallback(Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
    Controls.LauncherGrid:SetHide(true);
    Controls.RemovalGrid:SetHide(true);
end

ContextPtr:SetInitHandler(OnInit);

Events.LoadGameViewStateDone.Add(BPRefreshLauncher);
Events.UnitSelectionChanged.Add(BPOnLocalUnitChanged);
Events.UnitMoveComplete.Add(BPOnLocalUnitChanged);
Events.UnitChargesChanged.Add(BPOnLocalUnitChanged);
Events.ResearchCompleted.Add(BPOnLocalUnitChanged);
Events.CivicCompleted.Add(BPOnLocalUnitChanged);
Events.UnitMovementPointsChanged.Add(BPOnLocalUnitChanged);
Events.UnitMovementPointsCleared.Add(BPOnLocalUnitChanged);
Events.UnitMovementPointsRestored.Add(BPOnLocalUnitChanged);
Events.PlayerTurnActivated.Add(BPOnLocalUnitChanged);
Events.PlayerTurnDeactivated.Add(BPOnLocalUnitChanged);
LuaEvents.BP_ResourceChooser_PlantSelected.Add(BPOnChooserPlantSelected);
LuaEvents.BP_ResourceChooser_Canceled.Add(BPRefreshLauncher);
