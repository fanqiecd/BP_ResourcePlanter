$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$config = [xml](Get-Content -Raw -LiteralPath (Join-Path $root 'BP_ResourcePlanter_Config.xml'))
$modinfo = [xml](Get-Content -Raw -LiteralPath (Join-Path $root 'BP_ResourcePlanter.modinfo'))
$gameplay = Get-Content -Raw -LiteralPath (Join-Path $root 'BP_ResourcePlanter.lua')
$launcher = Get-Content -Raw -LiteralPath (Join-Path $root 'UI/Additions/BPResourceLauncher.lua')
$text = Get-Content -Raw -LiteralPath (Join-Path $root 'BP_ResourcePlanter_Text.sql')

$parameter = $config.GameInfo.Parameters.Row |
    Where-Object ParameterId -eq 'BP_USE_VANILLA_RESOURCE_RULES'

if ($null -eq $parameter -or $parameter.Domain -ne 'bool' -or $parameter.DefaultValue -ne '0') {
    throw 'The vanilla resource rule toggle must exist as a bool and default to off.'
}
if ($modinfo.Mod.FrontEndActions.UpdateDatabase.File -notcontains 'BP_ResourcePlanter_Config.xml') {
    throw 'The frontend configuration file is not registered in modinfo.'
}
if ($gameplay -notmatch 'ResourceBuilder\.CanHaveResource\(plot, resourceInfo\.Hash\)') {
    throw 'Gameplay is missing the native vanilla resource placement guard.'
}
if ($launcher -notmatch 'GameInfo\.Resource_ValidTerrains' -or
    $launcher -notmatch 'GameInfo\.Resource_ValidFeatures') {
    throw 'The chooser is missing vanilla resource table filtering.'
}
if ($text -notmatch 'LOC_BP_USE_VANILLA_RESOURCE_RULES_NAME') {
    throw 'The toggle localization is missing.'
}

Write-Host 'Resource rule toggle validation passed.'
