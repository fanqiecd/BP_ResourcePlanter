-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Builder Plants Resources  -  Gameplay 脚本
--
-- 独立 UI 通过 EXECUTE_SCRIPT 请求本脚本直接种植资源 / 地貌，并用不可见
-- UnitAbility 正确消耗一次建造者充能。旧占位改良路径仅用于清理旧存档残留。
--
-- 整体思路沿用上游 "Settlers Build Districts" 模组：
--   * 监听 ImprovementsAddedToMap（人类 / AI、读档 / 游玩过程中都会触发），
--     这样即便读档后也能继续完成转换。
--   * 直接阻止 AI 使用，避免 AI 无限制刷资源。
--   * 阻止在已有资源的格子上种植，避免叠加或覆盖。
--   * 阻止在自然奇观等不该动的格子上种植。
--   * 转换时移除占位改良，因此格子最终显示的是游戏原生资源模型，而不是占位物。
--
-- ResourceBuilder.SetResourceType(pPlot, resourceIndex, count) 是在运行中往地块上
-- 放置资源的标准 API。根据 Civ6 模组社区的通用做法，先围绕 SetResourceType 清理
-- 掉改良设施，可以确保宜居度 / 战略储备等收益计算及时刷新。这里因为占位改良本来
-- 就要删掉，所以直接把改良设为 -1，再设置资源即可。
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

ExposedMembers.GameEvents = GameEvents

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 建立查找表：占位改良索引 -> 资源索引 / 地貌索引
-- 资源改良名称格式为 'IMPROVEMENT_BP_<ResourceName>'，其中 <ResourceName> 是去掉
-- 'RESOURCE_' 前缀后的资源名。
-- 地貌改良名称格式为 'IMPROVEMENT_BP_<FeatureType>'，例如
-- 'IMPROVEMENT_BP_FEATURE_FOREST'。
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
local bpImprovementToResource = {}      -- [improvementIndex] = resourceIndex
local bpImprovementToFeature = {}       -- [improvementIndex] = featureIndex
local bpTrackedImprovementIndexes = {}  -- 快速判断“这个改良是不是本模组的”
local bpConvertingPlots = {}            -- 以地块索引为键的防重入保护
local bpBuildableResourceDomains = {}   -- [resourceIndex] = DOMAIN_LAND / DOMAIN_SEA
local bpBuildableFeatureDomains = {}    -- [featureIndex] = DOMAIN_LAND / DOMAIN_SEA
local bpBuilderUnitTypes = {}            -- [UnitType] = true
local BP_VISIBLE_RESOURCE_PROPERTY = 'BP_VisibleResourceForYieldBonuses'
local BP_BONUS_RESOURCE_PROPERTY = 'BP_HasBonusResourceForYieldBonuses'
local BP_LUXURY_RESOURCE_PROPERTY = 'BP_HasLuxuryResourceForYieldBonuses'
local BP_STRATEGIC_RESOURCE_PROPERTY = 'BP_HasStrategicResourceForYieldBonuses'
local function BPInitLookup()
    for row in GameInfo.TypeTags() do
        if row.Tag == 'CLASS_BUILDER' then
            bpBuilderUnitTypes[row.Type] = true
        end
    end

    for row in GameInfo.BPBuildableResources() do
        local resourceInfo = GameInfo.Resources['RESOURCE_'..row.ResourceName]
        if resourceInfo ~= nil then
            bpBuildableResourceDomains[resourceInfo.Index] = row.Domain
        end
    end

    for row in GameInfo.BPBuildableFeatures() do
        local featureInfo = GameInfo.Features[row.FeatureType]
        if featureInfo ~= nil then
            bpBuildableFeatureDomains[featureInfo.Index] = row.Domain
        end
    end

    -- GameInfo.Resources() 会遍历 Resources 表中的每一行。
    for resourceInfo in GameInfo.Resources() do
        local resourceType = resourceInfo.ResourceType
        if resourceType and string.sub(resourceType, 1, 9) == 'RESOURCE_' then
            local resourceName = string.sub(resourceType, 10) -- 去掉 'RESOURCE_' 前缀
            local improvementType = 'IMPROVEMENT_BP_'..resourceName
            local improvementInfo = GameInfo.Improvements[improvementType]
            if improvementInfo then
                local improvementIndex = improvementInfo.Index
                local resourceIndex = resourceInfo.Index
                bpImprovementToResource[improvementIndex] = resourceIndex
                bpTrackedImprovementIndexes[improvementIndex] = true
            end
        end
    end

    for featureInfo in GameInfo.Features() do
        local featureType = featureInfo.FeatureType
        if featureType == 'FEATURE_FOREST' or featureType == 'FEATURE_JUNGLE' then
            local improvementType = 'IMPROVEMENT_BP_'..featureType
            local improvementInfo = GameInfo.Improvements[improvementType]
            if improvementInfo then
                local improvementIndex = improvementInfo.Index
                local featureIndex = featureInfo.Index
                bpImprovementToFeature[improvementIndex] = featureIndex
                bpTrackedImprovementIndexes[improvementIndex] = true
            end
        end
    end

    local resourceCount = 0
    local featureCount = 0
    for _ in pairs(bpImprovementToResource) do resourceCount = resourceCount + 1 end
    for _ in pairs(bpImprovementToFeature) do featureCount = featureCount + 1 end
    print(string.format(
        '[BP_ResourcePlanter] Tracked %d resource improvements and %d feature improvements.',
        resourceCount,
        featureCount
    ))
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 辅助函数
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
local function BPGetPlotTerrainType(plot)
    if plot == nil then
        return nil
    end

    local terrainIndex = plot:GetTerrainType()
    if terrainIndex == nil or terrainIndex < 0 then
        return nil
    end

    local terrainInfo = GameInfo.Terrains[terrainIndex]
    return terrainInfo and terrainInfo.TerrainType or nil
