-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Builder Plants Resources  -  数据层
-- 实现思路沿用 "Settlers Build Districts"：为每个目标资源注册一个可由建造者
-- 建造的占位改良设施，再由 gameplay 脚本把这个新建的占位改良转换成同格子的
-- 真实资源。
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 第 1 步：收集所有可种植资源（加成 / 奢侈 / 战略）。
--          这里不手工维护资源名单，而是完全由数据库驱动，这样只要 DLC 或其它
--          模组的资源遵循标准 ResourceClassType 标签，就会被自动纳入。
--          纯资源分类占位项（ARTIFACT / CITYSTATE / KNOWLEDGE）会被排除。
--          此外必须再叠加"地图自然生成"过滤：Civ6 原版 Resources 表用 Frequency
--          表示陆地、SeaFrequency 表示海洋的自然生成频率权重（均 NOT NULL DEFAULT 0，
--          见 Base/Assets/Gameplay/Data/Schema/01_GameplaySchema.sql:2325-2344）。
--          凡是 Frequency=0 且 SeaFrequency=0 的资源（例如 6 个垄断/独特奢侈
--          RESOURCE_JEANS / PERFUME / COSMETICS / TOYS / CINNAMON / CLOVES，
--          详见 Resources.xml:207-212）地图上从不随机生成，引擎对它们的
--          spawn/渲染路径未初始化，强行种植会让 SetResourceType 在客户端崩溃。
--          所以"可种植资源"必须同时满足类属过滤 + 至少有一侧频率 > 0。
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS BPBuildableResources (
    ResourceName   TEXT PRIMARY KEY,   -- 去掉 'RESOURCE_' 前缀后的资源类型名
    PrereqTech     TEXT,
    PrereqCivic    TEXT,
    Domain         TEXT                  -- DOMAIN_LAND 或 DOMAIN_SEA
);

-- Domain 由资源允许出现的地形反推。
-- 只要某资源的任一合法地形是陆地，就归为 DOMAIN_LAND（这样像石油这种可陆可海
-- 的资源仍会归到更常见的陆地种植场景）；否则归为 DOMAIN_SEA（纯海洋资源，例如
-- 鲸鱼或珍珠）。
-- 对于香蕉、可可豆、丝绸这类“只声明合法地貌、不声明合法地形”的资源，还要继续
-- 看 Resource_ValidFeatures 对应的 Feature_ValidTerrains：只要这些地貌能落在任一
-- 非海洋地形上，也应判为 DOMAIN_LAND，而不是误回退成海洋资源。
-- 这里依赖地形名称，而不是可选的 Terrains.Water 字段，这样即便别的模组改了字段
-- 命名，查询也更稳。
-- 只纳入标准的玩家可见资源类别，并且必须能被地图自然生成（任意一侧频率 > 0），
-- 以排除垄断/独特奢侈（不会被地图刷出、引擎也未初始化其种植路径）。
INSERT OR REPLACE INTO BPBuildableResources (ResourceName, PrereqTech, PrereqCivic, Domain)
SELECT
    REPLACE(R.ResourceType, 'RESOURCE_', ''),
    R.PrereqTech,
    R.PrereqCivic,
    CASE
        WHEN EXISTS (
            SELECT 1 FROM Resource_ValidTerrains VT
            WHERE VT.ResourceType = R.ResourceType
              AND VT.TerrainType NOT IN ('TERRAIN_COAST','TERRAIN_OCEAN')
        )
        OR EXISTS (
            SELECT 1
            FROM Resource_ValidFeatures RVF
            JOIN Feature_ValidTerrains FVT ON FVT.FeatureType = RVF.FeatureType
            JOIN Features F ON F.FeatureType = RVF.FeatureType
            WHERE RVF.ResourceType = R.ResourceType
              AND F.NaturalWonder = 0
              AND FVT.TerrainType NOT IN ('TERRAIN_COAST','TERRAIN_OCEAN')
        )
        THEN 'DOMAIN_LAND'
        ELSE 'DOMAIN_SEA'
    END AS Domain
