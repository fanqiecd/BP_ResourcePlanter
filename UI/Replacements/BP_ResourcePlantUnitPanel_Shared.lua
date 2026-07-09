-- ===========================================================================
-- Builder Plants Resources  -  UnitPanel 共享逻辑
--
-- 这个文件假定调用方已经先 include 了当前规则集对应的 UnitPanel 脚本
-- （Base / Expansion1 / Expansion2 之一），然后再 include 本文件，以便在不丢失
-- 原版或资料片扩展逻辑的前提下，只覆写资源种植入口的呈现方式。
-- ===========================================================================

print("[BP_ResourcePlanter] Initializing shared UnitPanel resource chooser logic.")

-- ===========================================================================
-- 缓存原版函数
-- ===========================================================================
BASE_GetUnitActionsTable = GetUnitActionsTable;

-- ===========================================================================
-- 常量
-- ===========================================================================
local BP_IMPROVEMENT_PREFIX:string = "IMPROVEMENT_BP_";
local BP_SINGLE_ACTION_ICON:string = "ICON_UNITOPERATION_PLANT_FOREST";
local m_bpChooserValidImprovements:table = {};

local BP_RESOURCE_CLASS_PRIORITY:table = {
    RESOURCECLASS_STRATEGIC = 1,
    RESOURCECLASS_LUXURY = 2,
    RESOURCECLASS_BONUS = 3
};

local BP_FEATURE_FILTER_KEY:string = "FEATURE";
local m_bpResourceValidTerrainsByType:table = nil;
local m_bpResourceValidFeaturesByType:table = nil;

-- ===========================================================================
-- 只展示当前玩家已解锁的资源：占位改良本身不再挂科技/市政前置，避免科技树把它
-- 当成正式解锁项显示出来。
-- ===========================================================================
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

local function BPHasPlayerUnlockedFeature(featureInfo:table, player:table)
    if featureInfo == nil then
        return false;
    end

    return true;
end

local function BPBuildResourcePlacementRuleCache()
    if m_bpResourceValidTerrainsByType ~= nil and m_bpResourceValidFeaturesByType ~= nil then
        return;
    end

    m_bpResourceValidTerrainsByType = {};
    m_bpResourceValidFeaturesByType = {};

    for row in GameInfo.Resource_ValidTerrains() do
        if row.ResourceType ~= nil and row.TerrainType ~= nil then
            if m_bpResourceValidTerrainsByType[row.ResourceType] == nil then
                m_bpResourceValidTerrainsByType[row.ResourceType] = {};
            end
            m_bpResourceValidTerrainsByType[row.ResourceType][row.TerrainType] = true;
        end
    end

    for row in GameInfo.Resource_ValidFeatures() do
        if row.ResourceType ~= nil and row.FeatureType ~= nil then
            if m_bpResourceValidFeaturesByType[row.ResourceType] == nil then
                m_bpResourceValidFeaturesByType[row.ResourceType] = {};
            end
            m_bpResourceValidFeaturesByType[row.ResourceType][row.FeatureType] = true;
        end
    end
end

local function BPGetPlotTerrainType(plot:table)
    if plot == nil then
        return nil;
    end

    local terrainIndex:number = plot:GetTerrainType();
    if terrainIndex == nil or terrainIndex < 0 then
        return nil;
    end

    local terrainInfo:table = GameInfo.Terrains[terrainIndex];
    return terrainInfo and terrainInfo.TerrainType or nil;
end

local function BPGetPlotFeatureType(plot:table)
    if plot == nil then
        return nil;
    end

    local featureIndex:number = plot:GetFeatureType();
    if featureIndex == nil or featureIndex < 0 then
        return nil;
    end

    local featureInfo:table = GameInfo.Features[featureIndex];
    return featureInfo and featureInfo.FeatureType or nil;
end

local function BPPlotMatchesResourcePlacementRules(plot:table, resourceInfo:table)
    if plot == nil or resourceInfo == nil or resourceInfo.ResourceType == nil then
        return false;
    end

    -- 资源种植已取消具体地形 / 地貌限制，这里只保留“资源对象有效”的最小校验。
    return true;
end

