#
# Grok CLI installer for the pure-grok Windows builds.
# Downloads grok-windows-x86_64.exe from this repository's GitHub Releases.
#
# Usage:
#   irm https://raw.githubusercontent.com/opentokenz/pure-grok/main/install.ps1 | iex
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/opentokenz/pure-grok/main/install.ps1))) -Version v2.0.2
#   $env:GROK_VERSION = "v2.0.2"; irm ... | iex
#
# Env:
#   GROK_BIN_DIR   install directory (default: %USERPROFILE%\.local\bin)
#   GH_TOKEN       GitHub token; only required for private repositories
#   GROK_VERSION   tag to install when -Version is omitted (e.g. v2.0.2)

param(
    [Parameter(Position = 0)]
    [string]$Version
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'

if (-not $Version -and $env:GROK_VERSION) {
    $Version = $env:GROK_VERSION
}

if ($PSVersionTable.Platform -and $PSVersionTable.Platform -ne 'Win32NT') {
    Write-Error "This installer is for Windows. On macOS/Linux, use install.sh."
    exit 1
}

$arch = switch ($env:PROCESSOR_ARCHITECTURE) {
    'AMD64' { 'x86_64' }
    'x86'   { 'x86_64' }
    default { $null }
}
if (-not $arch) {
    Write-Error "Unsupported architecture: $env:PROCESSOR_ARCHITECTURE (prebuilt: windows-x86_64)"
    exit 1
}

$Repo = 'opentokenz/pure-grok'
$Asset = "grok-windows-${arch}.exe"
$ApiBase = "https://api.github.com/repos/$Repo"
$ReleaseBase = "https://github.com/$Repo/releases/download"

$headers = @{ 'User-Agent' = 'pure-grok-install' }
if ($env:GH_TOKEN) {
    $headers['Authorization'] = "Bearer $($env:GH_TOKEN)"
}

if (-not $Version) {
    Write-Host "Fetching latest release..." -ForegroundColor DarkGray
    try {
        $latest = Invoke-RestMethod -Uri "$ApiBase/releases/latest" -Headers $headers
        $Version = $latest.tag_name
    } catch {
        Write-Error "Failed to fetch the latest release tag. Check https://github.com/$Repo/releases or set GH_TOKEN."
        exit 1
    }
}
if (-not $Version) {
    Write-Error "No release tag found."
    exit 1
}

$BinDir = if ($env:GROK_BIN_DIR) { $env:GROK_BIN_DIR } else { Join-Path $env:USERPROFILE '.local\bin' }
$DownloadDir = Join-Path $env:LOCALAPPDATA 'pure-grok\downloads'
New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
New-Item -ItemType Directory -Path $DownloadDir -Force | Out-Null

$dest = Join-Path $BinDir 'grok.exe'
$url = "$ReleaseBase/$Version/$Asset"
$tmp = Join-Path $DownloadDir "$Asset.tmp"

Write-Host "  Downloading grok $Version ($Asset)..." -ForegroundColor DarkGray
try {
    Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -Headers $headers
} catch {
    if (Test-Path $tmp) { Remove-Item $tmp -Force }
    Write-Error "Failed to download $url"
    exit 1
}

try {
    & $tmp --version | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "version check failed" }
} catch {
    if (Test-Path $tmp) { Remove-Item $tmp -Force }
    Write-Error "Downloaded binary failed to run; keeping the existing install."
    exit 1
}

$cache = Join-Path $DownloadDir $Asset
Move-Item -Force $tmp $cache
Copy-Item -Force $cache $dest
Write-Host "  Installed grok $Version to $dest"

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not $userPath) { $userPath = '' }
$parts = $userPath -split ';' | Where-Object { $_ }
if ($parts -notcontains $BinDir) {
    [Environment]::SetEnvironmentVariable('Path', ($parts + $BinDir) -join ';', 'User')
    $env:Path = "$BinDir;$env:Path"
    Write-Host "  Added $BinDir to your user PATH. Open a new terminal to pick it up."
}
