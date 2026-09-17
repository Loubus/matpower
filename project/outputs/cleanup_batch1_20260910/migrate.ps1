$ErrorActionPreference = 'Stop'
$cleanupRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$cleanupRootPrefix = $cleanupRoot.TrimEnd('\') + '\'
$cleanupChanges = [System.Collections.Generic.List[object]]::new()

function Workspace-Path([string]$relative) {
    $absolute = [IO.Path]::GetFullPath((Join-Path $cleanupRoot $relative))
    if (-not $absolute.StartsWith($cleanupRootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path outside workspace: $absolute"
    }
    return $absolute
}

function Copy-Input([string]$sourceRelative, [string]$targetRelative) {
    $source = Workspace-Path $sourceRelative
    $target = Workspace-Path $targetRelative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing source: $source" }
    if (Test-Path -LiteralPath $target) { throw "Destination exists: $target" }
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    $hashBefore = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    Copy-Item -LiteralPath $source -Destination $target
    $hashAfter = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
    if ($hashBefore -ne $hashAfter) { throw "Copy differs: $target" }
    $cleanupChanges.Add([pscustomobject]@{action='copy';source=$sourceRelative;target=$targetRelative;sha256=$hashAfter})
}

function Move-Tree([string]$sourceRelative, [string]$targetRelative, [bool]$keepAlias) {
    $source = Workspace-Path $sourceRelative
    $target = Workspace-Path $targetRelative
    if (-not (Test-Path -LiteralPath $source -PathType Container)) { throw "Missing directory: $source" }
    if (Test-Path -LiteralPath $target) { throw "Destination exists: $target" }
    if ((Get-Item -LiteralPath $source).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Source already a link: $source" }
    $sourceResolved = (Resolve-Path -LiteralPath $source).Path
    if (-not $sourceResolved.StartsWith($cleanupRootPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Resolved source outside workspace' }
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    # Both absolute targets have been checked; same-shell, same-volume move.
    [IO.Directory]::Move($source, $target)
    if ($keepAlias) {
        New-Item -ItemType Junction -Path $source -Target $target | Out-Null
    }
    $cleanupChanges.Add([pscustomobject]@{action='move_directory';source=$sourceRelative;target=$targetRelative;compatibility_junction=$keepAlias})
}

if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'migration.json')) { throw 'Migration already recorded' }
# Save precisely the current files that the later path-only edits touch.
Copy-Input 'iniciar_proyecto.m' 'outputs/cleanup_batch1_20260910/before/iniciar_proyecto.m'
Copy-Input 'matpower/lib/t/t_mpxt_psse.m' 'outputs/cleanup_batch1_20260910/before/t_mpxt_psse.m'
Copy-Input 'auditoria_psse_matpower/beerten_5bus/cpf_runner/beerten_cpf_run.m' 'outputs/cleanup_batch1_20260910/before/beerten_cpf_run.m'

$cleanupGenq = @('psse_genq_3bus_local_inband.raw','psse_genq_3bus_qmax.raw','psse_genq_3bus_qmin.raw',
 'psse_genq_3bus_qmin_qmax_zero.raw','psse_genq_3bus_slack_q_limit.raw','psse_genq_4bus_remote_single.raw',
 'psse_genq_5bus_remote_group.raw','psse_genq_5bus_remote_group_all_limited.raw','psse_genq_5bus_remote_group_one_limited.raw')
foreach ($name in $cleanupGenq) {
    Copy-Input ('auditoria_psse_matpower/psse_validation_cases_genq/' + $name) ('tests/fixtures/controls/legacy_regression/psse_validation_cases_genq/' + $name)
}
Copy-Input 'auditoria_psse_matpower/psse_validation_cases_integrated/psse_integrated_controls_40bus.raw' 'tests/fixtures/controls/legacy_regression/psse_validation_cases_integrated/psse_integrated_controls_40bus.raw'
foreach ($name in @('suite_u_ultc_3w_tab.raw','suite_u_ultc_3w_tab_cw2.raw','suite_m_integrated_30bus_nominal.raw','suite_m_integrated_14bus_nominal.raw')) {
    Copy-Input ('auditoria_psse_matpower/psse_validation_suite/' + $name) ('tests/fixtures/controls/legacy_regression/psse_validation_suite/' + $name)
}

Copy-Input 'PSSE/V26p_Trs_2532.raw' 'cases/full_network/raw/V26p_Trs_2532.raw'
foreach ($entry in @(@('14','case14.m'),@('30','case_ieee30.m'),@('39','case39.m'),@('57','case57.m'))) {
    Copy-Input ('matpower/data/' + $entry[1]) ('cases/ieee/' + $entry[0] + '/' + $entry[1])
}
foreach ($file in Get-ChildItem -LiteralPath (Workspace-Path 'matpower/data') -Filter 'case5_vsc_mtdc_beerten*.m' -File) {
    Copy-Input ('matpower/data/' + $file.Name) ('cases/beerten/variants/' + $file.Name)
}

Move-Tree 'outputs/thesis_scope_20260910/upstream/Nordic' 'cases/nordic/upstream' $false
Move-Tree 'outputs/thesis_scope_20260910/upstream/CIGRE_implementation' 'cases/cigre/upstream' $false
Move-Tree 'outputs/thesis_scope_20260910/upstream/PowerModelsACDC' 'cases/ieee/upstream/PowerModelsACDC' $false
Move-Tree 'outputs/thesis_scope_20260910/upstream/MatACDC_cases' 'cases/beerten/upstream/MatACDC_cases' $false
Copy-Input 'outputs/thesis_scope_20260910/upstream/MatACDC1_0.zip' 'cases/beerten/upstream/MatACDC1_0.zip'
Move-Tree 'auditoria_psse_matpower/beerten_5bus' 'studies/beerten' $true
Move-Tree 'auditoria_psse_matpower/results/transpa_reduccion_v1' 'archive/transpa_reduction_v1/results' $true
Move-Tree 'auditoria_psse_matpower/transpa_reduccion' 'archive/transpa_reduction_v1/studies' $true

# Keep old paths as documented junctions so historical scripts still resolve.
# The active Beerten implementation and benchmark inputs have already moved out.
Move-Tree 'auditoria_psse_matpower' 'archive/psse_compatibility/auditoria_psse_matpower' $true

$cleanupChanges | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'migration.json') -Encoding utf8
Write-Output ('Recorded ' + $cleanupChanges.Count + ' migration actions; no deletions.')
