[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$RepairDiscovery,
    [switch]$KeepInterface
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$pluginName = 'VLC - MediaPlayer History Shuffle.lua'
$sourcePath = Join-Path $PSScriptRoot $pluginName
$extensionDirectory = Join-Path $env:APPDATA 'vlc\lua\extensions'
$targetPath = Join-Path $extensionDirectory $pluginName
$vlcCandidates = @(
    (Join-Path $env:ProgramFiles 'VideoLAN\VLC\vlc.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'VideoLAN\VLC\vlc.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\VideoLAN\VLC\vlc.exe')
)
$vlcPath = $vlcCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
$pluginCachePath = if ($vlcPath) { Join-Path (Split-Path $vlcPath) 'plugins\plugins.dat' } else { $null }
$pluginCacheBackupPath = Join-Path $env:APPDATA 'vlc\plugins.dat.history-shuffle-backup'
$vlcConfigPath = Join-Path $env:APPDATA 'vlc\vlcrc'
$vlcConfigBackupPath = Join-Path $env:APPDATA 'vlc\vlcrc.history-shuffle-interface-backup'

function Get-Hash([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Assert-ExtensionFile {
    if (-not (Test-Path -LiteralPath $targetPath)) {
        throw 'History Shuffle is not installed for the current Windows user.'
    }
    if ((Get-Hash $sourcePath) -ne (Get-Hash $targetPath)) {
        throw 'The installed plugin does not match this repository. Run install.ps1 again.'
    }
    if (-not (Select-String -LiteralPath $targetPath -SimpleMatch 'title = "History Shuffle"' -Quiet)) {
        throw 'The installed Lua file does not contain the expected VLC descriptor.'
    }
    if (Select-String -LiteralPath $targetPath -Pattern '\brawget\s*\(' -Quiet) {
        throw 'The installed Lua file calls rawget, which VLC removes from the desktop extension sandbox.'
    }
    if (-not (Select-String -LiteralPath $targetPath -Pattern '^function meta_changed\s*\(' -Quiet)) {
        throw 'The installed Lua file is missing VLC 3 input-listener callback meta_changed().'
    }
}

function Get-InterfaceState {
    $configured = $null
    $minimal = $false
    if (Test-Path -LiteralPath $vlcConfigPath) {
        $configuredLine = Select-String -LiteralPath $vlcConfigPath -Pattern '^intf=(.+)$' |
            Select-Object -Last 1
        if ($configuredLine) {
            $configured = $configuredLine.Matches[0].Groups[1].Value.Trim()
        }
        $minimal = [bool](Select-String -LiteralPath $vlcConfigPath -Pattern '^qt-minimal-view=1\s*$' -Quiet)
    }

    $explicitlyNonQt = $configured -and $configured -ne 'any' -and
        $configured -notmatch '(^|,)qt($|,)'
    [pscustomobject]@{
        Configured = if ($configured) { $configured } else { 'default (Qt)' }
        Compatible = -not $explicitlyNonQt -and -not $minimal
        NonQt = [bool]$explicitlyNonQt
        Minimal = $minimal
    }
}

function Set-CompatibleQtInterface {
    $interface = Get-InterfaceState
    if ($interface.Compatible -or $KeepInterface) {
        return
    }
    if (Get-Process vlc -ErrorAction SilentlyContinue) {
        throw 'VLC is running with an interface configuration that hides Lua extensions. Fully exit VLC and run install.ps1 again.'
    }
    if (-not (Test-Path -LiteralPath $vlcConfigPath)) {
        return
    }

    Copy-Item -LiteralPath $vlcConfigPath -Destination $vlcConfigBackupPath -Force
    $content = [IO.File]::ReadAllText($vlcConfigPath)
    if ($interface.NonQt) {
        $content = [Text.RegularExpressions.Regex]::Replace(
            $content,
            '(?m)^intf=.*$',
            'intf=qt,any'
        )
    }
    if ($interface.Minimal) {
        $content = [Text.RegularExpressions.Regex]::Replace(
            $content,
            '(?m)^qt-minimal-view=1\s*$',
            'qt-minimal-view=0'
        )
    }
    [IO.File]::WriteAllText($vlcConfigPath, $content, (New-Object Text.UTF8Encoding($false)))
    Write-Host 'Configured VLC to use its Qt interface so View > History Shuffle can exist.' -ForegroundColor Yellow
    Write-Host "Interface backup: $vlcConfigBackupPath"
}

function Write-Diagnostics {
    Write-Host "History Shuffle installation check" -ForegroundColor Cyan
    Write-Host "  VLC:       $(if ($vlcPath) { $vlcPath } else { 'not detected in standard locations' })"
    if ($vlcPath) {
        $version = (Get-Item -LiteralPath $vlcPath).VersionInfo.ProductVersion
        Write-Host "  Version:   $version"
    }
    Write-Host "  Extension: $targetPath"
    Write-Host "  Present:   $(Test-Path -LiteralPath $targetPath)"
    if (Test-Path -LiteralPath $targetPath) {
        Write-Host "  SHA-256:   $(Get-Hash $targetPath)"
    }
    $running = @(Get-Process vlc -ErrorAction SilentlyContinue).Count
    Write-Host "  VLC open:  $($running -gt 0)"
    $interface = Get-InterfaceState
    Write-Host "  Interface: $($interface.Configured)"
    Write-Host "  View menu: $(if ($interface.Compatible) { 'compatible' } else { 'BLOCKED by the configured interface' })"
    $duplicateFiles = @(
        Get-ChildItem -LiteralPath $extensionDirectory -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.FullName -ne $targetPath -and
                $_.Name -match '(?i)history.*shuffle|shuffle.*history'
            }
    )
    Write-Host "  Conflicting copies: $($duplicateFiles.Count)"
    foreach ($duplicate in $duplicateFiles) {
        Write-Host "    $($duplicate.FullName)" -ForegroundColor Yellow
    }
    $cacheStatus = if ($pluginCachePath -and (Test-Path -LiteralPath $pluginCachePath)) {
        (Get-Item -LiteralPath $pluginCachePath).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
    } else {
        'not found'
    }
    Write-Host "  Plugin cache: $cacheStatus"
}

function Repair-StalePluginCache {
    if (Get-Process vlc -ErrorAction SilentlyContinue) {
        throw 'Fully exit VLC before using -RepairDiscovery.'
    }
    if (-not $vlcPath) {
        throw 'VLC was not detected in a standard Windows install location.'
    }
    $vlcDirectory = Split-Path $vlcPath
    $cacheGenerator = Join-Path $vlcDirectory 'vlc-cache-gen.exe'
    $pluginsDirectory = Join-Path $vlcDirectory 'plugins'
    if (-not (Test-Path -LiteralPath $cacheGenerator) -or -not (Test-Path -LiteralPath $pluginsDirectory)) {
        throw 'VLC cache generator or plugins directory is missing. Repair/reinstall VLC.'
    }
    if (Test-Path -LiteralPath $pluginCachePath) {
        New-Item -ItemType Directory -Path (Split-Path $pluginCacheBackupPath) -Force | Out-Null
        Copy-Item -LiteralPath $pluginCachePath -Destination $pluginCacheBackupPath -Force
    }
    & $cacheGenerator $pluginsDirectory
    if ($LASTEXITCODE -ne 0) {
        throw 'VLC could not rebuild plugins.dat. Open PowerShell as Administrator and run -RepairDiscovery again.'
    }
    Write-Host 'Rebuilt VLC plugins.dat so the Lua extension engine can be discovered.' -ForegroundColor Yellow
    Write-Host "Backup: $pluginCacheBackupPath"
}

if ($Check) {
    Write-Diagnostics
    Assert-ExtensionFile
    $interface = Get-InterfaceState
    if (-not $interface.Compatible) {
        throw "The configured VLC interface '$($interface.Configured)' hides desktop Lua extensions. Fully exit VLC and run install.ps1 to switch to Qt."
    }
    Write-Host '  Result:    installed correctly' -ForegroundColor Green
    exit 0
}

if (-not (Test-Path -LiteralPath $sourcePath)) {
    throw "Plugin source is missing: $sourcePath"
}

Set-CompatibleQtInterface
New-Item -ItemType Directory -Path $extensionDirectory -Force | Out-Null
Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
Unblock-File -LiteralPath $targetPath -ErrorAction SilentlyContinue

if ($RepairDiscovery) {
    Repair-StalePluginCache
}

Assert-ExtensionFile

Write-Diagnostics
Write-Host '  Result:    installed correctly' -ForegroundColor Green
if (Get-Process vlc -ErrorAction SilentlyContinue) {
    Write-Warning 'VLC is running. Fully exit every VLC window and start VLC again before checking View > History Shuffle.'
} else {
    Write-Host 'Restart VLC, then choose View > History Shuffle.' -ForegroundColor Yellow
}
