from __future__ import annotations

import sqlite3
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SQL_PATH = REPO_ROOT / "BP_ResourcePlanter.sql"
STEP_MARKER = "-- 第 6 步："


def load_visible_resource_patch() -> str:
    sql_text = SQL_PATH.read_text(encoding="utf-8")
    marker_index = sql_text.find(STEP_MARKER)
    assert marker_index != -1, "未找到第 6 步 SQL 段落"
    return sql_text[marker_index:]


def build_minimal_schema(connection: sqlite3.Connection) -> None:
    connection.executescript(
        """
        CREATE TABLE Requirements (
            RequirementId TEXT PRIMARY KEY,
            RequirementType TEXT,
            Inverse INTEGER DEFAULT 0,
            Reverse INTEGER DEFAULT 0,
            Persistent INTEGER DEFAULT 0,
            ProgressWeight INTEGER DEFAULT 1,
            Triggered INTEGER DEFAULT 0
        );

        CREATE TABLE RequirementSets (
            RequirementSetId TEXT PRIMARY KEY,
            RequirementSetType TEXT
        );

        CREATE TABLE RequirementArguments (
            RequirementId TEXT,
            Name TEXT,
            Value TEXT,
            Type TEXT NOT NULL DEFAULT 'ARGTYPE_IDENTITY',
            Extra TEXT,
            SecondExtra TEXT,
            PRIMARY KEY (RequirementId, Name)
        );

        CREATE TABLE RequirementSetRequirements (
            RequirementSetId TEXT,
            RequirementId TEXT,
            PRIMARY KEY (RequirementSetId, RequirementId)
        );

        CREATE TABLE Modifiers (
            ModifierId TEXT PRIMARY KEY,
            SubjectRequirementSetId TEXT
        );
        """
    )


def seed_visible_resource_requirements(connection: sqlite3.Connection) -> None:
    connection.executescript(
        """
        INSERT INTO Requirements (RequirementId, RequirementType) VALUES
            ('REQUIRES_PLOT_HAS_VISIBLE_RESOURCE', 'REQUIREMENT_PLOT_RESOURCE_VISIBLE'),
            ('MOD_LEADER_VISIBLE_RESOURCE_REQ', 'REQUIREMENT_PLOT_RESOURCE_VISIBLE'),
            ('REQUIRES_PLOT_HAS_STRATEGIC', 'REQUIREMENT_PLOT_RESOURCE_CLASS_TYPE_MATCHES'),
            ('OTHER_REQ', 'REQUIREMENT_OTHER');

        INSERT INTO RequirementSets (RequirementSetId, RequirementSetType) VALUES
            ('PLOT_HAS_STRATEGIC_RESOURCE_ENGLAND', 'REQUIREMENTSET_TEST_ALL'),
            ('MOD_LEADER_SET', 'REQUIREMENTSET_TEST_ALL');

        INSERT INTO Modifiers (ModifierId, SubjectRequirementSetId) VALUES
            ('VICTORIA_STRATEGIC_RESOURCE', 'PLOT_HAS_STRATEGIC_RESOURCE_ENGLAND');

        INSERT INTO RequirementSetRequirements (RequirementSetId, RequirementId) VALUES
            ('PLOT_HAS_STRATEGIC_RESOURCE_ENGLAND', 'REQUIRES_PLOT_HAS_VISIBLE_RESOURCE'),
            ('PLOT_HAS_STRATEGIC_RESOURCE_ENGLAND', 'REQUIRES_PLOT_HAS_STRATEGIC'),
            ('MOD_LEADER_SET', 'MOD_LEADER_VISIBLE_RESOURCE_REQ'),
            ('MOD_LEADER_SET', 'OTHER_REQ');

        INSERT INTO RequirementArguments (RequirementId, Name, Value) VALUES
            ('REQUIRES_PLOT_HAS_STRATEGIC', 'ResourceClassType', 'RESOURCECLASS_STRATEGIC');
        """
    )


def fetch_rows(connection: sqlite3.Connection, query: str) -> list[tuple[str, ...]]:
    return connection.execute(query).fetchall()