FROM Resources R
WHERE R.ResourceClassType IN ('RESOURCECLASS_BONUS','RESOURCECLASS_LUXURY','RESOURCECLASS_STRATEGIC')
  -- 关键过滤：只保留"地图会随机生成"的资源。Frequency = 陆地频率，
  -- SeaFrequency = 海洋频率，二者皆 0 表示不会被地图刷出（如 6 种垄断奢侈），
  -- 强行种植会触发引擎内 SetResourceType 的崩溃，必须排除。
  AND (R.Frequency > 0 OR R.SeaFrequency > 0);

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 第 2 步：为占位改良准备合法地形 / 地貌列表。
--          这里复用原模组的允许列表，以保持与“游戏认为人工建筑可以放在哪些格子上”
--          的规则一致。
--          丘陵仍然像原模组那样并入同一个 Domain 桶。
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS BPValidTerrains (TerrainType TEXT PRIMARY KEY, Domain TEXT);
INSERT OR REPLACE INTO BPValidTerrains (TerrainType, Domain) VALUES
    ('TERRAIN_GRASS',           'DOMAIN_LAND'),
    ('TERRAIN_PLAINS',          'DOMAIN_LAND'),
    ('TERRAIN_DESERT',          'DOMAIN_LAND'),
    ('TERRAIN_TUNDRA',          'DOMAIN_LAND'),
    ('TERRAIN_SNOW',            'DOMAIN_LAND'),
    ('TERRAIN_GRASS_HILLS',     'DOMAIN_LAND'),
    ('TERRAIN_PLAINS_HILLS',    'DOMAIN_LAND'),
    ('TERRAIN_DESERT_HILLS',    'DOMAIN_LAND'),
    ('TERRAIN_TUNDRA_HILLS',    'DOMAIN_LAND'),
    ('TERRAIN_SNOW_HILLS',      'DOMAIN_LAND'),
    ('TERRAIN_COAST',           'DOMAIN_SEA' ),
    ('TERRAIN_OCEAN',           'DOMAIN_SEA' );

CREATE TABLE IF NOT EXISTS BPValidFeatures (FeatureType TEXT PRIMARY KEY, Domain TEXT);
INSERT OR REPLACE INTO BPValidFeatures (FeatureType, Domain)
SELECT DISTINCT FT.FeatureType, T.Domain
FROM Feature_ValidTerrains FT, Features F, BPValidTerrains T
WHERE FT.TerrainType = T.TerrainType
  AND FT.FeatureType = F.FeatureType
  AND F.NaturalWonder = 0;

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 第 3 步：为每个资源注册一个占位改良设施。
--          名称格式为 'IMPROVEMENT_BP_<ResourceName>'。图标直接复用资源自身的
--          图标定义（'ICON_RESOURCE_<ResourceName>'），这样建造菜单里显示的就
--          是正确的资源图案。
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
INSERT OR REPLACE INTO Types (Type, Kind)
SELECT 'IMPROVEMENT_BP_'||B.ResourceName, 'KIND_IMPROVEMENT'
FROM BPBuildableResources B;

INSERT OR REPLACE INTO Improvements (
    ImprovementType, Name,                              Description,                                       Icon,                       PlunderType,     Buildable, Workable, Domain
)
SELECT
    'IMPROVEMENT_BP_'||B.ResourceName,
    R.Name,
    'LOC_IMPROVEMENT_BP_GENERIC_DESCRIPTION',
    'ICON_RESOURCE_'||B.ResourceName,
    'NO_PLUNDER',
    1, 0,
    B.Domain
FROM BPBuildableResources B
JOIN Resources R
  ON R.ResourceType = 'RESOURCE_'||B.ResourceName;
-- 关于 Workable = 0：这个占位改良只是临时出生标记，用来让建造者菜单里有一个
-- 可点选项目，并触发 ImprovementAddedToMap 事件，从而让 Lua 能落下真实资源。
-- 我们刻意把它标记为“不可工作”，原因有两点：
--   1. 任意城市都不会把这个占位改良当作可收获产出的对象（格子最终只应提供资源）。
--   2. 即便 Lua 转换因为读档等原因稍有延迟，占位改良也不会短暂充当“真改良”，
--      不会在等待资源替换期间产出任何收益。
-- Lua 脚本会在设置资源的同一帧移除占位改良，因此玩家最终只会看到资源本身。

