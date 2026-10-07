<#
  PLAYER TOOL. Checks the manifest and updates the instance's mods.
  Best used as MultiMC's Pre-launch command (see README) so it runs every launch.

  -InstanceDir  The instance's .minecraft folder. MultiMC provides it as $INST_MC_DIR.
  -Auto         Don't ask; just apply updates (still shows a notice).
  -NoSelfUpdate Internal: skip updating this script (used right after a self-update).
#>
param(
    [string]$InstanceDir = $env:INST_MC_DIR,
    [switch]$Auto,
    [switch]$NoSelfUpdate
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Windows.Forms

function Msg($text, $buttons = 'OK', $icon = 'Information') {
    [Windows.Forms.MessageBox]::Show($text, 'Mod Sync', $buttons, $icon)
}
function Get-Base($name) {
    $n = [IO.Path]::GetFileNameWithoutExtension($name)
    if ($n -match '^(.+?)[-_+ ]v?\d') { $Matches[1] } else { $n }
}
function Get-Diff($old, $new) {
    $old = @($old | Where-Object { $_ }); $new = @($new | Where-Object { $_ })
    $rem = @($old | Where-Object { $new -notcontains $_ })
    $add = @(); $upd = @()
    foreach ($a in @($new | Where-Object { $old -notcontains $_ })) {
        $b = Get-Base $a
        $hit = $rem | Where-Object { (Get-Base $_) -eq $b } | Select-Object -First 1
        if ($hit) {
            $upd += ([IO.Path]::GetFileNameWithoutExtension($hit) + ' -> ' + [IO.Path]::GetFileNameWithoutExtension($a))
            $rem = @($rem | Where-Object { $_ -ne $hit })
        } else { $add += [IO.Path]::GetFileNameWithoutExtension($a) }
    }
    [pscustomobject]@{
        Added   = @($add)
        Updated = @($upd)
        Removed = @($rem | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) })
    }
}
function Section($title, $items, $max = 15) {
    $items = @($items)
    if ($items.Count -eq 0) { return '' }
    $out = "`n$title ($($items.Count)):`n" + (($items | Select-Object -First $max | ForEach-Object { "  $_" }) -join "`n")
    if ($items.Count -gt $max) { $out += "`n  ...and $($items.Count - $max) more" }
    $out + "`n"
}

