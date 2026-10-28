# reaper-web-faders installer for Windows.
# Installs into the REAPER resource folder (no admin rights needed, survives REAPER updates):
#   reaper_www_root\faders.html, Scripts\WebRemote\web_fx_bridge.lua, and a line in Scripts\__startup.lua
# Usage: double-click install.bat, or: powershell -ExecutionPolicy Bypass -File install.ps1 [-ResourcePath <path>]
param([string]$ResourcePath = (Join-Path $env:APPDATA "REAPER"))
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "reaper-web-faders installer`n"
if (-not (Test-Path $ResourcePath)) {
  Write-Host "REAPER resource folder not found: $ResourcePath"
  $ResourcePath = Read-Host "Enter your REAPER resource path (REAPER: Options > Show REAPER resource path), or leave empty to cancel"
  if (-not $ResourcePath -or -not (Test-Path $ResourcePath)) { Write-Host "Cancelled."; exit 1 }
}

$www = Join-Path $ResourcePath "reaper_www_root"
$scripts = Join-Path $ResourcePath "Scripts"
$bridgeDir = Join-Path $scripts "WebRemote"
New-Item -ItemType Directory -Force -Path $www, $bridgeDir | Out-Null
Copy-Item (Join-Path $here "faders.html") (Join-Path $www "faders.html") -Force
Copy-Item (Join-Path $here "web_fx_bridge.lua") (Join-Path $bridgeDir "web_fx_bridge.lua") -Force
Write-Host "Installed page:    $www\faders.html"
Write-Host "Installed bridge:  $bridgeDir\web_fx_bridge.lua"

$startup = Join-Path $scripts "__startup.lua"
$line = 'dofile(reaper.GetResourcePath() .. "/Scripts/WebRemote/web_fx_bridge.lua")'
$utf8 = New-Object System.Text.UTF8Encoding($false)   # no BOM, Lua doesn't want one
if ((Test-Path $startup) -and (Select-String -Path $startup -SimpleMatch "web_fx_bridge.lua" -Quiet)) {
  Write-Host "Auto-start:        already in $startup"
} else {
  [System.IO.File]::AppendAllText($startup, "`r`n-- Web remote FX bridge (reaper-web-faders)`r`n$line`r`n", $utf8)
  Write-Host "Auto-start:        added to $startup"
}

# If REAPER is running, start the new bridge now (it replaces any older running copy).
# A uniquely named launcher avoids REAPER's "script already running" prompt.
$proc = Get-Process -Name reaper -ErrorAction SilentlyContinue | Select-Object -First 1
if ($proc -and $proc.Path) {
  $launcher = Join-Path $env:TEMP ("rwf_launch_" + $PID + ".lua")
  [System.IO.File]::WriteAllText($launcher, $line, $utf8)
  Start-Process -FilePath $proc.Path -ArgumentList @("-nonewinst", "`"$launcher`"")
  Write-Host "Bridge:            started in the running REAPER"
} else {
  Write-Host "Bridge:            will start next time REAPER launches"
}

$ini = Join-Path $ResourcePath "reaper.ini"
if (-not ((Test-Path $ini) -and (Select-String -Path $ini -Pattern "^csurf_\d+=HTTP" -Quiet))) {
  Write-Host "`nNo web interface is set up in REAPER yet:"
  Write-Host "  Preferences > Control/OSC/Web > Add > Web browser interface,"
  Write-Host "  pick a port (e.g. 8889) and choose 'faders.html' as the default interface."
}
$ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
  Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } | Select-Object -First 1).IPAddress
if (-not $ip) { $ip = "<this-pc-ip>" }
Write-Host "`nThen open http://${ip}:<port>/faders.html on your phone or tablet.`n"
Write-Host "Done."
