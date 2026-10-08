<#
  Run by the "MultiMC + Mod Sync" desktop shortcut:
  checks for mod updates on your saved instance(s), then opens MultiMC.
  If anything goes wrong it still just opens MultiMC.
#>
param(
    [Parameter(Mandatory)][string]$MultiMCDir,
    [switch]$NoLaunch
)
$ErrorActionPreference = 'SilentlyContinue'

$state = Join-Path (Join-Path $env:LOCALAPPDATA 'ModSync') 'install-selection.json'
$tool  = Join-Path $PSScriptRoot 'ModSync.ps1'

if ((Test-Path -LiteralPath $state) -and (Test-Path -LiteralPath $tool)) {
    $saved = Get-Content -LiteralPath $state -Raw | ConvertFrom-Json
    foreach ($i in @($saved.instances)) {
        $mc = Join-Path $i.dir '.minecraft'
        if (-not (Test-Path -LiteralPath $mc)) { $mc = Join-Path $i.dir 'minecraft' }
        if (Test-Path -LiteralPath $mc) {
            & powershell -NoProfile -ExecutionPolicy Bypass -File $tool -InstanceDir $mc
        }
    }
}

$exe = Join-Path $MultiMCDir 'MultiMC.exe'
if (-not $NoLaunch -and (Test-Path -LiteralPath $exe) -and -not (Get-Process -Name 'MultiMC' -ErrorAction SilentlyContinue)) {
    Start-Process -FilePath $exe -WorkingDirectory $MultiMCDir
}
