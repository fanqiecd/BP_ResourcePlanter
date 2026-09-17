-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Builder Plants Resources  -  跨模组兼容层
--
-- 资源可见性 / 资源类别 Requirement 的包装必须在其他内容的 Requirement 定义之后运行。
-- 因此本文件由独立的高优先级 UpdateDatabase 组件加载，核心资源注册不再占用全局最高顺序。
--
-- ResourceBuilder.SetResourceType 在 gameplay 运行时新塞资源后，不会稳定重算这类
-- “按资源是否可见筛 plot yield / adjacency / building modifier”的 requirement；对部分
-- “资源类别匹配”判定也有同样的问题。
-- 本文件不按领袖 / 总督 / 万神殿逐个点名，而是包装所有标准 Requirement，并用 Lua
-- 同步到地块上的 property 作为兼容判定分支。
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 第 0 步：补登记在核心数据之后才加入的资源。
--          部分资源扩展（例如 Workshop 3787861188“C的资源扩展”）与本模组的核心
--          数据同为 LoadOrder=1000。若本模组先执行，核心 SQL 看不到这些资源，后续
--          选择器也就没有 BPBuildableResources 行可读。兼容层在 10100 执行，因此
--          这里重新扫描当前 Resources 表，把这类资源补进完整的占位设施数据链。
--
--          这里仍只接受标准的加成 / 奢侈 / 战略资源，且要求资源至少有一侧自然生成
--          频率。后一个条件与核心 SQL 保持一致，避免把不会由地图初始化的垄断资源
--          送进 ResourceBuilder.SetResourceType。
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
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
  AND (R.Frequency > 0 OR R.SeaFrequency > 0);

INSERT OR IGNORE INTO Types (Type, Kind)
SELECT 'IMPROVEMENT_BP_'||B.ResourceName, 'KIND_IMPROVEMENT'
FROM BPBuildableResources B;

INSERT OR IGNORE INTO Improvements (
    ImprovementType, Name,                              Description,                                       Icon,                       PlunderType, Buildable, Workable, Domain
)
SELECT
    'IMPROVEMENT_BP_'||B.ResourceName,
    R.Name,
    'LOC_IMPROVEMENT_BP_GENERIC_DESCRIPTION',
    'ICON_RESOURCE_'||B.ResourceName,
    'NO_PLUNDER',
    0, 0,
    B.Domain
FROM BPBuildableResources B
JOIN Resources R
  ON R.ResourceType = 'RESOURCE_'||B.ResourceName;

-- Improvements_XP2 只存在于 Gathering Storm。不要在通用兼容层中直接引用它：
-- SQLite 会先解析 INSERT 的目标表，sqlite_master 的 EXISTS 不能避免原版规则集的
-- “no such table”错误。这里的占位改良只服务于旧存档清理，无需抗灾属性。

INSERT OR IGNORE INTO Improvement_ValidTerrains (ImprovementType, TerrainType)
SELECT
    'IMPROVEMENT_BP_'||B.ResourceName,
    VT.TerrainType
FROM BPBuildableResources B
JOIN BPValidTerrains VT ON VT.Domain = B.Domain;

INSERT OR IGNORE INTO Improvement_ValidFeatures (ImprovementType, FeatureType)
SELECT
    'IMPROVEMENT_BP_'||B.ResourceName,
    VF.FeatureType
FROM BPBuildableResources B
JOIN BPValidFeatures VF ON VF.Domain = B.Domain;

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
