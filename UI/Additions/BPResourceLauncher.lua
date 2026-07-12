-- ===========================================================================
-- Builder Plants Resources - 独立资源入口
--
-- 通过 AddUserInterfaces 常驻，不替换 UnitPanel，也不向原生建造列表注册
-- BP 占位改良。选择后用 EXECUTE_SCRIPT 请求 Gameplay 直接落地目标。
-- ===========================================================================

local BP_SINGLE_ACTION_ICON:string = "ICON_UNITOPERATION_PLANT_FOREST";
local BP_FEATURE_FILTER_KEY:string = "FEATURE";

local BP_RESOURCE_CLASS_PRIORITY:table = {
    RESOURCECLASS_STRATEGIC = 1,
    RESOURCECLASS_LUXURY = 2,
    RESOURCECLASS_BONUS = 3
};

local m_builderUnitTypes:table = nil;
local m_resourceDefinitions:table = nil;
local m_featureDefinitions:table = nil;
local m_featureTerrainsByType:table = nil;
local m_launcherAttached:boolean = false;

local function BPBuildDataCache()
    if m_resourceDefinitions ~= nil then
        return;
    end

    m_builderUnitTypes = {};
    m_resourceDefinitions = {};
    m_featureDefinitions = {};
    m_featureTerrainsByType = {};

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

    for row in GameInfo.BPBuildableResources() do
        local resourceInfo:table = GameInfo.Resources["RESOURCE_" .. row.ResourceName];
        if resourceInfo ~= nil then
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
                Icon = "ICON_" .. resourceInfo.ResourceType,
                FilterKey = filterKey,
                SortPriority = BP_RESOURCE_CLASS_PRIORITY[resourceInfo.ResourceClassType] or 99
            });
        end
    end

    for row in GameInfo.BPBuildableFeatures() do
        local featureInfo:table = GameInfo.Features[row.FeatureType];
        if featureInfo ~= nil then
            table.insert(m_featureDefinitions, {
                Info = featureInfo,
                Domain = row.Domain,
                Icon = row.Icon
            });
        end
    end
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

local function BPDomainMatchesPlot(domain:string, plot:table)
    if domain == "DOMAIN_SEA" then
        return plot:IsWater();
    end
    return domain == "DOMAIN_LAND" and not plot:IsWater();
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

local function BPSortEntries(entries:table)
    table.sort(entries, function(a:table, b:table)
        if a.SortPriority ~= b.SortPriority then
            return a.SortPriority < b.SortPriority;
        end
        local comparison:number = Locale.Compare(a.Name, b.Name);
        if comparison ~= 0 then
            return comparison == -1;
        end
        return a.TargetIndex < b.TargetIndex;
    end);
end

local function BPCreateEntry(targetKind:string, targetIndex:number, info:table, iconId:string, filterKey:string, sortPriority:number)
    local resourceInfo:table = targetKind == "RESOURCE" and info or nil;
    local featureInfo:table = targetKind == "FEATURE" and info or nil;
    return {
        TargetKind = targetKind,
        TargetIndex = targetIndex,
        Name = Locale.Lookup(info.Name),
        IconId = iconId or BP_SINGLE_ACTION_ICON,
        EntryKind = targetKind,
        ResourceType = resourceInfo and resourceInfo.ResourceType or nil,
        ResourceClassType = resourceInfo and resourceInfo.ResourceClassType or nil,
        FeatureType = featureInfo and featureInfo.FeatureType or nil,
        FilterKey = filterKey,
        SortPriority = sortPriority
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
            if BPDomainMatchesPlot(definition.Domain, plot)
                and BPHasPlayerUnlockedResource(resourceInfo, player) then
                table.insert(entries, BPCreateEntry(
                    "RESOURCE",
                    resourceInfo.Index,
                    resourceInfo,
                    definition.Icon,
                    definition.FilterKey,
                    definition.SortPriority
                ));
            end
        end
    end

    if plot:GetFeatureType() == -1 then
        for _, definition in ipairs(m_featureDefinitions) do
            local featureInfo:table = definition.Info;
            if BPDomainMatchesPlot(definition.Domain, plot)
                and BPFeatureMatchesTerrain(featureInfo.FeatureType, plot)
                and BPHasPlayerUnlockedFeature(featureInfo, player) then
                table.insert(entries, BPCreateEntry(
                    "FEATURE",
                    featureInfo.Index,
                    featureInfo,
                    definition.Icon,
                    BP_FEATURE_FILTER_KEY,
                    4
                ));
            end
        end
    end

    BPSortEntries(entries);
    return entries;
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
    Controls.LauncherGrid:SetHide(true);
end

local function BPShowResourceChooser(entries:table)
    if entries == nil or #entries == 0 then
        return;
    end
    if #entries == 1 then
        BPRequestPlantTarget(entries[1].TargetKind, entries[1].TargetIndex);
        return;
    end
    LuaEvents.BP_ResourceChooser_Open(entries);
end

local function BPBuildCollapsedTooltip(entries:table)
    local tooltip:string = Locale.Lookup("LOC_BP_RESOURCE_CHOOSER_ACTION_DESCRIPTION");
    return tooltip .. "[NEWLINE][NEWLINE]" .. Locale.Lookup("LOC_BP_RESOURCE_CHOOSER_AVAILABLE") .. " " .. tostring(#entries);
end

local function BPAttachLauncher()
    if m_launcherAttached then
        return;
    end

    local actionStack:table = ContextPtr:LookUpControl("/InGame/UnitPanel/StandardActionsStack");
    if actionStack ~= nil then
        Controls.LauncherGrid:ChangeParent(actionStack);
        Controls.LauncherGrid:SetOffsetVal(0, 0);
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
    Controls.LauncherGrid:SetHide(not isBuilder);
    Controls.LauncherButton:SetDisabled(#entries == 0);
    Controls.LauncherButton:SetAlpha(#entries == 0 and 0.6 or 1);
    if isBuilder then
        Controls.LauncherButton:SetToolTipString(BPBuildCollapsedTooltip(entries));
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
        BPRefreshLauncher();
    end
end

local function OnInit()
    Controls.LauncherIcon:SetIcon(BP_SINGLE_ACTION_ICON);
    Controls.LauncherButton:RegisterCallback(Mouse.eLClick, BPOnLauncherClicked);
    Controls.LauncherButton:RegisterCallback(Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
    Controls.LauncherGrid:SetHide(true);
    BPAttachLauncher();
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
