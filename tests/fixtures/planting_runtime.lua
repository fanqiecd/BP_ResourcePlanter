-- Minimal Civ VI boundaries; the tests execute the actual gameplay/UI scripts.
local function rows(data, key)
    local result = {}
    for _, row in ipairs(data) do
        if row.Index ~= nil then result[row.Index] = row end
        if key then result[row[key]] = row end
    end
    return setmetatable(result, {__call = function()
        local index = 0
        return function() index = index + 1; return data[index] end
    end})
end

local function events()
    return setmetatable({}, {__index = function(self, name)
        local callbacks = {}
        local event = setmetatable({Add = function(fn)
            table.insert(callbacks, fn)
        end}, {__call = function(_, ...)
            for _, fn in ipairs(callbacks) do fn(...) end
        end})
        rawset(self, name, event)
        return event
    end})
end

Events, GameEvents, LuaEvents = events(), events(), events()
ExposedMembers = {}
print = function() end
ContextPtr = {SetInitHandler = function() end}
GameConfiguration = {GetValue = function() return State.rules end}
Game = {GetLocalPlayer = function() return 0 end}
Locale = {
    Lookup = function(value) return value end,
    Compare = function(a, b) return a == b and 0 or (a < b and -1 or 1) end
}

GameInfo = {
    TypeTags = rows({{Type = 'UNIT_BUILDER', Tag = 'CLASS_BUILDER'}}),
    Units = rows({{Index = 0, UnitType = 'UNIT_BUILDER'}}, 'UnitType'),
    Resources = rows({
        {Index = 0, Hash = 100, ResourceType = 'RESOURCE_STONE', Name = 'Stone', ResourceClassType = 'RESOURCECLASS_BONUS'},
        {Index = 1, Hash = 101, ResourceType = 'RESOURCE_DEER', Name = 'Deer', ResourceClassType = 'RESOURCECLASS_BONUS'},
        {Index = 2, Hash = 102, ResourceType = 'RESOURCE_BANANAS', Name = 'Bananas', ResourceClassType = 'RESOURCECLASS_BONUS'},
        {Index = 3, Hash = 103, ResourceType = 'RESOURCE_MODDED', Name = 'Modded', ResourceClassType = 'RESOURCECLASS_LUXURY'}
    }, 'ResourceType'),
    Features = rows({
        {Index = 0, FeatureType = 'FEATURE_FOREST', Name = 'Forest', NaturalWonder = 0},
        {Index = 1, FeatureType = 'FEATURE_JUNGLE', Name = 'Rainforest', NaturalWonder = 0}
    }, 'FeatureType'),
    Terrains = rows({
        {Index = 0, TerrainType = 'TERRAIN_GRASS'},
        {Index = 1, TerrainType = 'TERRAIN_DESERT'},
        {Index = 2, TerrainType = 'TERRAIN_PLAINS'}
    }, 'TerrainType'),
    Resource_ValidTerrains = rows({{ResourceType = 'RESOURCE_STONE', TerrainType = 'TERRAIN_GRASS'}}),
    Resource_ValidFeatures = rows({
        {ResourceType = 'RESOURCE_DEER', FeatureType = 'FEATURE_FOREST'},
        {ResourceType = 'RESOURCE_BANANAS', FeatureType = 'FEATURE_JUNGLE'},
        {ResourceType = 'RESOURCE_MODDED', FeatureType = 'FEATURE_FOREST'}
    }),
    Feature_ValidTerrains = rows({
        {FeatureType = 'FEATURE_FOREST', TerrainType = 'TERRAIN_GRASS'},
        {FeatureType = 'FEATURE_FOREST', TerrainType = 'TERRAIN_PLAINS'},
        {FeatureType = 'FEATURE_JUNGLE', TerrainType = 'TERRAIN_PLAINS'}
    }),
    BPBuildableResources = rows({{ResourceName = 'STONE', Domain = 'DOMAIN_LAND'}}),
    BPBuildableFeatures = rows({
        {FeatureType = 'FEATURE_FOREST', Domain = 'DOMAIN_LAND'},
        {FeatureType = 'FEATURE_JUNGLE', Domain = 'DOMAIN_LAND'}
    }),
    Improvements = rows({
        {Index = 10, ImprovementType = 'IMPROVEMENT_BP_FEATURE_FOREST'},
        {Index = 11, ImprovementType = 'IMPROVEMENT_BP_FEATURE_JUNGLE'}
    }, 'ImprovementType'),
    BPChargeSlots = rows({{Slot = 1}, {Slot = 2}, {Slot = 3}})
}

State = {rules = true, resource = -1, feature = -1, terrain = 0,
    improvement = -1, charges = 3, moves = 2, featureWrites = 0, properties = {}}
Plot = {
    GetResourceType = function() return State.resource end,
    GetFeatureType = function() return State.feature end,
    GetTerrainType = function() return State.terrain end,
    GetImprovementType = function() return State.improvement end,
    GetDistrictType = function() return -1 end,
    GetOwner = function() return 0 end,
    GetX = function() return 0 end,
    GetY = function() return 0 end,
    IsNaturalWonder = function() return false end,
    IsWater = function() return false end,
    SetProperty = function(_, name, value) State.properties[name] = value end
}
Map = {
    GetPlot = function() return Plot end,
    GetPlotByIndex = function() return Plot end,
    GetPlotIndex = function() return 0 end,
    GetPlotCount = function() return 1 end
}
local abilities = {}
Unit = {
    GetType = function() return 0 end,
    GetOwner = function() return 0 end,
    GetID = function() return 0 end,
    GetX = function() return 0 end,
    GetY = function() return 0 end,
    GetBuildCharges = function() return State.charges end,
    GetMovesRemaining = function() return State.moves end,
    GetAbility = function() return {
        GetAbilityCount = function(_, name) return abilities[name] or 0 end,
        ChangeAbilityCount = function(_, name, amount)
            abilities[name] = (abilities[name] or 0) + amount
            State.charges = State.charges - amount
        end
    } end
}
UnitManager = {
    GetUnit = function() return Unit end,
    FinishMoves = function() State.moves = 0 end
}
Players = {[0] = {IsHuman = function() return true end}}
ImprovementBuilder = {SetImprovementType = function(_, value) State.improvement = value end}
TerrainBuilder = {SetFeatureType = function(_, value)
    State.featureWrites = State.featureWrites + 1
    State.feature = value
end}
ResourceBuilder = {
    CanHaveResource = function(_, hash)
        return hash == 100 and State.terrain == 0 and State.feature == -1 and State.resource == -1
    end,
    SetResourceType = function(_, value) State.resource = value end
}
