-- ===========================================================================
-- Builder Plants Resources  -  UnitPanel 包装
--
-- 优先兼容 Team PVP Tools 的 UnitPanel_TPT.lua；如果不存在，再依次回退到
-- Expansion2 / Expansion1 / Base Game 的 UnitPanel。
-- ===========================================================================

local files = {
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
