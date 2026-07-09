-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Builder Plants Resources  -  本地化文本
-- UpdateText 运行在本地化数据库上，而不是 Gameplay 数据库，因此这里不能
-- 直接从 Resources 之类的 Gameplay 表中 SELECT。改良项目名称因此在
-- BP_ResourcePlanter.sql 中直接复用资源自身的 Name 标签，而本文件只提供
-- 文本库能够稳定加载的静态通用描述。
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

INSERT OR REPLACE INTO LocalizedText (Tag, Language, Text) VALUES
    ('LOC_IMPROVEMENT_BP_GENERIC_DESCRIPTION', 'en_US', 'Plants this resource on the selected tile.'),
    ('LOC_IMPROVEMENT_BP_GENERIC_DESCRIPTION', 'zh_Hans_CN', '在所选格子上种植该资源。'),
    ('LOC_IMPROVEMENT_BP_GENERIC_FEATURE_DESCRIPTION', 'en_US', 'Plants this feature on the selected tile.'),
    ('LOC_IMPROVEMENT_BP_GENERIC_FEATURE_DESCRIPTION', 'zh_Hans_CN', '在所选格子上种植该地貌。'),
    ('LOC_BP_RESOURCE_CHOOSER_TITLE', 'en_US', 'Choose Resource or Feature'),
    ('LOC_BP_RESOURCE_CHOOSER_TITLE', 'zh_Hans_CN', '选择资源或地貌'),
    ('LOC_BP_RESOURCE_CHOOSER_PROMPT', 'en_US', 'Choose a valid resource or feature to plant on this tile.'),
    ('LOC_BP_RESOURCE_CHOOSER_PROMPT', 'zh_Hans_CN', '请选择要在此格子上种植的资源或地貌。'),
    ('LOC_BP_RESOURCE_CHOOSER_ACTION_DESCRIPTION', 'en_US', 'Choose one of the valid resources or features for this tile and plant it.'),
    ('LOC_BP_RESOURCE_CHOOSER_ACTION_DESCRIPTION', 'zh_Hans_CN', '从当前格子可种植的资源或地貌中选择一种进行种植。'),
    ('LOC_BP_RESOURCE_CHOOSER_AVAILABLE', 'en_US', 'Available entries:'),
    ('LOC_BP_RESOURCE_CHOOSER_AVAILABLE', 'zh_Hans_CN', '当前可种植项目：'),
    -- 分类筛选标签(全部/加成/奢侈/战略/地貌)与空类提示。
    ('LOC_BP_FILTER_ALL', 'en_US', 'All'),
    ('LOC_BP_FILTER_ALL', 'zh_Hans_CN', '全部'),
    ('LOC_BP_FILTER_BONUS', 'en_US', 'Bonus'),
    ('LOC_BP_FILTER_BONUS', 'zh_Hans_CN', '加成'),
    ('LOC_BP_FILTER_LUXURY', 'en_US', 'Luxury'),
    ('LOC_BP_FILTER_LUXURY', 'zh_Hans_CN', '奢侈'),
    ('LOC_BP_FILTER_STRATEGIC', 'en_US', 'Strategic'),
    ('LOC_BP_FILTER_STRATEGIC', 'zh_Hans_CN', '战略'),
    ('LOC_BP_FILTER_FEATURE', 'en_US', 'Features'),
    ('LOC_BP_FILTER_FEATURE', 'zh_Hans_CN', '地貌'),
    ('LOC_BP_RESOURCE_CHOOSER_EMPTY_HINT', 'en_US', 'No plantable resources of this class on the current tile.'),
    ('LOC_BP_RESOURCE_CHOOSER_EMPTY_HINT', 'zh_Hans_CN', '当前格子没有可种植的该类资源。');
