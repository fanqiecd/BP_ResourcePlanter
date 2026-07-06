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

-- 放置规则优先跟随资源自身的自然生成规则（Resource_ValidTerrains /
-- Resource_ValidFeatures），而不是只按宽泛的 Domain 分类判断。
-- 这样可以避免玩家把小麦种进雨林、把松露种在冻土丘陵之类的不合理情况，也让每个
-- 占位改良的“合法格子”尽量贴近原版资源自然会出现的位置。
-- 如果某资源没有声明任何 Resource_ValidTerrains，则回退到所在 Domain 的整组
-- 地形白名单，确保它至少还能被建造在某些位置。
INSERT OR REPLACE INTO Improvement_ValidTerrains (ImprovementType, TerrainType)
SELECT
    'IMPROVEMENT_BP_'||B.ResourceName,
    CASE
        WHEN RT.TerrainType IS NOT NULL THEN RT.TerrainType
        ELSE VT.TerrainType
    END
FROM BPBuildableResources B
JOIN BPValidTerrains VT ON VT.Domain = B.Domain
LEFT JOIN (
    SELECT DISTINCT RVT.ResourceType, RVT.TerrainType
    FROM Resource_ValidTerrains RVT
) RT
  ON RT.ResourceType = 'RESOURCE_'||B.ResourceName
  AND RT.TerrainType = VT.TerrainType
WHERE (
    -- 资源显式声明了可生成地形：只允许这些地形的并集。
    EXISTS (SELECT 1 FROM Resource_ValidTerrains RVT WHERE RVT.ResourceType = 'RESOURCE_'||B.ResourceName)
    AND RT.TerrainType IS NOT NULL
) OR (
    -- 资源没有声明任何合法地形：回退到整个 Domain 的地形列表。
    NOT EXISTS (SELECT 1 FROM Resource_ValidTerrains RVT WHERE RVT.ResourceType = 'RESOURCE_'||B.ResourceName)
);

INSERT OR REPLACE INTO Improvement_ValidFeatures (ImprovementType, FeatureType)
SELECT
    'IMPROVEMENT_BP_'||B.ResourceName,
    RF.FeatureType
FROM BPBuildableResources B
JOIN (
    SELECT DISTINCT RFR.ResourceType, RFR.FeatureType
    FROM Resource_ValidFeatures RFR
) RF ON RF.ResourceType = 'RESOURCE_'||B.ResourceName;

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
-- 第 5 步：资源解锁时机仍沿用 Resources 表，但不再把前置直接写回占位改良。
--          原因：Improvement.PrereqTech / PrereqCivic 会让科技树 / 市政树把这些
--          临时占位改良也当成正式解锁项展示，出现资源旁边多一张额外图标。
--          改良是否应出现在建造者面板，改由 UnitPanel 共享 Lua 依据
--          BPBuildableResources 对应资源的 PrereqTech / PrereqCivic 做本地过滤。
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
