-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Builder Plants Resources  -  本地化文本
-- UpdateText 运行在本地化数据库上，而不是 Gameplay 数据库，因此这里不能
-- 直接从 Resources 之类的 Gameplay 表中 SELECT。改良项目名称因此在
-- BP_ResourcePlanter.sql 中直接复用资源自身的 Name 标签，而本文件只提供
-- 文本库能够稳定加载的静态通用描述。
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

INSERT OR REPLACE INTO LocalizedText (Tag, Language, Text) VALUES
    ('LOC_IMPROVEMENT_BP_GENERIC_DESCRIPTION', 'en_US', 'Plants this resource on the selected tile.'),
    ('LOC_IMPROVEMENT_BP_GENERIC_DESCRIPTION', 'zh_Hans_CN', '在所选格子上种植该资源。');