-- 让这些占位改良具备抗灾属性（与原模组给区域占位改良加抗灾的技巧一致），避免
-- 可受灾格子上的资源凭空消失。
-- 这里包了一层 sqlite_master 判断，这样即便没有 XP2（Gathering Storm）相关
-- 表结构，文件也能正常加载。
INSERT OR REPLACE INTO Improvements_XP2 (ImprovementType, DisasterResistant)
SELECT 'IMPROVEMENT_BP_'||B.ResourceName, 1
FROM BPBuildableResources B
WHERE EXISTS (
    SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'Improvements_XP2'
);

-- 资源种植不再要求满足原版资源的具体地形 / 地貌落点。
-- 这里仅按 Domain 放开：
--   * 陆地资源：可放在全部陆地地形
--   * 海洋资源：可放在海岸 / 远洋
-- 这样就取消了“香蕉必须雨林”“钻石必须丘陵”等资源级地块限制，只保留陆海域区分。
INSERT OR REPLACE INTO Improvement_ValidTerrains (ImprovementType, TerrainType)
SELECT
    'IMPROVEMENT_BP_'||B.ResourceName,
    VT.TerrainType
FROM BPBuildableResources B
JOIN BPValidTerrains VT ON VT.Domain = B.Domain
;

-- 资源种植不再要求命中特定资源自己的 Feature 条件，但仍要允许建在同域的普通地貌格上，
-- 否则像泛滥平原、沼泽、森林、雨林这类带 Feature 的合法陆地格会被游戏底层直接判成
-- “改良不可建造”，按钮整颗发灰。这里统一按 Domain 放开普通地貌：
--   * 陆地资源：允许全部陆地地貌
--   * 海洋资源：允许全部海洋地貌
-- 仍然依赖 BPValidFeatures 过滤自然奇观等不该动的特殊地貌。
DELETE FROM Improvement_ValidFeatures
WHERE ImprovementType IN (
    SELECT 'IMPROVEMENT_BP_'||B.ResourceName
    FROM BPBuildableResources B
);

INSERT OR REPLACE INTO Improvement_ValidFeatures (ImprovementType, FeatureType)
SELECT
    'IMPROVEMENT_BP_'||B.ResourceName,
    VF.FeatureType
FROM BPBuildableResources B
JOIN BPValidFeatures VF ON VF.Domain = B.Domain;

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 第 4 步：把建造者挂到每个占位改良上。
--          不修改 BuildCharges，仍然保持原版 3 次充能，这样每次种植资源都还是
--          正常消耗 1 次建造者充能。
--          只有玩家可以种植，AI 会在 Lua 层被拦住，避免它胡乱刷资源。
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
INSERT OR REPLACE INTO Improvement_ValidBuildUnits (ImprovementType, UnitType)
SELECT 'IMPROVEMENT_BP_'||B.ResourceName, 'UNIT_BUILDER'
FROM BPBuildableResources B;

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 第 5 步：注册可种植地貌（森林 / 雨林）。
--          它们不混入 BPBuildableResources，而是走一张独立表，避免把原版 Feature
--          伪装成 Resource。雨林在原版数据里对应 FEATURE_JUNGLE。
--          地貌列表不再绑定任何科技 / 市政前置；只要格子合法，就允许直接种植。
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS BPBuildableFeatures (
    FeatureType   TEXT PRIMARY KEY,
    Name          TEXT NOT NULL,
    Icon          TEXT NOT NULL,
    PrereqTech    TEXT,
    PrereqCivic   TEXT,
    Domain        TEXT NOT NULL
);

INSERT OR REPLACE INTO BPBuildableFeatures (FeatureType, Name, Icon, PrereqTech, PrereqCivic, Domain)
SELECT
    F.FeatureType,
    F.Name,
    'ICON_UNITOPERATION_PLANT_FOREST',
    NULL,
    NULL,
    'DOMAIN_LAND'
FROM Features F
WHERE F.FeatureType IN ('FEATURE_FOREST', 'FEATURE_JUNGLE')
  AND F.NaturalWonder = 0;

INSERT OR REPLACE INTO Types (Type, Kind)
SELECT 'IMPROVEMENT_BP_' || REPLACE(BF.FeatureType, 'FEATURE_', 'FEATURE_'), 'KIND_IMPROVEMENT'
FROM BPBuildableFeatures BF;

