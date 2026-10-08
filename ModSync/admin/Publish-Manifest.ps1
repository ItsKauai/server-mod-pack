<#
  ADMIN TOOL. Run this after you add/remove/update mods in your hosted folder.

  -Source   Folder you host (contains mods/, optionally config/). manifest.json is written here.
  -BaseUrl  Public URL that maps to that folder, e.g.
            https://raw.githubusercontent.com/YourName/YourRepo/main
  -Folders  Subfolders to sync (default: mods).
  -Notes    Short patch notes shown to players.

  Also: keeps a patch-note history, copies the player tool to <Source>\tool so players'
  copies self-update, and puts a ready-to-paste Discord changelog on your clipboard.

  Example:
    .\Publish-Manifest.ps1 -Source C:\ModPackHost -BaseUrl https://raw.githubusercontent.com/me/pack/main -Notes "Added JEI, updated Create"
#>
param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$BaseUrl,
    [string[]]$Folders = @('mods'),
    [string[]]$SyncOnlyFolders = @('config'),   # settings files: sent to players, updated when they change, never deleted
    [string]$Notes = '',
    [string]$ToolScript = (Join-Path $PSScriptRoot '..\resources\ModSync.ps1')
)
$ErrorActionPreference = 'Stop'
$Source = (Resolve-Path $Source).Path.TrimEnd('\')
$BaseUrl = $BaseUrl.TrimEnd('/')

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

# Previous manifest (for diff + history)
$prevPath = Join-Path $Source 'manifest.json'
$prev = if (Test-Path $prevPath) { Get-Content $prevPath -Raw | ConvertFrom-Json } else { $null }

$files = foreach ($folder in $Folders) {
    $dir = Join-Path $Source $folder
    if (-not (Test-Path $dir)) { Write-Warning "Missing folder: $dir"; continue }
    Get-ChildItem -LiteralPath $dir -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($Source.Length + 1).Replace('\', '/')
        $url = $BaseUrl + '/' + (($rel -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/')
        [ordered]@{
            path   = $rel
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLower()
            size   = $_.Length
            url    = $url
        }
    }
}
$files = @($files)
foreach ($folder in $SyncOnlyFolders) {
    $dir = Join-Path $Source $folder
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    $files += @(Get-ChildItem -LiteralPath $dir -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($Source.Length + 1).Replace('\', '/')
        $url = $BaseUrl + '/' + (($rel -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/')
        [ordered]@{
            path   = $rel
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLower()
            size   = $_.Length
            url    = $url
        }
    })
}
$files = @($files | Sort-Object { $_.path })

$sig = ($files | ForEach-Object { "$($_.path):$($_.sha256)" }) -join "`n"
$sha = [System.Security.Cryptography.SHA256]::Create()
$version = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($sig))[0..5] | ForEach-Object { $_.ToString('x2') })

# History: newest first, keep 20
$history = @()
if ($prev -and $prev.history) { $history = @($prev.history) }
$changed = (-not $prev) -or ($prev.version -ne $version)
$diff = $null
if ($changed) {
    $oldNames = if ($prev) { @($prev.files | ForEach-Object { Split-Path $_.path -Leaf }) } else { @() }
    $newNames = @($files | ForEach-Object { Split-Path $_.path -Leaf })
    $diff = Get-Diff $oldNames $newNames
    $entry = [ordered]@{
        version   = $version
        published = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        notes     = $Notes
        added     = @($diff.Added)
        updated   = @($diff.Updated)
        removed   = @($diff.Removed)
    }
    $history = @(@($entry) + $history | Select-Object -First 20)
} elseif ($Notes -and $history.Count -gt 0) {
    $history[0].notes = $Notes   # same mods, just reword the latest notes
}

# Player tool (for self-update)
$tool = $null
if (Test-Path $ToolScript) {
    $toolDir = Join-Path $Source 'tool'
    New-Item -ItemType Directory -Force $toolDir | Out-Null
    Copy-Item $ToolScript (Join-Path $toolDir 'ModSync.ps1') -Force
    $tool = [ordered]@{
        sha256 = (Get-FileHash -LiteralPath (Join-Path $toolDir 'ModSync.ps1') -Algorithm SHA256).Hash.ToLower()
        url    = "$BaseUrl/tool/ModSync.ps1"
    }
}

$manifest = [ordered]@{
    version        = $version
    published      = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    notes          = $Notes
    managedFolders = $Folders
    tool           = $tool
    history        = $history
    files          = $files
}
[IO.File]::WriteAllText($prevPath, ($manifest | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding $false))
# Keep git from rewriting line endings (the tool hash must match what players download)
$ga = Join-Path $Source '.gitattributes'
if (-not (Test-Path $ga)) { [IO.File]::WriteAllText($ga, "* -text`n") }

Write-Host "Wrote $prevPath  (version $version, $($files.Count) files)"

# Discord changelog
if ($changed -and $diff) {
    $lines = @("**Modpack update** ($((Get-Date).ToString('MMM d')))")
    if ($Notes) { $lines += $Notes }
    if ($diff.Added.Count)   { $lines += ''; $lines += "**Added ($($diff.Added.Count))**";     $lines += ($diff.Added   | ForEach-Object { "+ $_" }) }
    if ($diff.Updated.Count) { $lines += ''; $lines += "**Updated ($($diff.Updated.Count))**"; $lines += ($diff.Updated | ForEach-Object { "~ $_" }) }
    if ($diff.Removed.Count) { $lines += ''; $lines += "**Removed ($($diff.Removed.Count))**"; $lines += ($diff.Removed | ForEach-Object { "- $_" }) }
    $lines += ''; $lines += 'Just launch MultiMC and click Yes on the update popup.'
    $text = $lines -join "`n"
    try { Set-Clipboard -Value $text } catch {}
    Write-Host "`n--- Discord changelog (copied to clipboard) ---`n$text`n-----------------------------------------------"
} else {
    Write-Host 'No mod changes since last publish.'
}
Write-Host "Now commit + push the folder so it goes live at $BaseUrl"