def main() -> None:
    connection = sqlite3.connect(":memory:")
    build_minimal_schema(connection)
    seed_visible_resource_requirements(connection)
    connection.executescript(load_visible_resource_patch())

    wrapped_edges = set(
        fetch_rows(
            connection,
            """
            SELECT RequirementSetId, RequirementId
            FROM RequirementSetRequirements
            ORDER BY RequirementSetId, RequirementId
            """,
        )
    )
    assert (
        "PLOT_HAS_STRATEGIC_RESOURCE_ENGLAND",
        "BP_VISIBLE_RESOURCE_WRAPPER_REQ_REQUIRES_PLOT_HAS_VISIBLE_RESOURCE",
    ) in wrapped_edges
    assert (
        "MOD_LEADER_SET",
        "BP_VISIBLE_RESOURCE_WRAPPER_REQ_MOD_LEADER_VISIBLE_RESOURCE_REQ",
    ) in wrapped_edges
    assert (
        "PLOT_HAS_STRATEGIC_RESOURCE_ENGLAND",
        "BP_RESOURCE_CLASS_WRAPPER_REQ_REQUIRES_PLOT_HAS_STRATEGIC",
    ) in wrapped_edges

    wrapper_members = set(
        fetch_rows(
            connection,
            """
            SELECT RequirementSetId, RequirementId
            FROM RequirementSetRequirements
            WHERE RequirementSetId LIKE 'BP_VISIBLE_RESOURCE_WRAPPER_SET_%'
            ORDER BY RequirementSetId, RequirementId
            """,
        )
    )
    assert (
        "BP_VISIBLE_RESOURCE_WRAPPER_SET_REQUIRES_PLOT_HAS_VISIBLE_RESOURCE",
        "BP_VISIBLE_RESOURCE_ORIGINAL_REQ_REQUIRES_PLOT_HAS_VISIBLE_RESOURCE",
    ) in wrapper_members
    assert (
        "BP_VISIBLE_RESOURCE_WRAPPER_SET_REQUIRES_PLOT_HAS_VISIBLE_RESOURCE",
        "BP_REQUIRES_PLOT_SYNCED_VISIBLE_RESOURCE_PROPERTY",
    ) in wrapper_members
    assert (
        "BP_VISIBLE_RESOURCE_WRAPPER_SET_MOD_LEADER_VISIBLE_RESOURCE_REQ",
        "BP_VISIBLE_RESOURCE_ORIGINAL_REQ_MOD_LEADER_VISIBLE_RESOURCE_REQ",
    ) in wrapper_members
    assert (
        "BP_VISIBLE_RESOURCE_WRAPPER_SET_MOD_LEADER_VISIBLE_RESOURCE_REQ",
        "BP_REQUIRES_PLOT_SYNCED_VISIBLE_RESOURCE_PROPERTY",
    ) in wrapper_members

    class_wrapper_members = set(
        fetch_rows(
            connection,
            """
            SELECT RequirementSetId, RequirementId
            FROM RequirementSetRequirements
            WHERE RequirementSetId LIKE 'BP_RESOURCE_CLASS_WRAPPER_SET_%'
            ORDER BY RequirementSetId, RequirementId
            """,
        )
    )
    assert (
        "BP_RESOURCE_CLASS_WRAPPER_SET_REQUIRES_PLOT_HAS_STRATEGIC",
        "BP_RESOURCE_CLASS_ORIGINAL_REQ_REQUIRES_PLOT_HAS_STRATEGIC",
    ) in class_wrapper_members
    assert (
        "BP_RESOURCE_CLASS_WRAPPER_SET_REQUIRES_PLOT_HAS_STRATEGIC",
        "BP_RESOURCE_CLASS_PROPERTY_REQ_REQUIRES_PLOT_HAS_STRATEGIC",
    ) in class_wrapper_members

    property_arguments = set(
        fetch_rows(
            connection,
            """
            SELECT RequirementId, Name, Value
            FROM RequirementArguments
            WHERE RequirementId = 'BP_REQUIRES_PLOT_SYNCED_VISIBLE_RESOURCE_PROPERTY'
            ORDER BY Name
            """,
        )
    )
    assert (
        "BP_REQUIRES_PLOT_SYNCED_VISIBLE_RESOURCE_PROPERTY",
        "PropertyName",
        "BP_VisibleResourceForYieldBonuses",
    ) in property_arguments
    assert (
        "BP_REQUIRES_PLOT_SYNCED_VISIBLE_RESOURCE_PROPERTY",
        "PropertyMinimum",
        "1",
    ) in property_arguments

    class_property_arguments = set(
        fetch_rows(
            connection,
            """
            SELECT RequirementId, Name, Value
            FROM RequirementArguments
            WHERE RequirementId = 'BP_RESOURCE_CLASS_PROPERTY_REQ_REQUIRES_PLOT_HAS_STRATEGIC'
            ORDER BY Name
            """,
        )
    )
    assert (
        "BP_RESOURCE_CLASS_PROPERTY_REQ_REQUIRES_PLOT_HAS_STRATEGIC",
        "PropertyName",
        "BP_HasStrategicResourceForYieldBonuses",
    ) in class_property_arguments
    assert (
        "BP_RESOURCE_CLASS_PROPERTY_REQ_REQUIRES_PLOT_HAS_STRATEGIC",
        "PropertyMinimum",
        "1",
    ) in class_property_arguments

    print("visible resource wrapper SQL self-check passed")


if __name__ == "__main__":
    main()
