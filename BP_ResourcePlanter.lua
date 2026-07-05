-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Builder Plants Resources  -  Gameplay 脚本
--
-- 当建造者建成任意一个占位改良（'IMPROVEMENT_BP_<ResourceName>'）时，
-- 把它原地转换成对应的真实资源。
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

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 建立查找表：占位改良索引 -> 资源索引
-- 改良名称格式为 'IMPROVEMENT_BP_<ResourceName>'，其中 <ResourceName> 是去掉
-- 'RESOURCE_' 前缀后的资源名。脚本初始化时从 GameInfo 反推这层映射，避免在 Lua
-- 里写死资源名单。
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
local bpImprovementToResource = {}      -- [improvementIndex] = resourceIndex
local bpTrackedImprovementIndexes = {}  -- 快速判断“这个改良是不是本模组的”
local bpConvertingPlots = {}            -- 以地块索引为键的防重入保护

local function BPInitLookup()
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
    local count = 0
    for _ in pairs(bpImprovementToResource) do count = count + 1 end
    print(string.format('[BP_ResourcePlanter] Tracked %d resource-planting improvements.', count))
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 辅助函数
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
local function BPClearImprovement(plot)
    ImprovementBuilder.SetImprovementType(plot, -1, -1)
end

local function BPIsValidPlot(plot, player)
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

    -- 排除任何已经带资源的格子：防止重复种植或覆盖原资源。
    if plot:GetResourceType() ~= -1 then
        return false
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

local function BPPlaceResource(plot, resourceIndex, actingPlayerIndex)
    -- 最终状态约束：格子上只留下资源本身。触发本事件的占位改良会在同一次调用里
    -- 被移除，因此玩家不会看到一个完成态“改良设施”压在资源上。
    --
    -- 按照模组社区常见做法，先清改良（并且走 ImprovementBuilder 路径，让
    -- Events.ImprovementRemovedFromMap 也能触发），再设置资源。这样可以确保
    -- 宜居度 / 战略储备等收益立刻刷新，而不是要等到重载后才正确。
    -- SetResourceType 的数量设为 1，这与原版加成 / 奢侈资源的单格规模，以及
    -- 单格战略资源的 1 单位产出保持一致。
    BPClearImprovement(plot)
    ResourceBuilder.SetResourceType(plot, resourceIndex, 1)
    BPClearImprovement(plot)
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
        print('[BP_ResourcePlanter] Conversion canceled: AI players may not plant resources.')
        bpConvertingPlots[plotKey] = nil
        return
    end

    -- 校验地块。如果不合法，就回滚占位改良，避免玩家看到与现有内容重叠的假占位物。
    if not BPIsValidPlot(plot, playerID) then
        BPClearImprovement(plot)
        print('[BP_ResourcePlanter] Conversion canceled: plot ('..x..','..y..') is not eligible (already has resource / wonder / foreign territory).')
        bpConvertingPlots[plotKey] = nil
        return
    end

    local resourceIndex = bpImprovementToResource[improvementIndex]
    if resourceIndex == nil then
        BPClearImprovement(plot)
        print('[BP_ResourcePlanter] Conversion canceled: no resource mapping for improvement index '..tostring(improvementIndex)..'.')
        bpConvertingPlots[plotKey] = nil
        return
    end

    local resourceName = Locale.Lookup(GameInfo.Resources[resourceIndex].Name)
    BPPlaceResource(plot, resourceIndex, playerID)
    print(string.format('[BP_ResourcePlanter] Planted %s at (%d,%d) for player %d.',
        resourceName, x, y, playerID))
    bpConvertingPlots[plotKey] = nil
end

local function BPSanitizeExistingDummyImprovements()
    local cleanedCount = 0

    for plotIndex = 0, Map.GetPlotCount() - 1 do
        local plot = Map.GetPlotByIndex(plotIndex)
        if plot ~= nil then
            local improvementIndex = plot:GetImprovementType()
            if improvementIndex ~= -1 and bpTrackedImprovementIndexes[improvementIndex] then
                if plot:GetResourceType() ~= -1 then
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
    Events.ImprovementAddedToMap.Add(BPOnImprovementAddedToMap)
    print('[BP_ResourcePlanter] Initialized and listening for improvement placements.')
end

-- Lua gameplay 脚本启动时，游戏状态还没完全准备好，所以这里和上游模组一样，
-- 挂到 "view state done" 的加载完成事件上再初始化。
Events.LoadGameViewStateDone.Add(BPInitialize)