end

local function BPGetPlotFeatureType(plot)
    if plot == nil then
        return nil
    end

    local featureIndex = plot:GetFeatureType()
    if featureIndex == nil or featureIndex < 0 then
        return nil
    end

    local featureInfo = GameInfo.Features[featureIndex]
    return featureInfo and featureInfo.FeatureType or nil
end

local function BPGetResourceDebugName(resourceIndex)
    if resourceIndex == nil or resourceIndex < 0 then
        return "NONE", "None"
    end

    local resourceInfo = GameInfo.Resources[resourceIndex]
    if resourceInfo == nil then
        return tostring(resourceIndex), tostring(resourceIndex)
    end

    return resourceInfo.ResourceType or tostring(resourceIndex), Locale.Lookup(resourceInfo.Name)
end

local function BPGetFeatureDebugName(featureIndex)
    if featureIndex == nil or featureIndex < 0 then
        return "NONE", "None"
    end

    local featureInfo = GameInfo.Features[featureIndex]
    if featureInfo == nil then
        return tostring(featureIndex), tostring(featureIndex)
    end

    return featureInfo.FeatureType or tostring(featureIndex), Locale.Lookup(featureInfo.Name)
end

local function BPDescribePlotForDebug(plot)
    if plot == nil then
        return "plot=nil"
    end

    local terrainType = BPGetPlotTerrainType(plot) or "NONE"
    local featureType, featureName = BPGetFeatureDebugName(plot:GetFeatureType())
    local resourceType, resourceName = BPGetResourceDebugName(plot:GetResourceType())

    return string.format(
        "plot=(%d,%d) terrain=%s feature=%s(%s) resource=%s(%s) owner=%s district=%s improvement=%s",
        plot:GetX(),
        plot:GetY(),
        tostring(terrainType),
        tostring(featureType),
        tostring(featureName),
        tostring(resourceType),
        tostring(resourceName),
        tostring(plot:GetOwner()),
        tostring(plot:GetDistrictType()),
        tostring(plot:GetImprovementType())
    )
end

local function BPClearImprovement(plot)
    ImprovementBuilder.SetImprovementType(plot, -1, -1)
end

