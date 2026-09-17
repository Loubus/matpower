$ErrorActionPreference = 'Stop'
$legacyRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$legacyPrefix = $legacyRoot.TrimEnd('\') + '\'
$legacyActions = [System.Collections.Generic.List[object]]::new()

function Legacy-Path([string]$relative) {
    $absolute = [IO.Path]::GetFullPath((Join-Path $legacyRoot $relative))
    if (-not $absolute.StartsWith($legacyPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path outside workspace: $absolute"
    }
    return $absolute
}

function Reverse-Archive-Link([string]$originalRelative, [string]$archiveRelative) {
    $original = Legacy-Path $originalRelative
    $archived = Legacy-Path $archiveRelative
    $originalItem = Get-Item -LiteralPath $original
    $archiveItem = Get-Item -LiteralPath $archived
    if ($originalItem.LinkType -ne 'Junction') { throw "Expected original-path junction: $original" }
    if ($archiveItem.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Expected physical archive directory: $archived" }
    $linkTarget = [IO.Path]::GetFullPath([string](@($originalItem.Target)[0]))
    if (-not $linkTarget.Equals($archived, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unexpected link target: $linkTarget"
    }
    # Every absolute path and junction target was checked. Delete only the
    # junction itself, then rename the physical directory without traversal.
    [IO.Directory]::Delete($original)
    [IO.Directory]::Move($archived, $original)
    New-Item -ItemType Junction -Path $archived -Target $original | Out-Null
    $legacyActions.Add([pscustomobject]@{
        physical_path=$originalRelative; archive_junction=$archiveRelative;
        reason='Preserve MATLAB mfilename-relative project roots without modifying historical scripts'
    })
}

if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'legacy_path_layout.json')) {
    throw 'Final legacy layout already recorded'
}
Reverse-Archive-Link 'auditoria_psse_matpower' 'archive/psse_compatibility/auditoria_psse_matpower'
Reverse-Archive-Link 'auditoria_psse_matpower/transpa_reduccion' 'archive/transpa_reduction_v1/studies'
Reverse-Archive-Link 'auditoria_psse_matpower/results/transpa_reduccion_v1' 'archive/transpa_reduction_v1/results'
$legacyActions | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'legacy_path_layout.json') -Encoding utf8
Write-Output 'Historical physical locations restored; archive entries now link to them. No scientific files changed.'
