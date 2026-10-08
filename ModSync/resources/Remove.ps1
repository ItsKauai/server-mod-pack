<#
  Turns the auto-updater OFF for the instance(s) you pick (run by remove_mod_sync.bat).
  Your mods stay exactly as they are; they just stop updating on launch.

  Test switches: -MultiMCDir <dir>  -Pick <1,2|all>  -NoKill  -NoLaunch  -NoSave
#>
param(
    [string]$MultiMCDir,
    [string]$Pick,
    [switch]$NoKill,
    [switch]$NoLaunch,
    [switch]$NoSave,
    [string]$ShortcutDir   # default: your Desktop
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

try {
    Write-Host "`n=== Mod Sync: turn off updates ===`n" -ForegroundColor Cyan

    $stateFile = Join-Path (Join-Path $env:LOCALAPPDATA 'ModSync') 'install-selection.json'
    $mmc = $null
    if (-not $MultiMCDir -and (Test-Path -LiteralPath $stateFile)) {
        try { $s = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json; if (Test-MMC $s.multimcDir) { $mmc = $s.multimcDir } } catch { }
    }
    if (-not $mmc) { $mmc = Resolve-MultiMC $MultiMCDir }

    # Only instances that currently have the updater hooked in
    $active = @(Get-Instances $mmc | Where-Object {
        Get-Content -LiteralPath (Join-Path $_.Dir 'instance.cfg') | Where-Object { $_ -match '^PreLaunchCommand=.*ModSync\.ps1' }
    })
    if ($active.Count -eq 0) { Write-Host 'No instances have Mod Sync turned on. Nothing to do.' -ForegroundColor Yellow; Start-Sleep 3; exit 0 }

    Write-Host 'Instances with Mod Sync on:'
    Show-Menu $active { param($i) $i.Name }
    $ans = if ($Pick) { $Pick } elseif ($active.Count -eq 1) { '1' } else { Read-Host "`nTurn off for which? (number, several like 1,3, or 'all')" }
    if ($ans -eq 'all') { $chosen = $active }
    else {
        $idx = $ans -split '[,\s]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ - 1 } | Where-Object { $_ -ge 0 -and $_ -lt $active.Count }
        $chosen = @($idx | ForEach-Object { $active[$_] })
    }
    if ($chosen.Count -eq 0) { throw 'No valid instance chosen.' }

    if (-not $NoKill) {
        $procs = Get-Process -Name 'MultiMC' -ErrorAction SilentlyContinue
        if ($procs) { Write-Host 'Closing MultiMC...' -ForegroundColor Yellow; $procs | Stop-Process -Force; Start-Sleep -Seconds 2 }
    }

    foreach ($inst in $chosen) {
        $cfgPath = Join-Path $inst.Dir 'instance.cfg'
        $kept = @(Get-Content -LiteralPath $cfgPath | Where-Object { $_ -notmatch '^PreLaunchCommand=.*ModSync\.ps1' })
        # Drop the "custom commands" switch only if no other custom command is still in use
        $otherCmds = @($kept | Where-Object { $_ -match '^(PreLaunchCommand|PostExitCommand|WrapperCommand)=.+' })
        if ($otherCmds.Count -eq 0) { $kept = @($kept | Where-Object { $_ -notmatch '^OverrideCommands=' }) }
        [IO.File]::WriteAllLines($cfgPath, $kept, (New-Object Text.UTF8Encoding $false))
        Write-Host "Turned off: $($inst.Name)" -ForegroundColor Green
    }

    # keep the remembered install choice in sync
    if (-not $NoSave -and (Test-Path -LiteralPath $stateFile)) {
        try {
            $s = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
            $gone = @($chosen | ForEach-Object { $_.Dir })
            $left = @($s.instances | Where-Object { $gone -notcontains $_.dir })
            if ($left.Count -eq 0) {
                [IO.File]::Delete($stateFile)
                # nothing left to keep updated: remove the desktop shortcut too
                $lnkDir = if ($ShortcutDir) { $ShortcutDir } else { [Environment]::GetFolderPath('Desktop') }
                $lnk = Join-Path $lnkDir 'MultiMC + Mod Sync.lnk'
                if (Test-Path -LiteralPath $lnk) { [IO.File]::Delete($lnk); Write-Host 'Removed the "MultiMC + Mod Sync" desktop shortcut.' -ForegroundColor Green }
            }
            else {
                $save = [ordered]@{ multimcDir = $s.multimcDir; instances = @($left | ForEach-Object { [ordered]@{ name = $_.name; dir = $_.dir } }) }
                [IO.File]::WriteAllText($stateFile, (ConvertTo-Json -InputObject $save -Depth 4), (New-Object Text.UTF8Encoding $false))
            }
        } catch { }
    }

    Write-Host "`nDone. Mods stay as they are but will no longer update on launch." -ForegroundColor Cyan
    Write-Host '(Run Install.bat any time to turn it back on.)' -ForegroundColor Gray
    $exe = Join-Path $mmc 'MultiMC.exe'
    if (-not $NoLaunch -and (Test-Path -LiteralPath $exe)) { Start-Process -FilePath $exe -WorkingDirectory $mmc }
    Start-Sleep -Seconds 3
} catch {
    Write-Host "`nFailed: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host 'Press Enter to close'
    exit 1
}
