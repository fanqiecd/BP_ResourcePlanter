from __future__ import annotations

import re
import sqlite3
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
CORE_SQL_PATH = REPO_ROOT / "BP_ResourcePlanter.sql"
COMPATIBILITY_SQL_PATH = REPO_ROOT / "BP_ResourcePlanter_Compatibility.sql"
TARGET_MOD_ROOT = Path(
    r"D:\Program Files (x86)\Steam\steamapps\workshop\content\289070\3787861188"
)
TARGET_RESOURCE_TYPES = {
    "RESOURCE_C_ARTICHOKE",
    "RESOURCE_C_AUBERGINE",
    "RESOURCE_C_BEAN",
    "RESOURCE_C_BEET",
    "RESOURCE_C_BENTONITE",
    "RESOURCE_C_CABBAGE",
    "RESOURCE_C_CACTUS",
    "RESOURCE_C_CAMPHOR",
    "RESOURCE_C_CASHEW",
    "RESOURCE_C_CASSAVA",
    "RESOURCE_C_CAULIFLOWER",
    "RESOURCE_C_CHILI",
    "RESOURCE_C_CHINESE_CABBAGE",
    "RESOURCE_C_COPAL",
    "RESOURCE_C_CUCUMBER",
    "RESOURCE_C_DAYLILY",
    "RESOURCE_C_FLAX",
    "RESOURCE_C_GARLIC",
    "RESOURCE_C_GINGER",
    "RESOURCE_C_GOURD",
    "RESOURCE_C_GRAPHITE",
    "RESOURCE_C_HEAVENLY_HORSE",
    "RESOURCE_C_HOPS",
    "RESOURCE_C_KAOLINITE",
    "RESOURCE_C_LACQUER",
    "RESOURCE_C_LAUREL",
    "RESOURCE_C_LETTUCE",
    "RESOURCE_C_LILY",
    "RESOURCE_C_LYCHEE",
    "RESOURCE_C_MUSTARD",
    "RESOURCE_C_OKRA",
    "RESOURCE_C_ONION",
    "RESOURCE_C_OSMANTHUS",
    "RESOURCE_C_PEA",
    "RESOURCE_C_PEANUT",
    "RESOURCE_C_PINEAPPLE",
    "RESOURCE_C_PUMPKIN",
    "RESOURCE_C_RADISH",
    "RESOURCE_C_RAPESEED",
    "RESOURCE_C_RHUBARB",
    "RESOURCE_C_SCALLION",
    "RESOURCE_C_SHIITAKE",
    "RESOURCE_C_SOYBEAN",
    "RESOURCE_C_SUNFLOWER",
    "RESOURCE_C_TARO",
    "RESOURCE_C_TURMERIC",
    "RESOURCE_C_TURNIP",
    "RESOURCE_C_WATERLILY",
    "RESOURCE_C_WATERMALON",
    "RESOURCE_C_WATERSHIELD",
    "RESOURCE_C_WILD_RICE",
    "RESOURCE_C_WUTONG",
    "RESOURCE_C_YAM",
    "RESOURCE_C_ZEBU",
}


def load_core_registration_sql() -> str:
    sql_text = CORE_SQL_PATH.read_text(encoding="utf-8")
    marker = "-- 第 6 步："
    marker_index = sql_text.find(marker)
    assert marker_index != -1, "未找到核心资源注册 SQL 的结束位置"
    return sql_text[:marker_index]