local function BPSyncResourceYieldProperties(plot, resourceIndexOverride)
    if plot == nil then
        return
    end

    local resourceIndex = resourceIndexOverride
    if resourceIndex == nil then
        resourceIndex = plot:GetResourceType()
    end

    local bonusProperty = nil
    local luxuryProperty = nil
    local strategicProperty = nil

    if resourceIndex ~= nil and resourceIndex >= 0 then
        plot:SetProperty(BP_VISIBLE_RESOURCE_PROPERTY, 1)

        local resourceInfo = GameInfo.Resources[resourceIndex]
        local resourceClassType = resourceInfo and resourceInfo.ResourceClassType or nil
        if resourceClassType == 'RESOURCECLASS_BONUS' then
            bonusProperty = 1
        elseif resourceClassType == 'RESOURCECLASS_LUXURY' then
            luxuryProperty = 1
        elseif resourceClassType == 'RESOURCECLASS_STRATEGIC' then
            strategicProperty = 1
        end
    else
        plot:SetProperty(BP_VISIBLE_RESOURCE_PROPERTY, nil)
    end

    plot:SetProperty(BP_BONUS_RESOURCE_PROPERTY, bonusProperty)
    plot:SetProperty(BP_LUXURY_RESOURCE_PROPERTY, luxuryProperty)
    plot:SetProperty(BP_STRATEGIC_RESOURCE_PROPERTY, strategicProperty)
end

local function BPIsCommonPlotValid(plot, player)
    if plot == nil then return false end

    -- 直接排除自然奇观。Features.NaturalWonder 在 SQLite 里存的是 0/1 整数，
    -- 所以这里显式比较，而不是依赖 Lua 的真假值规则（1 为真、0 为假），这样更清楚。
    local featureType = plot:GetFeatureType()
    if featureType ~= -1 then
        local featureInfo = GameInfo.Features[featureType]
        if featureInfo and featureInfo.NaturalWonder and featureInfo.NaturalWonder ~= 0 then
            return false
        end
    end

    -- 排除已有区域的格子（城市中心、社区等）。
    if plot:GetDistrictType() ~= -1 then
        return false
    end

    -- 国家公园和世界奇观所在格子也不应被改动。
    if plot:IsNaturalWonder() then
        return false
    end

    -- 通用所有权保护：虽然周边无主地不是硬要求，但如果格子属于别人，就禁止种植，
    -- 避免建造者只靠相邻站位就往别国领土里塞资源。
    local plotOwner = plot:GetOwner()
    if plotOwner ~= -1 and plotOwner ~= player then
        return false
    end

    return true
end

local function BPIsValidResourcePlot(plot, player)
    if not BPIsCommonPlotValid(plot, player) then
        return false
    end

    -- 资源种植仍然禁止覆盖现有资源。
    if plot:GetResourceType() ~= -1 then
        return false
    end

    return true
end

local function BPIsValidFeaturePlot(plot, player)
    if not BPIsCommonPlotValid(plot, player) then
        return false
    end

    -- 地貌种植允许与已有资源共存，但不允许和现有地貌叠加。
    if plot:GetFeatureType() ~= -1 then
        return false
    end

    return true
end

local function BPPlaceResource(plot, resourceIndex)
    -- 最终状态约束：格子上只留下资源本身。触发本事件的占位改良会在同一次调用里
    -- 被移除，因此玩家不会看到一个完成态“改良设施”压在资源上。
    --
    -- 按照模组社区常见做法，先清改良（并且走 ImprovementBuilder 路径，让
    -- Events.ImprovementRemovedFromMap 也能触发），再设置资源。这样可以确保
    -- 宜居度 / 战略储备等收益立刻刷新，而不是要等到重载后才正确。
    -- SetResourceType 的数量设为 1，这与原版加成 / 奢侈资源的单格规模，以及
    -- 单格战略资源的 1 单位产出保持一致。
    BPClearImprovement(plot)
    -- 先把“这是资源格”的 property 预写到目标状态，再落资源。
    -- ponytail: SetResourceType 本身更像是本回合触发地块产出重算的脏化点；把条件写晚了，
    -- 引擎可能要等到下一回合才重新评估这类“资源可见性”地块加成。
    BPSyncResourceYieldProperties(plot, resourceIndex)
    ResourceBuilder.SetResourceType(plot, resourceIndex, 1)
    if plot:GetResourceType() ~= resourceIndex then
        BPSyncResourceYieldProperties(plot)
        BPClearImprovement(plot)
        return false
    end
    BPSyncResourceYieldProperties(plot)
    BPClearImprovement(plot)
    return true
end