try {
    $cfg = Get-Content (Join-Path $PSScriptRoot 'modsync.config.json') -Raw | ConvertFrom-Json
    if (-not $InstanceDir) { throw "No instance folder. Run via MultiMC pre-launch command or pass -InstanceDir." }
    $InstanceDir = $InstanceDir.TrimEnd('\')

    try {
        $m = Invoke-RestMethod -Uri ($cfg.manifestUrl + '?t=' + [guid]::NewGuid().ToString('N')) -TimeoutSec 15
    } catch {
        # Offline or host down: never block the game from launching.
        exit 0
    }

    # Self-update: if the published tool differs from this script, swap it in and re-run.
    if ($m.tool -and -not $NoSelfUpdate) {
        $me = $MyInvocation.MyCommand.Path
        if ((Get-FileHash -LiteralPath $me -Algorithm SHA256).Hash.ToLower() -ne $m.tool.sha256) {
            try {
                $tmp = "$me.new"
                Invoke-WebRequest -Uri ($m.tool.url + '?t=' + [guid]::NewGuid().ToString('N')) -OutFile $tmp -UseBasicParsing
                if ((Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash.ToLower() -eq $m.tool.sha256) {
                    Move-Item $tmp $me -Force
                    $re = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $me, '-InstanceDir', $InstanceDir, '-NoSelfUpdate')
                    if ($Auto) { $re += '-Auto' }
                    & powershell @re
                    exit $LASTEXITCODE
                } else { Remove-Item $tmp -Force }
            } catch { }   # self-update is best-effort
        }
    }

    $stateFile = Join-Path $InstanceDir '.modsync-version'
    $localVer = if (Test-Path $stateFile) { (Get-Content $stateFile -Raw).Trim() } else { '' }

    # Files the player wants to keep (one filename per line)
    $ignoreFile = Join-Path $InstanceDir '.modsync-ignore'
    $keep = if (Test-Path $ignoreFile) { Get-Content $ignoreFile | Where-Object { $_.Trim() } } else { @() }

    $download = @(); $wanted = @{}
    foreach ($f in $m.files) {
        $wanted[$f.path.ToLower()] = $true
        $dest = Join-Path $InstanceDir ($f.path.Replace('/', '\'))
        if (-not (Test-Path -LiteralPath $dest) -or (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash.ToLower() -ne $f.sha256) {
            $download += $f
        }
    }

    $remove = @(); $localNames = @()
    foreach ($folder in $m.managedFolders) {
        $dir = Join-Path $InstanceDir $folder
        if (-not (Test-Path $dir)) { continue }
        Get-ChildItem -LiteralPath $dir -Recurse -File | ForEach-Object {
            $rel = $_.FullName.Substring($InstanceDir.Length + 1).Replace('\', '/')
            if (-not $wanted.ContainsKey($rel.ToLower()) -and $keep -notcontains $_.Name) { $remove += $_ }
            if ($keep -notcontains $_.Name) { $localNames += $_.Name }
        }
    }

    if ($download.Count -eq 0 -and $remove.Count -eq 0) {
        Set-Content $stateFile $m.version
        exit 0
    }

    if (-not $Auto) {
        $newNames = @($m.files | ForEach-Object { Split-Path $_.path -Leaf })
        $d = Get-Diff $localNames $newNames
        $rebuilt = @($download | Where-Object { $localNames -contains (Split-Path $_.path -Leaf) } |
            ForEach-Object { [IO.Path]::GetFileNameWithoutExtension((Split-Path $_.path -Leaf)) + ' (re-downloaded)' })

        $body = "A mod update is available (v$($m.version), $($m.published))."
        $body += Section 'ADDED' $d.Added
        $body += Section 'UPDATED' (@($d.Updated) + $rebuilt)
        $body += Section 'REMOVED' $d.Removed

        # Patch notes since the player's last version (up to 5, newest first)
        $notes = @()
        foreach ($h in @($m.history)) {
            if ($h.version -eq $localVer) { break }
            if ($h.notes) { $notes += "$(($h.published -split ' ')[0]): $($h.notes)" }
            if ($notes.Count -ge 5) { break }
        }
        if ($notes.Count -eq 0 -and $m.notes) { $notes = @($m.notes) }
        if ($notes.Count) { $body += "`nPATCH NOTES:`n" + (($notes | ForEach-Object { "  - $_" }) -join "`n") + "`n" }
        $body += "`nUpdate now?"
        if ((Msg $body 'YesNo' 'Question') -ne 'Yes') { exit 0 }
    }

    $backup = Join-Path $InstanceDir ('.modsync-backup\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    foreach ($f in $remove) {
        New-Item -ItemType Directory -Force $backup | Out-Null
        Move-Item -LiteralPath $f.FullName (Join-Path $backup $f.Name) -Force
    }
    foreach ($f in $download) {
        $dest = Join-Path $InstanceDir ($f.path.Replace('/', '\'))
        New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
        $tmp = $dest + '.part'
        Invoke-WebRequest -Uri $f.url -OutFile $tmp -UseBasicParsing
        if ((Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash.ToLower() -ne $f.sha256) {
            Remove-Item -LiteralPath $tmp -Force
            throw "Checksum mismatch for $($f.path). Tell the pack admin."
        }
        Move-Item -LiteralPath $tmp $dest -Force
    }

    Set-Content $stateFile $m.version
    Msg "Mods updated to v$($m.version). Launching the game." | Out-Null
} catch {
    Msg "Mod sync failed:`n$($_.Exception.Message)`n`nThe game will still launch, but you may be out of date." 'OK' 'Warning' | Out-Null
}
exit 0
