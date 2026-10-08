# Shared helpers for Install.ps1 and Remove.ps1
Add-Type -AssemblyName System.Windows.Forms

function Test-MMC($d) {
    $d -and (Test-Path -LiteralPath (Join-Path $d 'instances')) -and
    ((Test-Path -LiteralPath (Join-Path $d 'MultiMC.exe')) -or (Test-Path -LiteralPath (Join-Path $d 'multimc.cfg')))
}

function Find-MultiMC {
    $found = New-Object Collections.Generic.List[string]
    # 1) A running MultiMC tells us exactly where it lives
    Get-Process -Name 'MultiMC' -ErrorAction SilentlyContinue | ForEach-Object {
        try { $found.Add((Split-Path $_.Path -Parent)) } catch {}
    }
    # 2) Common places, searched a few folders deep
    $skip = 'AppData', 'Windows', '$Recycle.Bin', 'System Volume Information', 'ProgramData'
    $roots = @()
    $home1 = $env:USERPROFILE
    $roots += Get-ChildItem -LiteralPath $home1 -Directory -ErrorAction SilentlyContinue |
        Where-Object { $skip -notcontains $_.Name } | ForEach-Object { @{ Path = $_.FullName; Depth = 4 } }
    foreach ($drv in [IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady }) {
        $roots += Get-ChildItem -LiteralPath $drv.RootDirectory.FullName -Directory -ErrorAction SilentlyContinue |
            Where-Object { $skip -notcontains $_.Name -and $_.Name -ne 'Users' } | ForEach-Object { @{ Path = $_.FullName; Depth = 3 } }
    }
    foreach ($r in $roots) {
        Get-ChildItem -LiteralPath $r.Path -Filter 'MultiMC.exe' -Recurse -Depth $r.Depth -File -ErrorAction SilentlyContinue |
            ForEach-Object { $found.Add($_.DirectoryName) }
    }
    $found | Where-Object { Test-MMC $_ } | Select-Object -Unique
}

function Select-Folder($title) {
    # Normal Windows Explorer dialog (address bar, Quick access, search) - open the folder, press Open.
    $owner = New-Object Windows.Forms.Form -Property @{ TopMost = $true }
    $dlg = New-Object Windows.Forms.OpenFileDialog
    $dlg.Title = $title
    $dlg.ValidateNames = $false
    $dlg.CheckFileExists = $false
    $dlg.CheckPathExists = $true
    $dlg.FileName = 'Select this folder'
    if ($dlg.ShowDialog($owner) -ne 'OK') { return $null }
    $p = $dlg.FileName
    if (Test-Path -LiteralPath $p -PathType Container) { $p } else { Split-Path $p -Parent }
}

function Get-Instances($mmc) {
    Get-ChildItem -LiteralPath (Join-Path $mmc 'instances') -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'instance.cfg') } | ForEach-Object {
            $name = $_.Name
            $line = Get-Content -LiteralPath (Join-Path $_.FullName 'instance.cfg') | Where-Object { $_ -match '^name=' } | Select-Object -First 1
            if ($line) { $name = $line.Substring(5) }
            [pscustomobject]@{ Name = $name; Dir = $_.FullName }
        }
}

function Show-Menu($items, $label) {
    for ($i = 0; $i -lt $items.Count; $i++) { Write-Host ("  [{0}] {1}" -f ($i + 1), (& $label $items[$i])) -ForegroundColor White }
}

function Resolve-MultiMC([string]$Given) {
    if ($Given) { return $Given }
    $mmc = $null
    Write-Host 'Looking for MultiMC...' -ForegroundColor Gray
    $cands = @(Find-MultiMC)
    if ($cands.Count -eq 1) { $mmc = $cands[0]; Write-Host "Found MultiMC: $mmc" -ForegroundColor Green }
    elseif ($cands.Count -gt 1) {
        Write-Host 'Found more than one MultiMC:'
        Show-Menu $cands { param($c) $c }
        $n = Read-Host "Which one? (number, or B to browse for another)"
        if ($n -match '^\d+$' -and [int]$n -ge 1 -and [int]$n -le $cands.Count) { $mmc = $cands[[int]$n - 1] }
    }
    while (-not (Test-MMC $mmc)) {
        Write-Host "Couldn't find MultiMC automatically - pick its folder (the one with MultiMC.exe)." -ForegroundColor Yellow
        $mmc = Select-Folder 'Select your MultiMC folder (contains MultiMC.exe and "instances")'
        if (-not $mmc) { Write-Host 'Cancelled.'; exit 0 }
        if (-not (Test-MMC $mmc)) { Write-Host "That folder doesn't look like MultiMC (no MultiMC.exe + instances). Try again." -ForegroundColor Red }
    }
    $mmc
}

function Wait-ForChangeKey([int]$Seconds) {
    if ($Seconds -le 0) { return $false }
    try {
        $end = (Get-Date).AddSeconds($Seconds)
        while ((Get-Date) -lt $end) {
            if ([Console]::KeyAvailable) {
                $k = [Console]::ReadKey($true)
                if ($k.Key -eq 'C') { return $true }
            }
            Start-Sleep -Milliseconds 100
        }
    } catch { }   # no real console (redirected input): just don't wait
    return $false
}
