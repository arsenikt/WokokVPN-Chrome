# Wokok VPN — Windows client installer (no admin, no Node, no Python).
#   irm https://raw.githubusercontent.com/arsenikt/WokokVPN-Chrome/main/client/install.ps1 | iex
# Uninstall:
#   $env:WOKOK_UNINSTALL=1; irm https://raw.githubusercontent.com/arsenikt/WokokVPN-Chrome/main/client/install.ps1 | iex
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Repo   = if ($env:WOKOK_REPO) { $env:WOKOK_REPO } else { "arsenikt/WokokVPN-Chrome" }
$Branch = if ($env:WOKOK_BRANCH) { $env:WOKOK_BRANCH } else { "main" }
$HostName = "com.wokok.chrome"
$ExtIds = @("pkimbklalingmifhjiojgcckpfinfjdo") + @("$env:WOKOK_EXT_IDS".Split(",") | Where-Object { $_ })
$D = Join-Path $env:LOCALAPPDATA "WokokVPN"
$Raw = "https://raw.githubusercontent.com/$Repo/$Branch"
$Local = if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot "host\wokok-host.ps1"))) { $PSScriptRoot } else { $null }
$Browsers = @("Google\Chrome", "Google\Chrome Beta", "Chromium", "Microsoft\Edge", "BraveSoftware\Brave-Browser", "Vivaldi", "Yandex\YandexBrowser")

function Say($t) { Write-Host "  $t" -ForegroundColor DarkYellow }
function Ok($t)  { Write-Host "  [ok] $t" -ForegroundColor Green }

if ($env:WOKOK_UNINSTALL) {
  Get-CimInstance Win32_Process -Filter "Name='xray.exe' OR Name='ssh.exe'" | Where-Object { $_.CommandLine -like "*WokokVPN*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  foreach ($b in $Browsers) { Remove-Item "HKCU:\Software\$b\NativeMessagingHosts\$HostName" -Force -ErrorAction SilentlyContinue }
  Remove-Item $D -Recurse -Force -ErrorAction SilentlyContinue
  Ok "Wokok VPN removed. Remove the extension in chrome://extensions"
  return
}

Write-Host ""
Write-Host "   W O K O K   V P N   for Chrome" -ForegroundColor DarkYellow
Write-Host "   stir-fry your traffic" -ForegroundColor Yellow
Write-Host ""

New-Item -ItemType Directory -Force "$D\bin", "$D\host", "$D\run" | Out-Null

# 1. xray-core
$arch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "arm64-v8a" } else { "64" }
if (-not (Test-Path "$D\bin\xray.exe") -or $env:WOKOK_UPDATE) {
  Say "Downloading Xray-core ($arch) from github.com/XTLS/Xray-core..."
  Get-CimInstance Win32_Process -Filter "Name='xray.exe'" | Where-Object { $_.CommandLine -like "*WokokVPN*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  $zip = Join-Path $env:TEMP "wokok-xray.zip"
  Invoke-WebRequest "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-windows-$arch.zip" -OutFile $zip -UseBasicParsing
  Expand-Archive $zip -DestinationPath "$D\bin" -Force
  Remove-Item $zip
}
Ok ("Xray " + ((& "$D\bin\xray.exe" version | Select-Object -First 1) -split " ")[1])

# 2. native helper
foreach ($f in "wokok-host.ps1") {
  if ($Local) { Copy-Item (Join-Path $Local "host\$f") "$D\host\$f" -Force }
  else { Invoke-WebRequest "$Raw/client/host/$f" -OutFile "$D\host\$f" -UseBasicParsing }
}
$launcher = "$D\host\wokok-host.cmd"
[IO.File]::WriteAllText($launcher, "@echo off`r`npowershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"%~dp0wokok-host.ps1`"`r`n", [Text.Encoding]::ASCII)
$manifest = [ordered]@{ name = $HostName; description = "Wokok VPN helper"; path = $launcher; type = "stdio"
  allowed_origins = @($ExtIds | ForEach-Object { "chrome-extension://$_/" }) }
$mPath = "$D\host\$HostName.json"
[IO.File]::WriteAllText($mPath, ($manifest | ConvertTo-Json), (New-Object Text.UTF8Encoding $false))
foreach ($b in $Browsers) {
  $reg = "HKCU:\Software\$b\NativeMessagingHosts\$HostName"
  New-Item -Path $reg -Force | Out-Null
  Set-ItemProperty -Path $reg -Name "(default)" -Value $mPath
}
Ok "Helper registered for Chrome, Edge, Brave, Vivaldi, Yandex, Chromium"

# 3. extension files (for Load unpacked)
$ext = "$D\extension"
if ($Local -and (Test-Path (Join-Path $Local "..\extension\manifest.json"))) {
  Remove-Item $ext -Recurse -Force -ErrorAction SilentlyContinue
  Copy-Item (Join-Path $Local "..\extension") $ext -Recurse -Force
} else {
  $zip = Join-Path $env:TEMP "wokok-ext.zip"
  Invoke-WebRequest "https://github.com/$Repo/releases/latest/download/wokok-extension.zip" -OutFile $zip -UseBasicParsing
  Remove-Item $ext -Recurse -Force -ErrorAction SilentlyContinue
  Expand-Archive $zip -DestinationPath $ext -Force
  Remove-Item $zip
}
Ok "Extension unpacked to $ext"

if (-not (Test-Path "$env:SystemRoot\System32\OpenSSH\ssh.exe")) {
  Write-Host "  [!] Windows OpenSSH client not found: SSH fallback disabled (Reality still works)." -ForegroundColor Yellow
}

Set-Clipboard -Value $ext -ErrorAction SilentlyContinue
Write-Host ""
function Step($n, $t) { Write-Host ""; Write-Host "  [$n] $t" -ForegroundColor DarkYellow; Write-Host "  ------------------------------------------------------------" -ForegroundColor DarkGray }
function Cmd($t)  { Write-Host "      $t" -ForegroundColor Yellow }
function Txt($t)  { Write-Host "      $t" }
function Dim($t)  { Write-Host "      $t" -ForegroundColor DarkGray }

Write-Host ""
Write-Host "  This PC is ready. 3 steps left:" -ForegroundColor Green

Step "1/3" "SERVER: get your wokok:// link"
Txt "You need a VPS outside your country (Ubuntu/Debian, 512 MB RAM, ~`$3/mo)."
Txt "Connect to it over SSH and run ONE command:"
Write-Host ""
Cmd "ssh root@YOUR_SERVER_IP"
Cmd "curl -fsSL https://raw.githubusercontent.com/$Repo/$Branch/server/install.sh | sudo bash"
Write-Host ""
Txt "After ~30 s it prints a link that starts with  wokok://  - copy it."
Dim "Already installed?  Show the link again:   sudo wokok link me"
Dim "Link for a friend:                       sudo wokok add alice"

Step "2/3" "CHROME: load the extension (once)"
Txt "1. Open  chrome://extensions"
Txt "2. Turn on  Developer mode  (top right)"
Txt "3. Click  Load unpacked  and choose:"
Cmd $ext
Dim "(path is already in your clipboard; the folder is opening now)"
Dim "Updating? Just press the reload button on the Wokok card."

Step "3/3" "CONNECT"
Txt "Click the wok icon in Chrome -> paste the wokok:// link -> tap the wok."
Write-Host ""
Write-Host "  Help: https://github.com/$Repo#-quick-start" -ForegroundColor DarkGray
Write-Host ""
Start-Process explorer.exe $ext