def build_minimal_schema(connection: sqlite3.Connection) -> None:
    connection.executescript(
        """
        CREATE TABLE Resources(
            ResourceType TEXT PRIMARY KEY,
            Name TEXT,
            ResourceClassType TEXT,
            Frequency INTEGER NOT NULL DEFAULT 0,
            SeaFrequency INTEGER NOT NULL DEFAULT 0,
            PrereqTech TEXT,
            PrereqCivic TEXT
        );
        CREATE TABLE Resource_ValidTerrains(ResourceType TEXT, TerrainType TEXT);
        CREATE TABLE Resource_ValidFeatures(ResourceType TEXT, FeatureType TEXT);
        CREATE TABLE Feature_ValidTerrains(FeatureType TEXT, TerrainType TEXT);
        CREATE TABLE Features(
            FeatureType TEXT PRIMARY KEY,
            Name TEXT,
            NaturalWonder INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE Types(Type TEXT PRIMARY KEY, Kind TEXT);
        CREATE TABLE Improvements(
            ImprovementType TEXT PRIMARY KEY,
            Name TEXT,
            Description TEXT,
            Icon TEXT,
            PlunderType TEXT,
            Buildable INTEGER,
            Workable INTEGER,
            Domain TEXT
        );
        CREATE TABLE Improvements_XP2(
            ImprovementType TEXT PRIMARY KEY,
            DisasterResistant INTEGER
        );
        CREATE TABLE Improvement_ValidTerrains(
            ImprovementType TEXT,
            TerrainType TEXT
        );
        CREATE TABLE Improvement_ValidFeatures(
            ImprovementType TEXT,
            FeatureType TEXT
        );
        CREATE TABLE Improvement_ValidBuildUnits(
            ImprovementType TEXT,
            UnitType TEXT
        );
        CREATE TABLE Requirements(
            RequirementId TEXT PRIMARY KEY,
            RequirementType TEXT
        );
        CREATE TABLE RequirementArguments(
            RequirementId TEXT,
            Name TEXT,
            Value TEXT,
            PRIMARY KEY (RequirementId, Name)
        );
        CREATE TABLE RequirementSets(
            RequirementSetId TEXT PRIMARY KEY,
            RequirementSetType TEXT
        );
        CREATE TABLE RequirementSetRequirements(
            RequirementSetId TEXT,
            RequirementId TEXT,
            PRIMARY KEY (RequirementSetId, RequirementId)
        );
        """
    )


def seed_core_data(connection: sqlite3.Connection) -> None:
    connection.executemany(
        "INSERT INTO Resources(ResourceType, Name, ResourceClassType, Frequency) VALUES (?, ?, ?, ?)",
        [
            ("RESOURCE_WHEAT", "LOC_RESOURCE_WHEAT_NAME", "RESOURCECLASS_BONUS", 2),
        ],
    )
    connection.executemany(
        "INSERT INTO Resource_ValidTerrains VALUES (?, ?)",
        [("RESOURCE_WHEAT", "TERRAIN_PLAINS")],
    )
    connection.executemany(
        "INSERT INTO Features(FeatureType, Name, NaturalWonder) VALUES (?, ?, ?)",
        [
            ("FEATURE_FOREST", "LOC_FEATURE_FOREST_NAME", 0),
            ("FEATURE_JUNGLE", "LOC_FEATURE_JUNGLE_NAME", 0),
            ("FEATURE_FLOODPLAINS_GRASSLAND", "LOC_FEATURE_FLOODPLAINS_NAME", 0),
        ],
    )
    connection.executemany(
        "INSERT INTO Feature_ValidTerrains VALUES (?, ?)",
        [
            ("FEATURE_FOREST", "TERRAIN_GRASS"),
            ("FEATURE_JUNGLE", "TERRAIN_GRASS"),
            ("FEATURE_FLOODPLAINS_GRASSLAND", "TERRAIN_GRASS"),
        ],
    )


def seed_target_resources(connection: sqlite3.Connection) -> None:
    target_base_path = TARGET_MOD_ROOT / "Base.sql"
    if target_base_path.exists():
        target_base_sql = target_base_path.read_text(encoding="utf-8")
        declared_resource_types = set(
            re.findall(
                r"\('(RESOURCE_C_[A-Z0-9_]+)',\s*'LOC_RESOURCE_C_[A-Z0-9_]+_NAME',\s*'RESOURCECLASS_",
                target_base_sql,
            )
        )
        assert declared_resource_types == TARGET_RESOURCE_TYPES, (
            "目标资源扩展模组的资源清单发生变化，请同步回归测试样本"
        )

    resource_rows = [
        (
            resource_type,
            f"LOC_{resource_type}_NAME",
            "RESOURCECLASS_BONUS"
            if resource_type == "RESOURCE_C_BENTONITE"
            else "RESOURCECLASS_LUXURY",
            2,
        )
        for resource_type in sorted(TARGET_RESOURCE_TYPES)
    ]

    connection.executemany(
        "INSERT INTO Resources(ResourceType, Name, ResourceClassType, Frequency) VALUES (?, ?, ?, ?)",
        resource_rows,
    )
    connection.executemany(
        "INSERT INTO Resource_ValidTerrains VALUES (?, ?)",
        [
            ("RESOURCE_C_BENTONITE", "TERRAIN_GRASS"),
            ("RESOURCE_C_BENTONITE", "TERRAIN_GRASS_HILLS"),
        ],
    )
    connection.execute(
        "INSERT INTO Resource_ValidFeatures VALUES (?, ?)",
        ("RESOURCE_C_PINEAPPLE", "FEATURE_JUNGLE"),
    )