-- ===========================================================================
-- 判断某个建造动作是否属于本模组的资源种植占位改良
-- ===========================================================================
local function BPIsResourcePlantBuildAction(action:table)
    if action == nil or action.CallbackVoid1 == nil then
        return false;
    end

    local improvementInfo:table = GameInfo.Improvements[action.CallbackVoid1];
    if improvementInfo == nil or improvementInfo.ImprovementType == nil then
        return false;
    end

    return string.sub(improvementInfo.ImprovementType, 1, string.len(BP_IMPROVEMENT_PREFIX)) == BP_IMPROVEMENT_PREFIX;
end

-- ===========================================================================
-- 从 IMPROVEMENT_BP_<NAME> 反推资源表行
-- ===========================================================================
local function BPGetResourceInfoFromAction(action:table)
    if action == nil or action.CallbackVoid1 == nil then
        return nil, nil;
    end

    local improvementInfo:table = GameInfo.Improvements[action.CallbackVoid1];
    if improvementInfo == nil or improvementInfo.ImprovementType == nil then
        return nil, nil;
    end

    local resourceName:string = string.sub(improvementInfo.ImprovementType, string.len(BP_IMPROVEMENT_PREFIX) + 1);
    if string.sub(resourceName, 1, 8) == "FEATURE_" then
        return nil, improvementInfo;
    end
    local resourceType:string = "RESOURCE_" .. resourceName;
    return GameInfo.Resources[resourceType], improvementInfo;
end

local function BPGetFeatureInfoFromAction(action:table)
    if action == nil or action.CallbackVoid1 == nil then
        return nil, nil;
    end

    local improvementInfo:table = GameInfo.Improvements[action.CallbackVoid1];
    if improvementInfo == nil or improvementInfo.ImprovementType == nil then
        return nil, nil;
    end

    local featureType:string = string.sub(improvementInfo.ImprovementType, string.len(BP_IMPROVEMENT_PREFIX) + 1);
    if string.sub(featureType, 1, 8) ~= "FEATURE_" then
        return nil, improvementInfo;
    end

    return GameInfo.Features[featureType], improvementInfo;
end

local function BPDescribeImprovementTarget(improvementHash:number)
    if improvementHash == nil then
        return "unknown", "UNKNOWN", "Unknown"
    end

    local improvementInfo:table = GameInfo.Improvements[improvementHash]
    if improvementInfo == nil or improvementInfo.ImprovementType == nil then
        return "unknown", "UNKNOWN", "Unknown"
    end

    local suffix:string = string.sub(improvementInfo.ImprovementType, string.len(BP_IMPROVEMENT_PREFIX) + 1)
    if string.sub(suffix, 1, 8) == "FEATURE_" then
        local featureType:string = suffix
        local featureInfo:table = GameInfo.Features[featureType]
        local featureName:string = featureInfo and Locale.Lookup(featureInfo.Name) or featureType
        return "feature", featureType, featureName
    end

    local resourceType:string = "RESOURCE_" .. suffix
    local resourceInfo:table = GameInfo.Resources[resourceType]
    local resourceName:string = resourceInfo and Locale.Lookup(resourceInfo.Name) or resourceType
    return "resource", resourceType, resourceName
end

local function BPDescribeCurrentPlotForDebug(plot:table)
    if plot == nil then
        return "plot=nil"
    end

    local terrainType:string = BPGetPlotTerrainType(plot) or "NONE"
    local featureType:string = BPGetPlotFeatureType(plot) or "NONE"
    local resourceType:string = "NONE"
    local resourceIndex:number = plot:GetResourceType()
    if resourceIndex ~= nil and resourceIndex >= 0 then
        local resourceInfo:table = GameInfo.Resources[resourceIndex]
        resourceType = resourceInfo and resourceInfo.ResourceType or tostring(resourceIndex)
    end

    return string.format(
        "plot=(%d,%d) terrain=%s feature=%s resource=%s owner=%s district=%s improvement=%s",
        plot:GetX(),
        plot:GetY(),
        tostring(terrainType),
        tostring(featureType),
        tostring(resourceType),
        tostring(plot:GetOwner()),
        tostring(plot:GetDistrictType()),
        tostring(plot:GetImprovementType())
    )
end