local function BPPlaceFeature(plot, featureIndex)
    BPClearImprovement(plot)
    TerrainBuilder.SetFeatureType(plot, featureIndex)
    BPSyncResourceYieldProperties(plot)
    BPClearImprovement(plot)
    return plot:GetFeatureType() == featureIndex
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 事件：地块新增改良设施
-- 函数签名与 Events.ImprovementAddedToMap.Add(fn) 一致：
-- (X, Y, improvementIndex, playerID)
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
local function BPOnImprovementAddedToMap(x, y, improvementIndex, playerID)
    -- 快速过滤：不是本模组的占位改良就直接返回。
    if not bpTrackedImprovementIndexes[improvementIndex] then
        return
    end

    local plot = Map.GetPlot(x, y)
    if plot == nil then
        print('[BP_ResourcePlanter] Conversion canceled: invalid plot ('..x..','..y..').')
        return
    end

    -- 防重入保护：下面清理占位改良时，在某些版本里可能会同步再次触发本事件。
    -- 这里先把地块标记为“处理中”，如果已经在处理就直接退出。
    local plotKey = Map.GetPlotIndex(x, y)
    if bpConvertingPlots[plotKey] then
        return
    end
    bpConvertingPlots[plotKey] = true

    local player = Players[playerID]
    if player == nil then
        print('[BP_ResourcePlanter] Conversion canceled: invalid player.')
        bpConvertingPlots[plotKey] = nil
        return
    end

    -- 阻止 AI。上游模组也是这么做的，否则 AI 建造者会不停刷资源，破坏战略资源
    -- 产出平衡。理论上 AI 在前面就不该成功放下占位改良，所以这里更多是读档补救：
    -- 如果有占位物残留，就防御性地把它清掉。
    if not player:IsHuman() then
        BPClearImprovement(plot)
        BPSyncResourceYieldProperties(plot)
        print('[BP_ResourcePlanter] Conversion canceled: AI players may not plant resources.')
        bpConvertingPlots[plotKey] = nil
        return
    end

    local resourceIndex = bpImprovementToResource[improvementIndex]
    if resourceIndex ~= nil then
        local resourceInfo = GameInfo.Resources[resourceIndex]
        local resourceType, resourceName = BPGetResourceDebugName(resourceIndex)
        print(string.format(
            '[BP_ResourcePlanter] Attempting resource conversion target=%s(%s) player=%d improvementIndex=%s %s.',
            tostring(resourceType),
            tostring(resourceName),
            playerID,
            tostring(improvementIndex),
            BPDescribePlotForDebug(plot)
        ))

        if not BPIsValidResourcePlot(plot, playerID) then
            BPClearImprovement(plot)
            BPSyncResourceYieldProperties(plot)
            print(string.format(
                '[BP_ResourcePlanter] Resource conversion canceled: target=%s(%s) player=%d not eligible %s.',
                tostring(resourceType),
                tostring(resourceName),
                playerID,
                BPDescribePlotForDebug(plot)
            ))
            bpConvertingPlots[plotKey] = nil
            return
        end

        local placementSucceeded = BPPlaceResource(plot, resourceIndex)
        if not placementSucceeded then
            print(string.format(
                '[BP_ResourcePlanter] Resource conversion failed: target=%s(%s) player=%d %s.',
                tostring(resourceType),
                tostring(resourceName),
                playerID,
                BPDescribePlotForDebug(plot)
            ))
            bpConvertingPlots[plotKey] = nil
            return
        end

        print(string.format(
            '[BP_ResourcePlanter] Resource planted target=%s(%s) player=%d %s.',
            tostring(resourceType),
            tostring(resourceName),
            playerID,
            BPDescribePlotForDebug(plot)
        ))
        bpConvertingPlots[plotKey] = nil
        return
    end

    local featureIndex = bpImprovementToFeature[improvementIndex]
    if featureIndex ~= nil then
        local featureType, featureName = BPGetFeatureDebugName(featureIndex)
        print(string.format(
            '[BP_ResourcePlanter] Attempting feature conversion target=%s(%s) player=%d improvementIndex=%s %s.',
            tostring(featureType),
            tostring(featureName),
            playerID,
            tostring(improvementIndex),
            BPDescribePlotForDebug(plot)
        ))
        if not BPIsValidFeaturePlot(plot, playerID) then
            BPClearImprovement(plot)
            BPSyncResourceYieldProperties(plot)
            print(string.format(
                '[BP_ResourcePlanter] Feature conversion canceled: target=%s(%s) player=%d not eligible %s.',
                tostring(featureType),
                tostring(featureName),
                playerID,
                BPDescribePlotForDebug(plot)
            ))
            bpConvertingPlots[plotKey] = nil
            return
        end

        BPPlaceFeature(plot, featureIndex)
        print(string.format(
            '[BP_ResourcePlanter] Feature planted target=%s(%s) player=%d %s.',
            tostring(featureType),
            tostring(featureName),
            playerID,
            BPDescribePlotForDebug(plot)
        ))
        bpConvertingPlots[plotKey] = nil
        return
    end

    if resourceIndex == nil and featureIndex == nil then
        BPClearImprovement(plot)
        BPSyncResourceYieldProperties(plot)
        print('[BP_ResourcePlanter] Conversion canceled: no resource mapping for improvement index '..tostring(improvementIndex)..'.')
        bpConvertingPlots[plotKey] = nil
        return
    end
