# Wokok VPN native messaging host (Windows, no dependencies).
# Chrome talks to it over stdin/stdout; it runs xray (Reality) or ssh -D (fallback) as a detached process.
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$VERSION = "2.1.7"
$BASE_PORT = 10808   # preferred local SOCKS port; next free one is used if busy
$SOCKS = $BASE_PORT
$D    = Join-Path $env:LOCALAPPDATA "WokokVPN"
$RUN  = Join-Path $D "run"
$XRAY = Join-Path $D "bin\xray.exe"
$SSH  = Join-Path $env:SystemRoot "System32\OpenSSH\ssh.exe"
$CURL = Join-Path $env:SystemRoot "System32\curl.exe"
$STATE = Join-Path $RUN "state.json"
$utf8 = New-Object Text.UTF8Encoding $false
New-Item -ItemType Directory -Force $RUN | Out-Null

function Read-Message {
  $in = [Console]::OpenStandardInput()
  $len = New-Object byte[] 4; $got = 0
  while ($got -lt 4) { $n = $in.Read($len, $got, 4 - $got); if ($n -le 0) { return $null }; $got += $n }
  $size = [BitConverter]::ToInt32($len, 0)
  $buf = New-Object byte[] $size; $got = 0
  while ($got -lt $size) { $n = $in.Read($buf, $got, $size - $got); if ($n -le 0) { break }; $got += $n }
  return ($utf8.GetString($buf, 0, $got) | ConvertFrom-Json)
}

function Send-Message($obj) {
  $bytes = $utf8.GetBytes(($obj | ConvertTo-Json -Depth 8 -Compress))
  $out = [Console]::OpenStandardOutput()
  $out.Write([BitConverter]::GetBytes([int]$bytes.Length), 0, 4)
  $out.Write($bytes, 0, $bytes.Length)
  $out.Flush()
}

function Get-State { try { Get-Content $STATE -Raw | ConvertFrom-Json } catch { $null } }
$st0 = Get-State; if ($st0 -and $st0.port) { $SOCKS = [int]$st0.port }

# True if nothing listens on 127.0.0.1:$p (we try to bind it ourselves).
function Test-Free($p) {
  $l = New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Loopback), $p
  try { $l.Start(); $true } catch { $false } finally { try { $l.Stop() } catch {} }
}
function Find-FreePort($from) {
  for ($p = $from; $p -lt $from + 50; $p++) { if (Test-Free $p) { return $p } }
  throw "no free local port in $from-$($from + 49)"
}
# Our own xray/ssh left over from a crash or an old state file: safe to kill.
function Stop-Orphans {
  Get-CimInstance Win32_Process -Filter "Name='xray.exe' OR Name='ssh.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*$RUN*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}
function Test-Alive($procId) { if (-not $procId) { return $false }; [bool](Get-Process -Id $procId -ErrorAction SilentlyContinue) }

function Test-Port($h, $p, $ms = 800) {
  $c = New-Object Net.Sockets.TcpClient
  try { $sw = [Diagnostics.Stopwatch]::StartNew(); $ok = $c.ConnectAsync($h, $p).Wait($ms); if ($ok -and $c.Connected) { [int]$sw.ElapsedMilliseconds } else { -1 } }
  catch { -1 } finally { $c.Dispose() }
}

# Proves real internet through the tunnel, not just a local listener.
function Test-Tunnel($timeout = 6) {
  $r = & $CURL -s -o NUL -m $timeout -w "%{http_code} %{time_total}" --socks5-hostname "127.0.0.1:$SOCKS" "http://www.gstatic.com/generate_204" 2>$null
  $p = "$r".Split(" ")
  if ($p[0] -eq "204") { return [int]([double]::Parse($p[1], [Globalization.CultureInfo]::InvariantCulture) * 1000) }
  return -1
}

function Start-Detached($cmdLine) {
  # Via WMI so the process lives outside Chrome's job object and survives the host exiting.
  $si = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ ShowWindow = [uint16]0 }
  $r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $cmdLine; CurrentDirectory = $RUN; ProcessStartupInformation = $si }
  return [int]$r.ProcessId
}

function Stop-Tunnel {
  $s = Get-State
  if ($s -and (Test-Alive $s.pid)) { Stop-Process -Id $s.pid -Force -ErrorAction SilentlyContinue }
  Remove-Item $STATE -ErrorAction SilentlyContinue
}

function Wait-Up($procId) {
  for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Milliseconds 300
    if (-not (Test-Alive $procId)) { return -1 }
    if ((Test-Port "127.0.0.1" $SOCKS 300) -ge 0) { return (Test-Tunnel 6) }
  }
  return -1
}

function Start-Reality($s) {
  if (-not (Test-Path $XRAY)) { throw "xray.exe not found - rerun the installer" }
  if ((Test-Port $s.host ([int]$s.port) 3500) -lt 0) { throw "server port $($s.port) is unreachable: open TCP $($s.port) in your VPS firewall/provider panel, or check that Xray runs (sudo wokok status)" }
  $cfg = @{
    log = @{ loglevel = "warning"; error = (Join-Path $RUN "xray.log") }
    inbounds = @(@{ listen = "127.0.0.1"; port = $SOCKS; protocol = "socks"; settings = @{ udp = $true }
      sniffing = @{ enabled = $true; destOverride = @("http", "tls", "quic"); routeOnly = $true } })
    outbounds = @(@{ protocol = "vless"
      settings = @{ vnext = @(@{ address = $s.host; port = [int]$s.port; users = @(@{ id = $s.id; encryption = "none"; flow = "xtls-rprx-vision" }) }) }
      streamSettings = @{ network = "tcp"; security = "reality"
        realitySettings = @{ serverName = $s.sni; fingerprint = "chrome"; publicKey = $s.pbk; shortId = "$($s.sid)"; spiderX = "" } } })
  }
  $path = Join-Path $RUN "xray.json"
  [IO.File]::WriteAllText($path, ($cfg | ConvertTo-Json -Depth 10), $utf8)
  $procId = Start-Detached "`"$XRAY`" run -c `"$path`""
  return @{ pid = $procId; ms = (Wait-Up $procId) }
}