-- ===========================================================================
-- 资源排序：战略 -> 奢侈 -> 加成，同类按本地化名称排序
-- ===========================================================================
local function BPSortResourcePlantActions(actions:table)
    table.sort(actions,
        function(a:table, b:table)
            local resourceInfoA:table, improvementInfoA:table = BPGetResourceInfoFromAction(a);
            local resourceInfoB:table, improvementInfoB:table = BPGetResourceInfoFromAction(b);
            local featureInfoA:table = nil;
            local featureInfoB:table = nil;

            if resourceInfoA == nil then
                featureInfoA, improvementInfoA = BPGetFeatureInfoFromAction(a);
            end

            if resourceInfoB == nil then
                featureInfoB, improvementInfoB = BPGetFeatureInfoFromAction(b);
            end

            local priorityA:number = 99;
            local priorityB:number = 99;

            if resourceInfoA ~= nil and BP_RESOURCE_CLASS_PRIORITY[resourceInfoA.ResourceClassType] ~= nil then
                priorityA = BP_RESOURCE_CLASS_PRIORITY[resourceInfoA.ResourceClassType];
            elseif featureInfoA ~= nil then
                priorityA = 4;
            end

            if resourceInfoB ~= nil and BP_RESOURCE_CLASS_PRIORITY[resourceInfoB.ResourceClassType] ~= nil then
                priorityB = BP_RESOURCE_CLASS_PRIORITY[resourceInfoB.ResourceClassType];
            elseif featureInfoB ~= nil then
                priorityB = 4;
            end

            if priorityA ~= priorityB then
                return priorityA < priorityB;
            end

            local localizedNameA:string = "";
            local localizedNameB:string = "";

            if improvementInfoA ~= nil then
                localizedNameA = Locale.Lookup(improvementInfoA.Name);
            end

            if improvementInfoB ~= nil then
                localizedNameB = Locale.Lookup(improvementInfoB.Name);
            end

            return Locale.Compare(localizedNameA, localizedNameB) == -1;
        end
    );
end

-- ===========================================================================
-- 发起真正的 BUILD_IMPROVEMENT 操作
-- ===========================================================================
local function BPRequestPlantImprovement(improvementHash:number)
    if not g_isOkayToProcess then
        print("[BP_ResourcePlanter] Plant request ignored because UI is not ready.")
        return;
    end

    local pSelectedUnit:table = UI.GetHeadSelectedUnit();
    if pSelectedUnit ~= nil then
        local targetKind:string, targetType:string, targetName:string = BPDescribeImprovementTarget(improvementHash)
        local selectedPlot:table = Map.GetPlot(pSelectedUnit:GetX(), pSelectedUnit:GetY())
        print(string.format(
            "[BP_ResourcePlanter] Requesting BUILD_IMPROVEMENT target=%s targetType=%s targetName=%s unitOwner=%d %s hash=%s.",
            tostring(targetKind),
            tostring(targetType),
            tostring(targetName),
            pSelectedUnit:GetOwner(),
            BPDescribeCurrentPlotForDebug(selectedPlot),
            tostring(improvementHash)
        ))
        local tParameters:table = {};
        tParameters[UnitOperationTypes.PARAM_X] = pSelectedUnit:GetX();
        tParameters[UnitOperationTypes.PARAM_Y] = pSelectedUnit:GetY();
        tParameters[UnitOperationTypes.PARAM_IMPROVEMENT_TYPE] = improvementHash;

        UnitManager.RequestOperation(pSelectedUnit, UnitOperationTypes.BUILD_IMPROVEMENT, tParameters);
    end

    ContextPtr:RequestRefresh();
end