end

local function BPDomainMatchesPlot(domain, plot)
    if domain == 'DOMAIN_SEA' then
        return plot:IsWater()
    end
    return domain == 'DOMAIN_LAND' and not plot:IsWater()
end

local function BPFeatureMatchesTerrain(featureInfo, plot)
    local terrainType = BPGetPlotTerrainType(plot)
    if featureInfo == nil or terrainType == nil then
        return false
    end

    for row in GameInfo.Feature_ValidTerrains() do
        if row.FeatureType == featureInfo.FeatureType and row.TerrainType == terrainType then
            return true
        end
    end
    return false
end

local function BPHasPlayerUnlockedResource(resourceInfo, player)
    if resourceInfo == nil or player == nil then
        return false
    end

    if resourceInfo.PrereqTech ~= nil then
        local techInfo = GameInfo.Technologies[resourceInfo.PrereqTech]
        if techInfo == nil or not player:GetTechs():HasTech(techInfo.Index) then
            return false
        end
    end
    if resourceInfo.PrereqCivic ~= nil then
        local civicInfo = GameInfo.Civics[resourceInfo.PrereqCivic]
        if civicInfo == nil or not player:GetCulture():HasCivic(civicInfo.Index) then
            return false
        end
    end
    return true
end

local function BPFindAvailableChargeAbility(unit)
    local unitAbility = unit and unit:GetAbility() or nil
    if unitAbility == nil then
        return nil
    end

    for row in GameInfo.BPChargeSlots() do
        local abilityType = 'ABILITY_BP_CONSUMED_CHARGE_'..row.Slot
        if unitAbility:GetAbilityCount(abilityType) == 0 then
            return abilityType
        end
    end
    return nil
end

local function BPConsumeBuilderCharge(unit, abilityType)
    local unitAbility = unit and unit:GetAbility() or nil
    if unitAbility == nil or abilityType == nil then
        return false
    end

    UnitManager.FinishMoves(unit)
    unitAbility:ChangeAbilityCount(abilityType, 1)
    return true
end

