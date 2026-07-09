-- ===========================================================================
-- Builder Plants Resources  -  UnitPanel 包装
--
-- 优先叠加已启用的大型 UnitPanel 替换（目前已知需要兼容和而不同的
-- DL_UnitPanel.lua）；如果不存在，再依次回退到 Team PVP Tools / Expansion2 /
-- Expansion1 / Base Game 的 UnitPanel。
-- ===========================================================================

local files = {
    "DL_UnitPanel.lua",
    "UnitPanel_TPT.lua",
    "UnitPanel_Expansion2.lua",
    "UnitPanel_Expansion1.lua",
    "UnitPanel.lua",
}

for _, file in ipairs(files) do
    include(file)
    if Initialize then
        print("[BP_ResourcePlanter] Loaded " .. file .. " as UnitPanel base file.")
        break
    end
end

include("BP_ResourcePlantUnitPanel_Shared");
