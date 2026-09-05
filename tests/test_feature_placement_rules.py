"""Run with: python -m pip install -r tests/requirements.txt; python -m pytest tests."""
from pathlib import Path
import re

import pytest
from lupa.lua54 import LuaRuntime


ROOT = Path(__file__).resolve().parents[1]
FOREST, JUNGLE = 0, 1
STONE, DEER, BANANAS, MODDED = 0, 1, 2, 3


@pytest.fixture
def runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute((ROOT / "tests/fixtures/planting_runtime.lua").read_text(encoding="utf-8"))
    lua.execute((ROOT / "BP_ResourcePlanter.lua").read_text(encoding="utf-8"))
    lua.globals().Events.LoadGameViewStateDone()
    # Civ VI's UI dialect adds annotations; strip only its primitive type hints.
    ui_source = (ROOT / "UI/Additions/BPResourceLauncher.lua").read_text(encoding="utf-8")
    ui_source = re.sub(r":(?:table|string|number|boolean)\b", "", ui_source)
    collect = lua.execute(ui_source + "\nreturn BPCollectPlantableEntries")
    return lua, collect


def features(runtime):
    lua, collect = runtime
    return {
        entry.TargetIndex
        for entry in collect(lua.globals().Unit).values()
        if entry.TargetKind == "FEATURE"
    }


def plant(runtime, target, kind="FEATURE"):
    lua, _ = runtime
    lua.globals().GameEvents.BPPlantTarget(0, lua.table_from({
        "UnitID": 0, "X": 0, "Y": 0, "TargetKind": kind, "TargetIndex": target,
    }))


@pytest.mark.parametrize("rules", [True, 1])
def test_ui_rechecks_features_after_planting_stone(runtime, rules):
    state = runtime[0].globals().State
    state.rules = rules
    assert FOREST in features(runtime)
    plant(runtime, STONE, "RESOURCE")
    assert state.resource == STONE
    state.moves = 2  # Next turn, on the same tile and with the UI cache already built.
    assert FOREST not in features(runtime)


@pytest.mark.parametrize("target,terrain", [(FOREST, 0), (JUNGLE, 2)])
def test_gameplay_rejects_feature_request_on_stone_without_spending_charge(runtime, target, terrain):
    state = runtime[0].globals().State
    state.resource, state.terrain = STONE, terrain
    plant(runtime, target)  # Bypass the menu, as with a stale selection.
    assert state.feature == -1
    assert state.featureWrites == 0
    assert state.resource == STONE
    assert state.charges == 3
    assert state.moves == 2


@pytest.mark.parametrize("rules", [False, 0, None])
@pytest.mark.parametrize("target,terrain", [(FOREST, 0), (JUNGLE, 2)])
def test_disabled_rules_preserve_unrestricted_coexistence(runtime, rules, target, terrain):
    state = runtime[0].globals().State
    state.rules, state.resource, state.terrain = rules, STONE, terrain
    assert target in features(runtime)
    plant(runtime, target)
    assert state.feature == target
    assert state.resource == STONE
    assert state.charges == 2


@pytest.mark.parametrize("resource,target,terrain", [
    (-1, FOREST, 0), (-1, JUNGLE, 2), (DEER, FOREST, 0),
    (BANANAS, JUNGLE, 2), (MODDED, FOREST, 0),
])
def test_rules_allow_empty_tiles_and_compatible_resources(runtime, resource, target, terrain):
    state = runtime[0].globals().State
    state.resource, state.terrain = resource, terrain
    assert target in features(runtime)
    plant(runtime, target)
    assert state.feature == target
    assert state.resource == resource
    assert state.charges == 2


@pytest.mark.parametrize("resource,target", [(DEER, JUNGLE), (BANANAS, FOREST), (999, FOREST)])
def test_rules_reject_resource_incompatible_with_target_feature(runtime, resource, target):
    state = runtime[0].globals().State
    state.resource, state.terrain = resource, 2
    assert target not in features(runtime)
    plant(runtime, target)
    assert state.feature == -1
    assert state.charges == 3


@pytest.mark.parametrize("terrain,existing_feature", [(1, -1), (0, JUNGLE)])
def test_terrain_and_existing_feature_restrictions_still_apply(runtime, terrain, existing_feature):
    state = runtime[0].globals().State
    state.terrain, state.feature = terrain, existing_feature
    assert FOREST not in features(runtime)
    plant(runtime, FOREST)
    assert state.feature == existing_feature
    assert state.charges == 3


@pytest.mark.parametrize("resource,expected_feature", [(STONE, -1), (DEER, FOREST)])
def test_legacy_conversion_checks_resource_compatibility(runtime, resource, expected_feature):
    lua, _ = runtime
    state = lua.globals().State
    state.resource, state.improvement = resource, 10
    lua.globals().Events.ImprovementAddedToMap(0, 0, 10, 0)
    assert state.feature == expected_feature
    assert state.resource == resource
    assert state.improvement == -1