local function BPExecutePlantTarget(playerID, params)
    local player = Players[playerID]
    local unit = params and UnitManager.GetUnit(playerID, params.UnitID) or nil
    local plot = params and Map.GetPlot(params.X, params.Y) or nil
    if player == nil or not player:IsHuman() or unit == nil or plot == nil then
        print('[BP_ResourcePlanter] Direct plant canceled: invalid player, unit, or plot.')
        return
    end
    local unitInfo = GameInfo.Units[unit:GetType()]
    if unitInfo == nil
        or not bpBuilderUnitTypes[unitInfo.UnitType]
        or unit:GetX() ~= params.X
        or unit:GetY() ~= params.Y
        or unit:GetBuildCharges() <= 0
        or unit:GetMovesRemaining() <= 0 then
        print('[BP_ResourcePlanter] Direct plant canceled: invalid builder state.')
        return
    end
    if plot:GetImprovementType() ~= -1 then
        print('[BP_ResourcePlanter] Direct plant canceled: plot already has an improvement.')
        return
    end

    local chargeAbility = BPFindAvailableChargeAbility(unit)
    if chargeAbility == nil then
        print('[BP_ResourcePlanter] Direct plant canceled: consumed-charge ability slots exhausted.')
        return
    end

    local targetKind = params.TargetKind
    local targetIndex = params.TargetIndex
    local planted = false
    if targetKind == 'RESOURCE' then
        local resourceInfo = GameInfo.Resources[targetIndex]
        local domain = bpBuildableResourceDomains[targetIndex]
        if resourceInfo ~= nil
            and domain ~= nil
            and BPHasPlayerUnlockedResource(resourceInfo, player)
            and BPDomainMatchesPlot(domain, plot)
            and BPIsValidResourcePlot(plot, playerID) then
            planted = BPPlaceResource(plot, targetIndex)
        end
    elseif targetKind == 'FEATURE' then
        local featureInfo = GameInfo.Features[targetIndex]
        local domain = bpBuildableFeatureDomains[targetIndex]
        if featureInfo ~= nil
            and domain ~= nil
            and BPDomainMatchesPlot(domain, plot)
            and BPFeatureMatchesTerrain(featureInfo, plot)
            and BPIsValidFeaturePlot(plot, playerID) then
            planted = BPPlaceFeature(plot, targetIndex)
        end
    end

    if not planted then
        print(string.format(
            '[BP_ResourcePlanter] Direct plant failed target=%s index=%s player=%d %s.',
            tostring(targetKind),
            tostring(targetIndex),
            playerID,
            BPDescribePlotForDebug(plot)
        ))
        return
    end

    BPConsumeBuilderCharge(unit, chargeAbility)
    print(string.format(
        '[BP_ResourcePlanter] Direct plant succeeded target=%s index=%s player=%d chargeAbility=%s %s.',
        tostring(targetKind),
        tostring(targetIndex),
        playerID,
        tostring(chargeAbility),
        BPDescribePlotForDebug(plot)
    ))
end

local function BPSyncAllVisibleResourceYieldProperties()
    local syncedCount = 0

    for plotIndex = 0, Map.GetPlotCount() - 1 do
        local plot = Map.GetPlotByIndex(plotIndex)
        if plot ~= nil then
            BPSyncResourceYieldProperties(plot)
            if plot:GetResourceType() ~= -1 then
                syncedCount = syncedCount + 1
            end
        end
    end

    print(string.format('[BP_ResourcePlanter] Synced visible-resource yield property on %d plots.', syncedCount))
end

local function BPSanitizeExistingDummyImprovements()
    local cleanedCount = 0

    for plotIndex = 0, Map.GetPlotCount() - 1 do
        local plot = Map.GetPlotByIndex(plotIndex)
        if plot ~= nil then
            local improvementIndex = plot:GetImprovementType()
            if improvementIndex ~= -1 and bpTrackedImprovementIndexes[improvementIndex] then
                local resourceIndex = bpImprovementToResource[improvementIndex]
                local featureIndex = bpImprovementToFeature[improvementIndex]
                local plotResourceIndex = plot:GetResourceType()
                local plotFeatureIndex = plot:GetFeatureType()

                if (resourceIndex ~= nil and plotResourceIndex == resourceIndex)
                    or (featureIndex ~= nil and plotFeatureIndex == featureIndex) then
                    BPClearImprovement(plot)
                    cleanedCount = cleanedCount + 1
                else
                    local owner = plot:GetOwner()
                    if owner ~= -1 then
                        BPOnImprovementAddedToMap(plot:GetX(), plot:GetY(), improvementIndex, owner)
                    else
                        BPClearImprovement(plot)
                        cleanedCount = cleanedCount + 1
                    end
                end
            end
        end
    end

    print(string.format('[BP_ResourcePlanter] Sanitized %d lingering dummy improvements on load.', cleanedCount))
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 初始化
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
local function BPInitialize()
    BPInitLookup()
    BPSanitizeExistingDummyImprovements()
    BPSyncAllVisibleResourceYieldProperties()
    Events.ImprovementAddedToMap.Add(BPOnImprovementAddedToMap)
    GameEvents.BPPlantTarget.Add(BPExecutePlantTarget)
    print('[BP_ResourcePlanter] Initialized with independent planting and legacy dummy cleanup.')
end

-- Lua gameplay 脚本启动时，游戏状态还没完全准备好，所以这里和上游模组一样，
-- 挂到 "view state done" 的加载完成事件上再初始化。
Events.LoadGameViewStateDone.Add(BPInitialize)