def test_should_register_resources_added_after_core_sql() -> None:
    connection = sqlite3.connect(":memory:")
    build_minimal_schema(connection)
    seed_core_data(connection)
    connection.executescript(load_core_registration_sql())

    seed_target_resources(connection)
    connection.executescript(COMPATIBILITY_SQL_PATH.read_text(encoding="utf-8"))

    rows = connection.execute(
        """
        SELECT ResourceName, Domain
        FROM BPBuildableResources
        WHERE ResourceName LIKE 'C_%'
        ORDER BY ResourceName
        """
    ).fetchall()
    assert {resource_name for resource_name, _ in rows} == {
        resource_type.removeprefix("RESOURCE_")
        for resource_type in TARGET_RESOURCE_TYPES
    }
    assert len(rows) == len(TARGET_RESOURCE_TYPES)
    assert dict(rows)["C_BENTONITE"] == "DOMAIN_LAND"
    assert dict(rows)["C_PINEAPPLE"] == "DOMAIN_LAND"

    improvements = connection.execute(
        """
        SELECT ImprovementType, Domain
        FROM Improvements
        WHERE ImprovementType LIKE 'IMPROVEMENT_BP_C_%'
        ORDER BY ImprovementType
        """
    ).fetchall()
    assert {
        improvement_type.removeprefix("IMPROVEMENT_BP_")
        for improvement_type, _ in improvements
    } == {
        resource_type.removeprefix("RESOURCE_")
        for resource_type in TARGET_RESOURCE_TYPES
    }
    assert len(improvements) == len(TARGET_RESOURCE_TYPES)


def test_should_preserve_target_native_placement_tables_for_rule_toggle() -> None:
    connection = sqlite3.connect(":memory:")
    build_minimal_schema(connection)
    seed_core_data(connection)
    connection.executescript(load_core_registration_sql())

    seed_target_resources(connection)
    connection.executescript(COMPATIBILITY_SQL_PATH.read_text(encoding="utf-8"))

    bentonite_terrains = {
        row[0]
        for row in connection.execute(
            """
            SELECT TerrainType
            FROM Resource_ValidTerrains
            WHERE ResourceType = 'RESOURCE_C_BENTONITE'
            """
        )
    }
    pineapple_features = {
        row[0]
        for row in connection.execute(
            """
            SELECT FeatureType
            FROM Resource_ValidFeatures
            WHERE ResourceType = 'RESOURCE_C_PINEAPPLE'
            """
        )
    }
    assert bentonite_terrains == {"TERRAIN_GRASS", "TERRAIN_GRASS_HILLS"}
    assert pineapple_features == {"FEATURE_JUNGLE"}

    launcher_source = (
        REPO_ROOT / "UI" / "Additions" / "BPResourceLauncher.lua"
    ).read_text(encoding="utf-8")
    gameplay_source = (REPO_ROOT / "BP_ResourcePlanter.lua").read_text(encoding="utf-8")
    assert "GameInfo.Resource_ValidTerrains()" in launcher_source
    assert "GameInfo.Resource_ValidFeatures()" in launcher_source
    assert "ResourceBuilder.CanHaveResource(plot, resourceInfo.Hash)" in gameplay_source


if __name__ == "__main__":
    test_should_register_resources_added_after_core_sql()
    test_should_preserve_target_native_placement_tables_for_rule_toggle()
    print("late resource compatibility tests passed")
