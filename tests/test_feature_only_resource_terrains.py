from __future__ import annotations

import sqlite3
import xml.etree.ElementTree as ET
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SQL_PATH = REPO_ROOT / "BP_ResourcePlanter.sql"
BASE_DATA_DIR = Path(
    r"D:\Program Files (x86)\Steam\steamapps\common\Sid Meier's Civilization VI\Base\Assets\Gameplay\Data"
)
FEATURE_ONLY_LAND_RESOURCES = (
    "BANANAS",
    "COCOA",
    "DYES",
    "SILK",
    "SPICES",
    "SUGAR",
    "TRUFFLES",
)
SEA_TERRAINS = {"TERRAIN_COAST", "TERRAIN_OCEAN"}


def load_sql_setup() -> str:
    sql_text = SQL_PATH.read_text(encoding="utf-8")
    marker_index = sql_text.find("-- 第 6 步：")
    assert marker_index != -1, "未找到第 6 步 SQL 段落"
    return sql_text[:marker_index]


def parse_row_values(row: ET.Element) -> dict[str, str]:
    if row.attrib:
        return dict(row.attrib)
    return {child.tag: child.text or "" for child in row}


def to_int_bool(value: str | None) -> int:
    if value is None or value == "":
        return 0
    lowered = value.strip().lower()
    if lowered in {"true", "1"}:
        return 1
    if lowered in {"false", "0"}:
        return 0
    return int(value)


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
            PrereqCivic TEXT,
            Happiness INTEGER
        );

        CREATE TABLE Resource_ValidTerrains(ResourceType TEXT, TerrainType TEXT);
        CREATE TABLE Resource_ValidFeatures(ResourceType TEXT, FeatureType TEXT);
        CREATE TABLE Feature_ValidTerrains(FeatureType TEXT, TerrainType TEXT);
        CREATE TABLE Features(FeatureType TEXT PRIMARY KEY, NaturalWonder INTEGER NOT NULL DEFAULT 0);

        CREATE TABLE Types(Type TEXT, Kind TEXT);
        CREATE TABLE Improvements(
            ImprovementType TEXT,
            Name TEXT,
            Description TEXT,
            Icon TEXT,
            PlunderType TEXT,
            Buildable INTEGER,
            Workable INTEGER,
            Domain TEXT
        );
        CREATE TABLE Improvements_XP2(ImprovementType TEXT, DisasterResistant INTEGER);
        CREATE TABLE Improvement_ValidTerrains(ImprovementType TEXT, TerrainType TEXT);
        CREATE TABLE Improvement_ValidFeatures(ImprovementType TEXT, FeatureType TEXT);
        CREATE TABLE Improvement_ValidBuildUnits(ImprovementType TEXT, UnitType TEXT);
        """
    )


def seed_base_resource_data(connection: sqlite3.Connection) -> None:
    resources_root = ET.parse(BASE_DATA_DIR / "Resources.xml").getroot()
    for row in resources_root.findall(".//Resources/Row"):
        values = parse_row_values(row)
        resource_type = values.get("ResourceType")
        if resource_type:
            connection.execute(
                "INSERT INTO Resources VALUES (?,?,?,?,?,?,?,?)",
                (
                    resource_type,
                    values.get("Name"),
                    values.get("ResourceClassType"),
                    int(values.get("Frequency") or 0),
                    int(values.get("SeaFrequency") or 0),
                    values.get("PrereqTech"),
                    values.get("PrereqCivic"),
                    values.get("Happiness"),
                ),
            )

    for row in resources_root.findall(".//Resource_ValidTerrains/Row"):
        values = parse_row_values(row)
        if values.get("ResourceType"):
            connection.execute(
                "INSERT INTO Resource_ValidTerrains VALUES (?,?)",
                (values["ResourceType"], values["TerrainType"]),
            )

    for row in resources_root.findall(".//Resource_ValidFeatures/Row"):
        values = parse_row_values(row)
        if values.get("ResourceType"):
            connection.execute(
                "INSERT INTO Resource_ValidFeatures VALUES (?,?)",
                (values["ResourceType"], values["FeatureType"]),
            )

    features_root = ET.parse(BASE_DATA_DIR / "Features.xml").getroot()
    for row in features_root.findall(".//Features/Row"):
        values = parse_row_values(row)
        feature_type = values.get("FeatureType")
        if feature_type:
            connection.execute(
                "INSERT INTO Features VALUES (?,?)",
                (feature_type, to_int_bool(values.get("NaturalWonder"))),
            )

    for row in features_root.findall(".//Feature_ValidTerrains/Row"):
        values = parse_row_values(row)
        if values.get("FeatureType"):
            connection.execute(
                "INSERT INTO Feature_ValidTerrains VALUES (?,?)",
                (values["FeatureType"], values["TerrainType"]),
            )


def fetch_set(connection: sqlite3.Connection, query: str, params: tuple[str, ...]) -> set[str]:
    return {row[0] for row in connection.execute(query, params).fetchall()}


def main() -> None:
    connection = sqlite3.connect(":memory:")
    build_minimal_schema(connection)
    seed_base_resource_data(connection)
    connection.executescript(load_sql_setup())

    expected_land_domains = set(
        connection.execute(
            f"""
            SELECT ResourceName
            FROM BPBuildableResources
            WHERE ResourceName IN ({",".join("?" for _ in FEATURE_ONLY_LAND_RESOURCES)})
              AND Domain = 'DOMAIN_LAND'
            """,
            FEATURE_ONLY_LAND_RESOURCES,
        ).fetchall()
    )
    expected_land_domains = {row[0] for row in expected_land_domains}
    assert expected_land_domains == set(FEATURE_ONLY_LAND_RESOURCES)

    for resource_name in FEATURE_ONLY_LAND_RESOURCES:
        terrains = fetch_set(
            connection,
            """
            SELECT TerrainType
            FROM Improvement_ValidTerrains
            WHERE ImprovementType = ?
            """,
            (f"IMPROVEMENT_BP_{resource_name}",),
        )
        assert terrains, f"{resource_name} 未生成合法地形"
        assert terrains.isdisjoint(SEA_TERRAINS), f"{resource_name} 仍错误包含海洋地形: {terrains}"

    assert fetch_set(
        connection,
        """
        SELECT TerrainType
        FROM Improvement_ValidTerrains
        WHERE ImprovementType = 'IMPROVEMENT_BP_BANANAS'
        """,
        (),
    ) == {"TERRAIN_GRASS", "TERRAIN_GRASS_HILLS", "TERRAIN_PLAINS", "TERRAIN_PLAINS_HILLS"}

    assert fetch_set(
        connection,
        """
        SELECT TerrainType
        FROM Improvement_ValidTerrains
        WHERE ImprovementType = 'IMPROVEMENT_BP_COCOA'
        """,
        (),
    ) == {"TERRAIN_GRASS", "TERRAIN_GRASS_HILLS", "TERRAIN_PLAINS", "TERRAIN_PLAINS_HILLS"}

    assert fetch_set(
        connection,
        """
        SELECT TerrainType
        FROM Improvement_ValidTerrains
        WHERE ImprovementType = 'IMPROVEMENT_BP_SUGAR'
        """,
        (),
    ) == {"TERRAIN_DESERT", "TERRAIN_GRASS"}

    pearls_terrains = fetch_set(
        connection,
        """
        SELECT TerrainType
        FROM Improvement_ValidTerrains
        WHERE ImprovementType = 'IMPROVEMENT_BP_PEARLS'
        """,
        (),
    )
    assert pearls_terrains
    assert pearls_terrains.issubset(SEA_TERRAINS), f"海洋资源 PEARLS 被拖到陆地: {pearls_terrains}"

    print("feature-only resource terrain self-check passed")


if __name__ == "__main__":
    main()