INSERT OR REPLACE INTO Improvements (
    ImprovementType, Name,                               Description,                                              Icon,      PlunderType, Buildable, Workable, Domain
)
SELECT
    'IMPROVEMENT_BP_' || REPLACE(BF.FeatureType, 'FEATURE_', 'FEATURE_'),
    BF.Name,
    'LOC_IMPROVEMENT_BP_GENERIC_FEATURE_DESCRIPTION',
    BF.Icon,
    'NO_PLUNDER',
    1, 0,
    BF.Domain
FROM BPBuildableFeatures BF;

INSERT OR REPLACE INTO Improvements_XP2 (ImprovementType, DisasterResistant)
SELECT 'IMPROVEMENT_BP_' || REPLACE(BF.FeatureType, 'FEATURE_', 'FEATURE_'), 1
FROM BPBuildableFeatures BF
WHERE EXISTS (
    SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'Improvements_XP2'
);

INSERT OR REPLACE INTO Improvement_ValidTerrains (ImprovementType, TerrainType)
SELECT
    'IMPROVEMENT_BP_' || REPLACE(BF.FeatureType, 'FEATURE_', 'FEATURE_'),
    FVT.TerrainType
FROM BPBuildableFeatures BF
JOIN Feature_ValidTerrains FVT ON FVT.FeatureType = BF.FeatureType;

INSERT OR REPLACE INTO Improvement_ValidBuildUnits (ImprovementType, UnitType)
SELECT 'IMPROVEMENT_BP_' || REPLACE(BF.FeatureType, 'FEATURE_', 'FEATURE_'), 'UNIT_BUILDER'
FROM BPBuildableFeatures BF;

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 第 6 步：资源解锁时机仍沿用 Resources 表，但不再把前置直接写回占位改良。
--          原因：Improvement.PrereqTech / PrereqCivic 会让科技树 / 市政树把这些
--          临时占位改良也当成正式解锁项展示，出现资源旁边多一张额外图标。
--          改良是否应出现在建造者面板，改由 UnitPanel 共享 Lua 依据
--          BPBuildableResources 对应资源的 PrereqTech / PrereqCivic 做本地过滤。
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- 第 7 步：把“资源可见性”判定包装成通用兼容层，兼容所有走标准
--          REQUIREMENT_PLOT_RESOURCE_VISIBLE 的官方 / 模组领袖与加成。
--          同时也要兼容 REQUIREMENT_PLOT_RESOURCE_CLASS_TYPE_MATCHES
--          （例如蒸汽时代维多利亚的“战略资源 +2 生产力”）。
--          根因不是某个 leader modifier 数值写错，而是 ResourceBuilder.SetResourceType
--          在 gameplay 运行时新塞资源后，不会稳定重算这类“按资源是否可见筛 plot yield /
--          adjacency / building modifier”的 requirement；对部分“资源类别匹配”判定也有
--          同样的问题。
--          这里不按领袖 / 总督 / 万神殿逐个点名修，而是：
--            1. 扫描所有 RequirementType = REQUIREMENT_PLOT_RESOURCE_VISIBLE 的 requirement；
--            2. 为每个 requirement 包一层 TEST_ANY：
--               - 原始“资源可见”判定；
--               - 本模组 Lua 在种植 / 读档时同步到地块上的
--                 BP_VisibleResourceForYieldBonuses property；
--            3. 扫描所有 RequirementType = REQUIREMENT_PLOT_RESOURCE_CLASS_TYPE_MATCHES 且
--               资源类别属于 BONUS / LUXURY / STRATEGIC 的 requirement；
--            4. 为这些 requirement 同样包一层 TEST_ANY：
--               - 原始“资源类别匹配”判定；
--               - 本模组 Lua 同步到地块上的类别布尔 property。
--            5. 把 RequirementSetRequirements 对这些 requirement 的引用统一改挂到 wrapper。
--          这样官方内容与按标准写法实现的 mod 领袖，都能在运行时种出资源后立即吃到
--          同一套加成，而不再依赖固定 RequirementId / ModifierId 名字。
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS BP_VisibleResourceRequirementsToWrap;

CREATE TEMP TABLE BP_VisibleResourceRequirementsToWrap AS
SELECT R.RequirementId AS RequirementId
FROM Requirements R
WHERE R.RequirementType = 'REQUIREMENT_PLOT_RESOURCE_VISIBLE'
  AND R.RequirementId NOT LIKE 'BP_VISIBLE_RESOURCE_%';

