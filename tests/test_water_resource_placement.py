"""Water placement checks against the real Lua scripts with mocked Civ VI APIs.

These tests cover mod logic, not the game's native resource builder or UI rendering.
"""
from pathlib import Path
import re
import sqlite3

import pytest
from lupa.lua54 import LuaRuntime

from test_late_resource_compatibility import (
    build_minimal_schema,
    load_core_registration_sql,
    seed_core_data,
)


ROOT = Path(__file__).resolve().parents[1]
FISH, PEARLS, WHALES, CRABS = 4, 5, 6, 7
COAST, OCEAN = 3, 4

WATER_SETUP = """
local resourceRows, buildableRows, terrainRows = {}, {}, {}
for resource in GameInfo.Resources() do table.insert(resourceRows, resource) end
for row in GameInfo.BPBuildableResources() do table.insert(buildableRows, row) end
for row in GameInfo.Resource_ValidTerrains() do table.insert(terrainRows, row) end
for offset, name in ipairs({'FISH', 'PEARLS', 'WHALES', 'CRABS'}) do
    table.insert(resourceRows, {
        Index = offset + 3, Hash = offset + 103,
        ResourceType = 'RESOURCE_' .. name, Name = name,
        ResourceClassType = (name == 'FISH' or name == 'CRABS')
            and 'RESOURCECLASS_BONUS' or 'RESOURCECLASS_LUXURY'
    })
    table.insert(buildableRows, {ResourceName = name, Domain = 'DOMAIN_SEA'})
    -- Base-game Resources.xml permits these four resources on COAST only.
    table.insert(terrainRows, {ResourceType = 'RESOURCE_' .. name, TerrainType = 'TERRAIN_COAST'})
end
GameInfo.Resources = rows(resourceRows, 'ResourceType')
GameInfo.BPBuildableResources = rows(buildableRows)
GameInfo.Resource_ValidTerrains = rows(terrainRows)
GameInfo.Terrains = rows({
    {Index = 0, TerrainType = 'TERRAIN_GRASS'},
    {Index = 3, TerrainType = 'TERRAIN_COAST'},
    {Index = 4, TerrainType = 'TERRAIN_OCEAN'}
}, 'TerrainType')
State.terrain, State.owner, State.district = 3, 0, -1
State.nativeAllows, State.nativeCalls = true, 0
Plot.IsWater = function() return State.terrain == 3 or State.terrain == 4 end
Plot.GetOwner = function() return State.owner end
Plot.GetDistrictType = function() return State.district end
Unit.IsEmbarked = function() return Plot:IsWater() end
ResourceBuilder.CanHaveResource = function(_, hash)
    State.nativeCalls = State.nativeCalls + 1
    State.nativeHash = hash
    return State.nativeAllows
end
"""


@pytest.fixture
def water_runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
    # Append in the same chunk to reuse the fixture's local GameInfo row adapter.
    lua.execute((ROOT / "tests/fixtures/planting_runtime.lua").read_text(encoding="utf-8") + WATER_SETUP)
    lua.execute((ROOT / "BP_ResourcePlanter.lua").read_text(encoding="utf-8"))
    lua.globals().Events.LoadGameViewStateDone()
    source = (ROOT / "UI/Additions/BPResourceLauncher.lua").read_text(encoding="utf-8")
    source = re.sub(r":(?:table|string|number|boolean)\b", "", source)
    collect = lua.execute(source + "\nreturn BPCollectPlantableEntries")
    return lua, collect


def available(runtime):
    lua, collect = runtime
    return {entry.TargetIndex for entry in collect(lua.globals().Unit).values()}


def plant(runtime, target):
    lua, _ = runtime
    lua.globals().GameEvents.BPPlantTarget(0, lua.table_from({
        "UnitID": 0, "X": 0, "Y": 0, "TargetKind": "RESOURCE", "TargetIndex": target,
    }))


@pytest.mark.parametrize("target", [FISH, PEARLS, WHALES, CRABS])
@pytest.mark.parametrize("rules,terrain", [(False, COAST), (False, OCEAN), (True, COAST)])
def test_water_resources_are_offered_and_placed_when_allowed(water_runtime, target, rules, terrain):
    state = water_runtime[0].globals().State
    state.rules, state.terrain = rules, terrain
    assert target in available(water_runtime)
    plant(water_runtime, target)
    assert state.resource == target
    assert state.charges == 2
    assert state.moves == 0
    assert state.nativeCalls == int(rules)


def test_vanilla_rules_hide_all_four_resources_on_open_ocean(water_runtime):
    state = water_runtime[0].globals().State
    state.rules, state.terrain = True, OCEAN
    assert available(water_runtime) == set()


@pytest.mark.parametrize("field,value", [
    ("moves", 0), ("charges", 0), ("resource", 99), ("improvement", 5),
    ("district", 1), ("owner", 1),
])
def test_invalid_water_state_blocks_menu_and_direct_request(water_runtime, field, value):
    state = water_runtime[0].globals().State
    state[field] = value
    original_resource, original_charges = state.resource, state.charges
    assert available(water_runtime) == set()
    plant(water_runtime, FISH)
    assert state.resource == original_resource
    assert state.charges == original_charges


def test_exhausted_moves_recover_on_the_next_turn(water_runtime):
    state = water_runtime[0].globals().State
    state.moves = 0
    assert available(water_runtime) == set()
    state.moves = 2
    assert available(water_runtime) == {FISH, PEARLS, WHALES, CRABS}


def test_land_resource_is_not_offered_or_placed_on_water_even_with_rules_off(water_runtime):
    state = water_runtime[0].globals().State
    state.rules = False
    assert 0 not in available(water_runtime)  # STONE
    plant(water_runtime, 0)
    assert state.resource == -1
    assert state.charges == 3


def test_native_rejection_after_menu_selection_preserves_charge(water_runtime):
    state = water_runtime[0].globals().State
    assert FISH in available(water_runtime)
    # Native checks are stricter than the UI table lookup. Simulate a rejection,
    # without claiming which game-engine conditions cause it.
    state.nativeAllows = False
    plant(water_runtime, FISH)
    assert state.nativeCalls == 1
    assert state.nativeHash == 104
    assert state.resource == -1
    assert state.charges == 3
    assert state.moves == 2


def test_core_and_compatibility_sql_register_native_water_resources():
    with sqlite3.connect(":memory:") as connection:
        build_minimal_schema(connection)
        seed_core_data(connection)
        samples = [("FISH", "BONUS", 23), ("CRABS", "BONUS", 17),
                   ("PEARLS", "LUXURY", 1), ("WHALES", "LUXURY", 1)]
        for name, category, frequency in samples:
            connection.execute(
                "INSERT INTO Resources(ResourceType, Name, ResourceClassType, SeaFrequency) VALUES (?, ?, ?, ?)",
                ("RESOURCE_" + name, name, "RESOURCECLASS_" + category, frequency),
            )
            connection.execute("INSERT INTO Resource_ValidTerrains VALUES (?, 'TERRAIN_COAST')",
                               ("RESOURCE_" + name,))
        for sql in (load_core_registration_sql(),
                    (ROOT / "BP_ResourcePlanter_Compatibility.sql").read_text(encoding="utf-8")):
            connection.executescript(sql)
            actual = dict(connection.execute(
                "SELECT ResourceName, Domain FROM BPBuildableResources WHERE ResourceName IN ('FISH','CRABS','PEARLS','WHALES')"
            ))
            assert actual == {name: "DOMAIN_SEA" for name, _, _ in samples}
