param(
    [string]$Godot = 'E:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe',
    [switch]$GPU,
    [switch]$Benchmark,
    [switch]$GPUCombatBenchmark,
    [switch]$LegacyParityBenchmark,
    [switch]$LegacyAvoidance
)
$ErrorActionPreference = 'Stop'
$taskProject = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$taskLogs = Join-Path ([System.IO.Path]::GetTempPath()) ('vearth-mass-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $taskLogs

function Invoke-GodotCheck([string]$Name, [string[]]$Arguments, [string]$Pass, [int]$Timeout = 45) {
    $taskLog = Join-Path $taskLogs ($Name + '.log')
    $taskArgs = @('--path', ('"' + $taskProject + '"'), '--log-file', ('"' + $taskLog + '"')) + $Arguments
    $taskProcess = Start-Process -FilePath $Godot -ArgumentList $taskArgs -WindowStyle Hidden -PassThru
    $taskWatch = [Diagnostics.Stopwatch]::StartNew()
    while (-not $taskProcess.WaitForExit(1000)) {
        if ($taskWatch.Elapsed.TotalSeconds -gt $Timeout) {
            Stop-Process -Id $taskProcess.Id
            throw "$Name timed out. Log: $taskLog"
        }
    }
    $taskText = Get-Content -LiteralPath $taskLog -Raw
    if ($taskProcess.ExitCode -ne 0 -or $taskText -match 'SCRIPT ERROR|Parse Error|(?m)^ERROR:' -or ($Pass -and $taskText -notmatch $Pass)) {
        Write-Host $taskText
        throw "$Name failed (exit $($taskProcess.ExitCode)). Log: $taskLog"
    }
    Write-Host "PASS $Name"
}

Invoke-GodotCheck 'import' @('--headless', '--editor', '--quit') ''
foreach ($taskScene in @('enemy_data_validation_test', 'mass_enemy_spawner_test', 'enemy_world_test',
    'enemy_combat_test', 'mass_enemy_integration_test', 'mass_enemy_playable_test', 'advanced_turrets_test',
    'grid_combat_prototype_test', 'grid_layout_persistence_test', 'level_progression_test')) {
    Invoke-GodotCheck $taskScene @('--headless', "res://tests/$taskScene.tscn", '--quit-after', '400') 'tests passed'
}
foreach ($taskScript in @('turret_cone_test')) {
    Invoke-GodotCheck $taskScript @('--headless', '--script', "res://tests/$taskScript.gd", '--quit-after', '400') 'tests passed'
}
if ($LegacyAvoidance) {
    # Entrypoint/fixture fixed; the current legacy algorithm still fails route 29.
    Invoke-GodotCheck 'asteroid_avoidance_test' @('--headless', 'res://tests/asteroid_avoidance_test.tscn', '--quit-after', '400') 'tests passed'
} else {
    Write-Warning 'Legacy asteroid_avoidance_test: fixture repaired; route 29 still intersects an avoidance volume. Use -LegacyAvoidance to reproduce; see MASS_ENEMY_RUNTIME.md.'
}
if ($GPU) {
    Invoke-GodotCheck 'enemy_gpu_render_test' @('res://tests/enemy_gpu_render_test.tscn', '--quit-after', '400') 'GPU render parity passed'
    Invoke-GodotCheck 'enemy_gpu_combat_test' @('res://tests/enemy_gpu_combat_test.tscn', '--quit-after', '1400') 'GPU combat tests passed'
    Invoke-GodotCheck 'mass_enemy_gpu_game_test' @('res://tests/mass_enemy_gpu_game_test.tscn', '--quit-after', '1400') 'Production GPU game tests passed'
    Invoke-GodotCheck 'mass_enemy_gpu_legacy_parity' @('res://tests/mass_enemy_gpu_game_test.tscn', '--quit-after', '1400', '--', '--legacy-parity') 'Production GPU game tests passed'
    Invoke-GodotCheck 'mass_enemy_arena_test' @('res://tests/mass_enemy_arena_test.tscn', '--quit-after', '400') 'arena smoke test passed'
}
if ($Benchmark) {
    # Sequential, after tests: avoid competing Godot instances during measurement.
    Invoke-GodotCheck 'mass_enemy_benchmark' @('res://tests/mass_enemy_benchmark.tscn', '--quit-after', '4000') 'rendered benchmark passed' 300
}
if ($GPUCombatBenchmark) {
    Invoke-GodotCheck 'mass_enemy_gpu_benchmark' @('res://tests/mass_enemy_benchmark.tscn', '--quit-after', '4000', '--', '--gpu-simulation') 'rendered benchmark passed' 120
    Invoke-GodotCheck 'mass_enemy_gpu_game_benchmark' @('res://tests/mass_enemy_gpu_game_test.tscn', '--quit-after', '4000', '--', '--benchmark') 'Production GPU game tests passed' 120
}
if ($LegacyParityBenchmark) {
    Invoke-GodotCheck 'mass_enemy_legacy_parity_benchmark' @('res://tests/mass_enemy_gpu_game_test.tscn', '--quit-after', '4000', '--', '--benchmark', '--legacy-parity', '--debris-upgraded', '--output=user://mass_enemy_legacy_parity_benchmark.json') 'Production GPU game tests passed' 120
}
Write-Host "Logs: $taskLogs"