INSERT OR IGNORE INTO Requirements (RequirementId, RequirementType) VALUES
    ('BP_REQUIRES_PLOT_SYNCED_VISIBLE_RESOURCE_PROPERTY', 'REQUIREMENT_PLOT_PROPERTY_MATCHES');

INSERT OR REPLACE INTO RequirementArguments (RequirementId, Name, Value) VALUES
    ('BP_REQUIRES_PLOT_SYNCED_VISIBLE_RESOURCE_PROPERTY', 'PropertyName', 'BP_VisibleResourceForYieldBonuses'),
    ('BP_REQUIRES_PLOT_SYNCED_VISIBLE_RESOURCE_PROPERTY', 'PropertyMinimum', '1');

INSERT OR IGNORE INTO RequirementSets (RequirementSetId, RequirementSetType)
SELECT
    'BP_VISIBLE_RESOURCE_WRAPPER_SET_' || RequirementId,
    'REQUIREMENTSET_TEST_ANY'
FROM BP_VisibleResourceRequirementsToWrap;

INSERT OR IGNORE INTO Requirements (RequirementId, RequirementType)
SELECT
    'BP_VISIBLE_RESOURCE_WRAPPER_REQ_' || RequirementId,
    'REQUIREMENT_REQUIREMENTSET_IS_MET'
FROM BP_VisibleResourceRequirementsToWrap;

INSERT OR IGNORE INTO Requirements (RequirementId, RequirementType)
SELECT
    'BP_VISIBLE_RESOURCE_ORIGINAL_REQ_' || RequirementId,
    'REQUIREMENT_PLOT_RESOURCE_VISIBLE'
FROM BP_VisibleResourceRequirementsToWrap;

INSERT OR REPLACE INTO RequirementArguments (RequirementId, Name, Value)
SELECT
    'BP_VISIBLE_RESOURCE_WRAPPER_REQ_' || RequirementId,
    'RequirementSetId',
    'BP_VISIBLE_RESOURCE_WRAPPER_SET_' || RequirementId
FROM BP_VisibleResourceRequirementsToWrap;

INSERT OR IGNORE INTO RequirementSetRequirements (RequirementSetId, RequirementId)
SELECT
    'BP_VISIBLE_RESOURCE_WRAPPER_SET_' || RequirementId,
    'BP_VISIBLE_RESOURCE_ORIGINAL_REQ_' || RequirementId
FROM BP_VisibleResourceRequirementsToWrap;

INSERT OR IGNORE INTO RequirementSetRequirements (RequirementSetId, RequirementId)
SELECT
    'BP_VISIBLE_RESOURCE_WRAPPER_SET_' || RequirementId,
    'BP_REQUIRES_PLOT_SYNCED_VISIBLE_RESOURCE_PROPERTY'
FROM BP_VisibleResourceRequirementsToWrap;

UPDATE RequirementSetRequirements
SET RequirementId = 'BP_VISIBLE_RESOURCE_WRAPPER_REQ_' || RequirementSetRequirements.RequirementId
WHERE EXISTS (
    SELECT 1
    FROM BP_VisibleResourceRequirementsToWrap W
    WHERE W.RequirementId = RequirementSetRequirements.RequirementId
);

DROP TABLE IF EXISTS BP_VisibleResourceRequirementsToWrap;

DROP TABLE IF EXISTS BP_ResourceClassRequirementsToWrap;

CREATE TEMP TABLE BP_ResourceClassRequirementsToWrap AS
SELECT
    R.RequirementId AS RequirementId,
    MAX(CASE WHEN RA.Name = 'ResourceClassType' THEN RA.Value END) AS ResourceClassType,
    CASE MAX(CASE WHEN RA.Name = 'ResourceClassType' THEN RA.Value END)
        WHEN 'RESOURCECLASS_BONUS' THEN 'BP_HasBonusResourceForYieldBonuses'
        WHEN 'RESOURCECLASS_LUXURY' THEN 'BP_HasLuxuryResourceForYieldBonuses'
        WHEN 'RESOURCECLASS_STRATEGIC' THEN 'BP_HasStrategicResourceForYieldBonuses'
    END AS PropertyName
