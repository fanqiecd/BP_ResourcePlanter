from __future__ import annotations

import sqlite3
import xml.etree.ElementTree as ET
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SQL_PATH = REPO_ROOT / "BP_ResourcePlanter.sql"
BASE_DATA_DIR = Path(
    r"D:\Program Files (x86)\Steam\steamapps\common\Sid Meier's Civilization VI\Base\Assets\Gameplay\Data"
)
TARGET_FEATURES = {
    "FEATURE_FOREST": {
        "icon": "ICON_UNITOPERATION_PLANT_FOREST",
        "tech": None,
        "civic": None,
        "improvement": "IMPROVEMENT_BP_FEATURE_FOREST",
    },
    "FEATURE_JUNGLE": {
        "icon": "ICON_UNITOPERATION_PLANT_FOREST",
        "tech": None,
        "civic": None,
        "improvement": "IMPROVEMENT_BP_FEATURE_JUNGLE",
    },
}


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
        CREATE TABLE Features(
            FeatureType TEXT PRIMARY KEY,
            Name TEXT,
            NaturalWonder INTEGER NOT NULL DEFAULT 0,
            AddCivic TEXT,
            RemoveTech TEXT,
            Forest INTEGER NOT NULL DEFAULT 0
        );

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


def seed_base_data(connection: sqlite3.Connection) -> None:
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
                "INSERT INTO Features VALUES (?,?,?,?,?,?)",
                (
                    feature_type,
                    values.get("Name"),
                    to_int_bool(values.get("NaturalWonder")),
                    values.get("AddCivic"),
                    values.get("RemoveTech"),
                    to_int_bool(values.get("Forest")),
                ),
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
    seed_base_data(connection)
    connection.executescript(load_sql_setup())

    rows = connection.execute(
        """
        SELECT FeatureType, Icon, PrereqTech, PrereqCivic
        FROM BPBuildableFeatures
        ORDER BY FeatureType
        """
    ).fetchall()
    assert len(rows) == 2, f"BPBuildableFeatures 应仅包含森林/雨林，实际为: {rows}"

    for feature_type, icon, prereq_tech, prereq_civic in rows:
        expected = TARGET_FEATURES[feature_type]
        assert icon == expected["icon"], f"{feature_type} 图标错误: {icon}"
        assert prereq_tech == expected["tech"], f"{feature_type} 科技前置错误: {prereq_tech}"
        assert prereq_civic == expected["civic"], f"{feature_type} 市政前置错误: {prereq_civic}"

    for feature_type, expected in TARGET_FEATURES.items():
        improvement_type = expected["improvement"]
        improvement_row = connection.execute(
            """
            SELECT Icon, Domain
            FROM Improvements
            WHERE ImprovementType = ?
            """,
            (improvement_type,),
        ).fetchone()
        assert improvement_row is not None, f"缺少地貌占位改良: {improvement_type}"
        assert improvement_row[0] == expected["icon"], f"{improvement_type} 图标错误: {improvement_row[0]}"
        assert improvement_row[1] == "DOMAIN_LAND", f"{improvement_type} 应为陆地改良: {improvement_row[1]}"

        terrains = fetch_set(
            connection,
            """
            SELECT TerrainType
            FROM Improvement_ValidTerrains
            WHERE ImprovementType = ?
            """,
            (improvement_type,),
        )
        expected_terrains = fetch_set(
            connection,
            """
            SELECT TerrainType
            FROM Feature_ValidTerrains
            WHERE FeatureType = ?
            """,
            (feature_type,),
        )
        assert terrains == expected_terrains, (
            f"{improvement_type} 合法地形应与 {feature_type} 一致: {terrains} != {expected_terrains}"
        )

        build_units = fetch_set(
            connection,
            """
            SELECT UnitType
            FROM Improvement_ValidBuildUnits
            WHERE ImprovementType = ?
            """,
            (improvement_type,),
        )
        assert build_units == {"UNIT_BUILDER"}, f"{improvement_type} 应仅允许建造者建造: {build_units}"

    print("buildable feature self-check passed")


if __name__ == "__main__":
    main()
