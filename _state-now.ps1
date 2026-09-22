$Root = 'C:\ProgramData\HomelabScreenCamera'
$out = Join-Path $Root '_state-now.txt'
Function W($m){ Add-Content -Path $out -Value $m; Write-Output $m }

W ('=== estado ' + (Get-Date) + ' ===')
W '--- 1) listeners: 8000 (bridge) | 8554 (helper) | 8556 (mtx-interno) | 8554-pub? ---'
foreach ($port in 8000,8554,8556) {
  $l = Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($l) {
    W ("  :" + $port + " -> pid=" + $l.OwningProcess)
    $p = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $l.OwningProcess) -ErrorAction SilentlyContinue
    if ($p) { W ("     cmd=" + $p.CommandLine) }
  } else {
    W ("  :" + $port + " -> SEM LISTENER!")
  }
}

W '--- 2) bridge /health via LAN (o que da o VERDE) ---'
try {
  $r = Invoke-WebRequest -Uri 'http://192.168.5.54:8000/health' -TimeoutSec 4 -UseBasicParsing -ErrorAction Stop
  W ("  /health -> " + [int]$r.StatusCode + " " + $r.Content)
} catch { W ('  /health -> ERR ' + $_.Exception.Message) }

W '--- 3) mediaMTX ativo? publisher ainda publica desktop? ---'
$mt = Get-Process mediamtx -ErrorAction SilentlyContinue | Select-Object -First 1
if ($mt) { W ('  mediamtx pid=' + $mt.Id + ' started=' + $mt.StartTime) } else { W '  mediamtx: NAO RODANDO!' }
$pub = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'ffmpeg' -and $_.CommandLine -match '8556|desktop' } | Select-Object -First 3
if ($pub) { foreach($p in $pub){ W ('  ffmpeg pid=' + $p.ProcessId + ' started=' + $(if($p.CreationDate){$p.CreationDate}) + ' cmd=' + $p.CommandLine.Substring(0,[Math]::Min(120,$p.CommandLine.Length))) } }
else { W '  ffmpeg publisher: NENHUM com 8556/desktop!' }

W '--- 4) ultimas CONN da :8554 (helper novo) ---'
$logf = Join-Path $Root '_dial-8554.newer.log'
if (Test-Path $logf) { Get-Content $logf | Select-Object -Last 12 | ForEach-Object { W ('  ' + $_) } } else { W '  sem log newer' }

W '--- 5) ultimas linhas mediaMTX (sessao desktop?) ---'
$mtxl = Get-ChildItem (Join-Path $Root 'media') -Filter '*.log' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($mtxl) { Get-Content $mtxl.FullName -ErrorAction SilentlyContinue | Select-Object -Last 8 | ForEach-Object { W ('  [mtx] ' + $_) } }
$rw = Get-ChildItem (Join-Path $Root) -Filter '*mediamtx*.log' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($rw) { Get-Content $rw.FullName -ErrorAction SilentlyContinue | Select-Object -Last 8 | ForEach-Object { W ('  [mtx-run] ' + $_) } }