FROM Requirements R
JOIN RequirementArguments RA ON RA.RequirementId = R.RequirementId
WHERE R.RequirementType = 'REQUIREMENT_PLOT_RESOURCE_CLASS_TYPE_MATCHES'
GROUP BY R.RequirementId
HAVING MAX(CASE WHEN RA.Name = 'ResourceClassType' THEN RA.Value END) IN (
    'RESOURCECLASS_BONUS',
    'RESOURCECLASS_LUXURY',
    'RESOURCECLASS_STRATEGIC'
);

INSERT OR IGNORE INTO RequirementSets (RequirementSetId, RequirementSetType)
SELECT
    'BP_RESOURCE_CLASS_WRAPPER_SET_' || RequirementId,
    'REQUIREMENTSET_TEST_ANY'
FROM BP_ResourceClassRequirementsToWrap;

INSERT OR IGNORE INTO Requirements (RequirementId, RequirementType)
SELECT
    'BP_RESOURCE_CLASS_WRAPPER_REQ_' || RequirementId,
    'REQUIREMENT_REQUIREMENTSET_IS_MET'
FROM BP_ResourceClassRequirementsToWrap;

INSERT OR IGNORE INTO Requirements (RequirementId, RequirementType)
SELECT
    'BP_RESOURCE_CLASS_ORIGINAL_REQ_' || RequirementId,
    'REQUIREMENT_PLOT_RESOURCE_CLASS_TYPE_MATCHES'
FROM BP_ResourceClassRequirementsToWrap;

INSERT OR IGNORE INTO Requirements (RequirementId, RequirementType)
SELECT
    'BP_RESOURCE_CLASS_PROPERTY_REQ_' || RequirementId,
    'REQUIREMENT_PLOT_PROPERTY_MATCHES'
FROM BP_ResourceClassRequirementsToWrap;

INSERT OR REPLACE INTO RequirementArguments (RequirementId, Name, Value)
SELECT
    'BP_RESOURCE_CLASS_WRAPPER_REQ_' || RequirementId,
    'RequirementSetId',
    'BP_RESOURCE_CLASS_WRAPPER_SET_' || RequirementId
FROM BP_ResourceClassRequirementsToWrap;

INSERT OR REPLACE INTO RequirementArguments (RequirementId, Name, Value)
SELECT
    'BP_RESOURCE_CLASS_ORIGINAL_REQ_' || RequirementId,
    'ResourceClassType',
    ResourceClassType
FROM BP_ResourceClassRequirementsToWrap;

INSERT OR REPLACE INTO RequirementArguments (RequirementId, Name, Value)
SELECT
    'BP_RESOURCE_CLASS_PROPERTY_REQ_' || RequirementId,
    'PropertyName',
    PropertyName
FROM BP_ResourceClassRequirementsToWrap;

INSERT OR REPLACE INTO RequirementArguments (RequirementId, Name, Value)
SELECT
    'BP_RESOURCE_CLASS_PROPERTY_REQ_' || RequirementId,
    'PropertyMinimum',
    '1'
FROM BP_ResourceClassRequirementsToWrap;

INSERT OR IGNORE INTO RequirementSetRequirements (RequirementSetId, RequirementId)
SELECT
    'BP_RESOURCE_CLASS_WRAPPER_SET_' || RequirementId,
    'BP_RESOURCE_CLASS_ORIGINAL_REQ_' || RequirementId
FROM BP_ResourceClassRequirementsToWrap;

INSERT OR IGNORE INTO RequirementSetRequirements (RequirementSetId, RequirementId)
SELECT
    'BP_RESOURCE_CLASS_WRAPPER_SET_' || RequirementId,
    'BP_RESOURCE_CLASS_PROPERTY_REQ_' || RequirementId
FROM BP_ResourceClassRequirementsToWrap;

UPDATE RequirementSetRequirements
SET RequirementId = 'BP_RESOURCE_CLASS_WRAPPER_REQ_' || RequirementSetRequirements.RequirementId
WHERE EXISTS (
    SELECT 1
    FROM BP_ResourceClassRequirementsToWrap W
    WHERE W.RequirementId = RequirementSetRequirements.RequirementId
);

DROP TABLE IF EXISTS BP_ResourceClassRequirementsToWrap;