-- ===========================================================================
-- 弹出资源选择框
-- ===========================================================================
local function BPShowResourceChooser(actions:table)
    if actions == nil or #actions == 0 then
        print("[BP_ResourcePlanter] Resource chooser requested with no valid actions.")
        return;
    end

    BPSortResourcePlantActions(actions);

    if #actions == 1 then
        print("[BP_ResourcePlanter] Resource chooser short-circuited with a single action.")
        BPRequestPlantImprovement(actions[1].CallbackVoid1);
        return;
    end

    local chooserEntries:table = {};
    m_bpChooserValidImprovements = {};

    for _, action in ipairs(actions) do
        local resourceInfo, improvementInfo = BPGetResourceInfoFromAction(action);
        local featureInfo = nil;
        local filterKey = nil;

        if resourceInfo ~= nil then
            if resourceInfo.ResourceClassType == "RESOURCECLASS_BONUS" then
                filterKey = "BONUS";
            elseif resourceInfo.ResourceClassType == "RESOURCECLASS_LUXURY" then
                filterKey = "LUXURY";
            elseif resourceInfo.ResourceClassType == "RESOURCECLASS_STRATEGIC" then
                filterKey = "STRATEGIC";
            end
        else
            featureInfo, improvementInfo = BPGetFeatureInfoFromAction(action);
            filterKey = BP_FEATURE_FILTER_KEY;
        end

        local improvementHash:number = action.CallbackVoid1;
        local buttonLabel:string = "";
        if improvementInfo ~= nil then
            buttonLabel = Locale.Lookup(improvementInfo.Name);
        end

        table.insert(chooserEntries, {
            ImprovementHash = improvementHash,
            Name = buttonLabel,
            IconId = improvementInfo and improvementInfo.Icon or BP_SINGLE_ACTION_ICON,
            EntryKind = resourceInfo and 'RESOURCE' or 'FEATURE',
            ResourceType = resourceInfo and resourceInfo.ResourceType or nil,
            -- 资源分类(供选择器 UI 端做"全部/加成/奢侈/战略"本地过滤);
            -- 取自 GameInfo.Resources[...].ResourceClassType,形如
            -- "RESOURCECLASS_BONUS" / "RESOURCECLASS_LUXURY" / "RESOURCECLASS_STRATEGIC"。
            ResourceClassType = resourceInfo and resourceInfo.ResourceClassType or nil,
            FeatureType = featureInfo and featureInfo.FeatureType or nil,
            FilterKey = filterKey
        });
        m_bpChooserValidImprovements[improvementHash] = true;
    end

    print("[BP_ResourcePlanter] Raising chooser with " .. tostring(#chooserEntries) .. " mixed entries.")
    LuaEvents.BP_ResourceChooser_Open(chooserEntries);
end

-- ===========================================================================
-- 生成单入口动作的提示文本
-- ===========================================================================
local function BPBuildCollapsedTooltip(actions:table)
    if actions == nil or #actions == 0 then
        return Locale.Lookup("LOC_BP_RESOURCE_CHOOSER_ACTION_DESCRIPTION");
    end

    local lines:table = {};
    BPSortResourcePlantActions(actions);

    for _, action in ipairs(actions) do
        local _, improvementInfo = BPGetResourceInfoFromAction(action);
        if improvementInfo == nil then
            _, improvementInfo = BPGetFeatureInfoFromAction(action);
        end
        if improvementInfo ~= nil then
            table.insert(lines, "[ICON_Bullet] " .. Locale.Lookup(improvementInfo.Name));
        end
    end

    local tooltip:string = Locale.Lookup("LOC_BP_RESOURCE_CHOOSER_ACTION_DESCRIPTION");
    tooltip = tooltip .. "[NEWLINE][NEWLINE]" .. Locale.Lookup("LOC_BP_RESOURCE_CHOOSER_AVAILABLE");

    for _, line in ipairs(lines) do
        tooltip = tooltip .. "[NEWLINE]" .. line;
    end

    return tooltip;
end

-- ===========================================================================
-- 把 BP 资源种植动作折叠成一个单入口动作
-- ===========================================================================
local function BPCollectResourcePlantActions(buildActions:table, pUnit:table)
    local bpActions:table = {};
    local otherBuildActions:table = {};
    local player:table = nil;
    local plot:table = nil;

    if pUnit ~= nil then
        player = Players[pUnit:GetOwner()];
        plot = Map.GetPlot(pUnit:GetX(), pUnit:GetY());
    end

    for _, action in ipairs(buildActions) do
        if BPIsResourcePlantBuildAction(action) then
            local resourceInfo:table = BPGetResourceInfoFromAction(action);
            local featureInfo:table = nil;
            local isUnlocked:boolean = false;

            if resourceInfo ~= nil then
                isUnlocked = BPHasPlayerUnlockedResource(resourceInfo, player);
                if resourceInfo ~= nil and isUnlocked then
                    if plot ~= nil then
                        -- 资源分支不允许覆盖已有资源；即便该资源因科技未解锁而地图上未显示，
                        -- plot:GetResourceType() 仍会返回真实底层资源类型。
                        -- 这里前置拦掉，避免玩家消耗建造者充能后才在 gameplay 侧被取消。
                        if plot:GetResourceType() ~= -1 then
                            isUnlocked = false;
                        else
                            isUnlocked = BPPlotMatchesResourcePlacementRules(plot, resourceInfo);
                        end
                    end
                end
            else
                featureInfo = BPGetFeatureInfoFromAction(action);
                isUnlocked = BPHasPlayerUnlockedFeature(featureInfo, player);
            end

            if isUnlocked then
                table.insert(bpActions, action);
            end
        else
            table.insert(otherBuildActions, action);
        end
    end

    return bpActions, otherBuildActions;
end

-- ===========================================================================
-- 创建右侧圆形动作区里的单入口动作
-- ===========================================================================
local function BPCreateResourceChooserAction(bpActions:table)
    if bpActions == nil or #bpActions == 0 then
        return nil;
    end

    local enabledBPActions:table = {};
    local showAsRecommended:boolean = false;
    local primarySound:string = nil;

    for _, action in ipairs(bpActions) do
        if not action.Disabled then
            table.insert(enabledBPActions, action);
        end
        if action.IsBestImprovement then
            showAsRecommended = true;
        end
        if primarySound == nil and action.Sound ~= nil and action.Sound ~= "" then
            primarySound = action.Sound;
        end
    end

    local chooserActions:table = (#enabledBPActions > 0) and enabledBPActions or bpActions;
    local isDisabled:boolean = (#enabledBPActions == 0);
    local collapsedTooltip:string = BPBuildCollapsedTooltip(chooserActions);

    return {
        IconId = BP_SINGLE_ACTION_ICON,
        Disabled = isDisabled,
        helpString = collapsedTooltip,
        userTag = DB.MakeHash("BP_RESOURCE_CHOOSER_ACTION"),
        CallbackFunc = function(void1, void2)
            if not isDisabled then
                print("[BP_ResourcePlanter] Resource chooser action button clicked.")
                BPShowResourceChooser(chooserActions);
            else
                print("[BP_ResourcePlanter] Resource chooser action button clicked while disabled.")
            end
        end,
        CallbackVoid1 = nil,
        CallbackVoid2 = nil,
        IsBestImprovement = showAsRecommended,
        Sound = primarySound
    };
end

-- ===========================================================================
-- 覆盖原版函数：移除 BUILD 面板中的 BP 资源按钮，并在右侧圆形动作区中插入单入口
-- ===========================================================================
function GetUnitActionsTable(pUnit:table)
    local actionsTable:table = BASE_GetUnitActionsTable(pUnit);

    if actionsTable ~= nil and actionsTable["BUILD"] ~= nil and #actionsTable["BUILD"] > 0 then
        local bpActions:table, otherBuildActions:table = BPCollectResourcePlantActions(actionsTable["BUILD"], pUnit);
        actionsTable["BUILD"] = otherBuildActions;

        local chooserAction:table = BPCreateResourceChooserAction(bpActions);
        if chooserAction ~= nil then
            table.insert(actionsTable["SPECIFIC"], 1, chooserAction);
        end
    end

    return actionsTable;
end

local function BPOnChooserPlantSelected(improvementHash:number)
    if improvementHash ~= nil and m_bpChooserValidImprovements[improvementHash] then
        local targetKind:string, targetType:string, targetName:string = BPDescribeImprovementTarget(improvementHash)
        local selectedUnit:table = UI.GetHeadSelectedUnit()
        local selectedPlot:table = nil
        local plotSummary:string = "plot=nil"
        local unitOwner:number = -1
        if selectedUnit ~= nil then
            selectedPlot = Map.GetPlot(selectedUnit:GetX(), selectedUnit:GetY())
            plotSummary = BPDescribeCurrentPlotForDebug(selectedPlot)
            unitOwner = selectedUnit:GetOwner()
        end
        print(string.format(
            "[BP_ResourcePlanter] Chooser confirmed target=%s targetType=%s targetName=%s unitOwner=%d %s hash=%s.",
            tostring(targetKind),
            tostring(targetType),
            tostring(targetName),
            unitOwner,
            plotSummary,
            tostring(improvementHash)
        ))
        BPRequestPlantImprovement(improvementHash);
    else
        print("[BP_ResourcePlanter] Chooser ignored invalid improvement hash " .. tostring(improvementHash) .. ".")
    end
    m_bpChooserValidImprovements = {};
end

local function BPOnChooserCanceled()
    print("[BP_ResourcePlanter] Chooser canceled.")
    m_bpChooserValidImprovements = {};
end

LuaEvents.BP_ResourceChooser_PlantSelected.Add(BPOnChooserPlantSelected);
LuaEvents.BP_ResourceChooser_Canceled.Add(BPOnChooserCanceled);