function Start-Ssh($s) {
  if (-not $s.ssh) { throw "no SSH fallback in this link" }
  if (-not (Test-Path $SSH)) { throw "Windows OpenSSH client is missing" }
  if ((Test-Port $s.host ([int]$s.ssh.port) 3500) -lt 0) { throw "SSH port $($s.ssh.port) is unreachable (check the real SSH port of your server)" }
  $key = Join-Path $RUN "ssh_key"
  [IO.File]::WriteAllBytes($key, [Convert]::FromBase64String($s.ssh.key))
  & icacls.exe $key /inheritance:r /grant:r "$($env:USERNAME):F" 2>&1 | Out-Null
  $known = Join-Path $D "known_hosts"
  $a = @("-i", "`"$key`"", "-N", "-T", "-D", "127.0.0.1:$SOCKS", "-p", $s.ssh.port,
    "-o", "IdentitiesOnly=yes", "-o", "BatchMode=yes", "-o", "ExitOnForwardFailure=yes",
    "-o", "ServerAliveInterval=20", "-o", "ServerAliveCountMax=3", "-o", "StrictHostKeyChecking=accept-new",
    "-o", "UserKnownHostsFile=`"$known`"", "-E", "`"$(Join-Path $RUN 'ssh.log')`"", "$($s.ssh.user)@$($s.host)")
  $procId = Start-Detached ("`"$SSH`" " + ($a -join " "))
  return @{ pid = $procId; ms = (Wait-Up $procId) }
}

function Connect($s, $prefer) {
  Stop-Tunnel
  Stop-Orphans
  Start-Sleep -Milliseconds 200
  try { $script:SOCKS = Find-FreePort $BASE_PORT } catch { return @{ ok = $false; error = $_.Exception.Message } }
  $order = switch ($prefer) { "ssh" { @("ssh") } "reality" { @("reality") } default { @("reality", "ssh") } }
  $errors = @()
  foreach ($mode in $order) {
    try {
      $r = if ($mode -eq "reality") { Start-Reality $s } else { Start-Ssh $s }
      if ($r.ms -ge 0) {
        @{ pid = $r.pid; mode = $mode; since = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(); server = $s.host; port = $SOCKS } | ConvertTo-Json | Set-Content $STATE -Encoding utf8
        return @{ ok = $true; connected = $true; mode = $mode; socksPort = $SOCKS; ping = $r.ms }
      }
      if (Test-Alive $r.pid) { Stop-Process -Id $r.pid -Force -ErrorAction SilentlyContinue }
      $errors += "$($mode): connected, but no internet through the tunnel (wrong keys, SNI or server time?)"
    } catch { $errors += "$($mode): $($_.Exception.Message)" }
  }
  return @{ ok = $false; connected = $false; error = ($errors -join "; ") }
}

function Status {
  $s = Get-State
  $up = $s -and (Test-Alive $s.pid) -and ((Test-Port "127.0.0.1" $SOCKS 400) -ge 0)
  return @{ ok = $true; connected = [bool]$up; mode = $(if ($up) { $s.mode } else { $null }); socksPort = $SOCKS; version = $VERSION; platform = "windows" }
}

function Info {
  $ms = Test-Tunnel 6
  if ($ms -lt 0) { return @{ ok = $false; error = "tunnel is not answering" } }
  $j = & $CURL -s -m 8 --socks5-hostname "127.0.0.1:$SOCKS" "https://ipwho.is/" 2>$null | ConvertFrom-Json
  return @{ ok = $true; ping = $ms; ip = $j.ip; country = $j.country; cc = $j.country_code; city = $j.city; isp = $j.connection.isp }
}

function Speed {
  $r = & $CURL -s -o NUL -m 20 -w "%{speed_download}" --socks5-hostname "127.0.0.1:$SOCKS" "https://speed.cloudflare.com/__down?bytes=25000000" 2>$null
  $bps = [double]::Parse("0$r", [Globalization.CultureInfo]::InvariantCulture)
  return @{ ok = ($bps -gt 0); mbps = [math]::Round($bps * 8 / 1e6, 1) }
}

function Ping($targets) {
  $res = @()
  foreach ($t in $targets) { $res += @{ id = $t.id; ms = (Test-Port $t.host ([int]$t.port) 2000) } }
  return @{ ok = $true; results = $res }
}

try {
  $m = Read-Message
  $reply = switch ($m.cmd) {
    "connect"    { Connect $m.server $m.prefer }
    "disconnect" { Stop-Tunnel; @{ ok = $true; connected = $false } }
    "info"       { Info }
    "speed"      { Speed }
    "ping"       { Ping $m.targets }
    default      { Status }
  }
  Send-Message $reply
} catch {
  Send-Message @{ ok = $false; error = $_.Exception.Message }
}
