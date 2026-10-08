<#
  PLAYER INSTALLER (run by Install.bat).
  - Finds your MultiMC automatically (falls back to a normal Explorer folder picker).
  - Lists your instances so you can pick the modpack.
  - Closes MultiMC if it's running, sets up the auto-updater, then reopens MultiMC.
  - Remembers your choice. Next run shows it for a few seconds - press C to change it.
    (forget_previous_instance_selected.bat clears the saved choice.)

  Test switches: -MultiMCDir <dir>  -Pick <1,2|all>  -NoKill  -NoLaunch  -ScanOnly  -NoSave  -ChangeWait <sec>
#>
param(
    [string]$MultiMCDir,
    [string]$Pick,
    [switch]$NoKill,
    [switch]$NoLaunch,
    [switch]$ScanOnly,
    [switch]$NoSave,
    [int]$ChangeWait = 5,
    [switch]$ForceChange,  # test only: behave as if C was pressed
    [switch]$NoShortcut,
    [string]$ShortcutDir   # default: your Desktop
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

try {
    Write-Host "`n=== Mod Sync installer ===`n" -ForegroundColor Cyan

    if ($ScanOnly) {
        $cands = @(Find-MultiMC)
        Write-Host "Found: $($cands -join ' | ')"
        $cands | ForEach-Object { Get-Instances $_ | ForEach-Object { "  instance: $($_.Name)" } }
        exit 0
    }

    # ---- saved choice from a previous run? ----
    $stateFile = Join-Path (Join-Path $env:LOCALAPPDATA 'ModSync') 'install-selection.json'
    $mmc = $null
    $chosen = $null
    if (-not $MultiMCDir -and -not $Pick -and (Test-Path -LiteralPath $stateFile)) {
        try {
            $saved = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
            $still = @($saved.instances | Where-Object { Test-Path -LiteralPath (Join-Path $_.dir 'instance.cfg') })
            if ((Test-MMC $saved.multimcDir) -and $still.Count -gt 0) {
                $mmc = $saved.multimcDir
                $chosen = @($still | ForEach-Object { [pscustomobject]@{ Name = $_.name; Dir = $_.dir } })
                Write-Host "Using your saved choice: $(($chosen | ForEach-Object { $_.Name }) -join ', ')" -ForegroundColor Green
                if ($ChangeWait -gt 0) { Write-Host "Press C within $ChangeWait seconds to choose a different instance..." -ForegroundColor Yellow }
                if ($ForceChange -or (Wait-ForChangeKey $ChangeWait)) {
                    Write-Host 'OK, choose again.' -ForegroundColor Cyan
                    $chosen = $null   # keep the saved MultiMC folder, re-pick the instance
                }
            }
        } catch { }   # unreadable/outdated save: just ask again
    }

    # ---- find MultiMC ----
    if (-not $mmc) { $mmc = Resolve-MultiMC $MultiMCDir }

    # ---- pick instance(s) ----
    if (-not $chosen) {
        $instances = @(Get-Instances $mmc)
        if ($instances.Count -eq 0) { throw "No instances found in $mmc\instances" }
        if ($instances.Count -eq 1) { $chosen = @($instances[0]); Write-Host "Only one instance: $($instances[0].Name)" -ForegroundColor Green }
        else {
            Write-Host "`nYour instances:"
            Show-Menu $instances { param($i) $i.Name }
            $ans = if ($Pick) { $Pick } else { Read-Host "`nWhich one is the modpack? (number, several like 1,3, or 'all')" }
            if ($ans -eq 'all') { $chosen = $instances }
            else {
                $idx = $ans -split '[,\s]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ - 1 } | Where-Object { $_ -ge 0 -and $_ -lt $instances.Count }
                $chosen = @($idx | ForEach-Object { $instances[$_] })
            }
            if ($chosen.Count -eq 0) { throw 'No valid instance chosen.' }
        }
    }

    # ---- close MultiMC (it would overwrite our settings otherwise) ----
    if (-not $NoKill) {
        $procs = Get-Process -Name 'MultiMC' -ErrorAction SilentlyContinue
        if ($procs) {
            Write-Host 'Closing MultiMC...' -ForegroundColor Yellow
            $procs | Stop-Process -Force
            Start-Sleep -Seconds 2
        }
    }

    # ---- install the tool ----
    $dest = Join-Path $env:LOCALAPPDATA 'ModSync'
    New-Item -ItemType Directory -Force $dest | Out-Null
    foreach ($f in 'ModSync.ps1', 'modsync.config.json', 'LaunchMultiMC.ps1') { Copy-Item (Join-Path $PSScriptRoot $f) $dest -Force }
    $script = (Join-Path $dest 'ModSync.ps1').Replace('\', '/')
    $cmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$script`""

    foreach ($inst in $chosen) {
        $cfgPath = Join-Path $inst.Dir 'instance.cfg'
        $lines = New-Object Collections.Generic.List[string]
        Get-Content -LiteralPath $cfgPath | Where-Object { $_ -notmatch '^(OverrideCommands|PreLaunchCommand)=' } | ForEach-Object { $lines.Add($_) }
        $lines.Add('OverrideCommands=true')
        $lines.Add("PreLaunchCommand=$cmd")
        [IO.File]::WriteAllLines($cfgPath, $lines, (New-Object Text.UTF8Encoding $false))
        Write-Host "Set up: $($inst.Name)" -ForegroundColor Green
    }

    # remember the choice for next time
    if (-not $NoSave) {
        $save = [ordered]@{
            multimcDir = $mmc
            instances  = @($chosen | ForEach-Object { [ordered]@{ name = $_.Name; dir = $_.Dir } })
        }
        [IO.File]::WriteAllText($stateFile, (ConvertTo-Json -InputObject $save -Depth 4), (New-Object Text.UTF8Encoding $false))
    }

    $exe = Join-Path $mmc 'MultiMC.exe'

    # desktop shortcut: check for updates, then open MultiMC
    if (-not $NoShortcut) {
        try {
            $lnkDir = if ($ShortcutDir) { $ShortcutDir } else { [Environment]::GetFolderPath('Desktop') }
            $lnk = Join-Path $lnkDir 'MultiMC + Mod Sync.lnk'
            $sc = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
            $sc.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $sc.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $dest 'LaunchMultiMC.ps1')`" -MultiMCDir `"$mmc`""
            $sc.WorkingDirectory = $mmc
            if (Test-Path -LiteralPath $exe) { $sc.IconLocation = "$exe,0" }
            $sc.Description = 'Checks for mod updates, then opens MultiMC'
            $sc.Save()
            Write-Host "Created desktop shortcut: MultiMC + Mod Sync  (open MultiMC with it to check for updates at startup)" -ForegroundColor Green
        } catch { Write-Host "Couldn't create the desktop shortcut: $($_.Exception.Message)" -ForegroundColor Yellow }
    }

    Write-Host "`nDone! Your mods will now update automatically when you launch." -ForegroundColor Cyan
    if (-not $NoLaunch -and (Test-Path -LiteralPath $exe)) {
        Write-Host 'Reopening MultiMC...' -ForegroundColor Gray
        Start-Process -FilePath $exe -WorkingDirectory $mmc
    }
    Start-Sleep -Seconds 3
} catch {
    Write-Host "`nInstall failed: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host 'Press Enter to close'
    exit 1
}
