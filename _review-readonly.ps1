$Root = 'C:\ProgramData\HomelabScreenCamera'
$out = Join-Path $Root '_review-readonly.log'
Function W($m){ Add-Content -Path $out -Value $m; Write-Output $m }

W ('=== REVISAO READ-ONLY | ' + (Get-Date) + ' ===')

# ---------- 1) HELPER :8554 (keepalive2) — DVR connections ----------
W '--- [1] helper :8554 keepalive2 ---'
$kl = Get-ChildItem $Root -Filter '*8554*keepalive*.log' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
foreach ($f in $kl | Select-Object -First 3) {
  W ('  [' + $f.Name + ' | ' + $f.LastWriteTime + ']')
  $c = @(Get-Content $f.FullName -ErrorAction SilentlyContinue)
  W ('    lines=' + $c.Count)
  $dvr = @($c | Where-Object { $_ -match '192\.168\.5\.31' })
  W ('    do-DVR=' + $dvr.Count)
  # tipos de primeiro-request
  $opt = @($dvr | Where-Object { $_ -match 'OPTIONS' }).Count
  $desc = @($dvr | Where-Object { $_ -match 'DESCRIBE' }).Count
  $relay = @($dvr | Where-Object { $_ -match 'relay|-> forward|-> relay' }).Count
  W ('    OPTIONS=' + $opt + '  DESCRIBE=' + $desc + '  relay/forward=' + $relay)
  W '    ultimas do-DVR:'
  $dvr | Select-Object -Last 8 | ForEach-Object { W ('      ' + $_) }
  # timestamps: primeira e ultima
  if ($dvr.Count -gt 0) {
    $ts = $dvr -replace '^\[([0-9:.]+)\].*','$1'
    W ('    janela: ' + ($ts | Select-Object -First 1) + ' -> ' + ($ts | Select-Object -Last 1))
  }
}

# ---------- 2) MediaMTX :8556 — recebeu algo do helper? stream vivo? ----------
W '--- [2] MediaMTX log ---'
$mx = Get-ChildItem 'C:\ProgramData\HomelabScreenCamera' -Filter 'mediamtx*.log' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($mx) {
  W ('  [' + $mx.Name + ' | ' + $mx.LastWriteTime + ']')
  $c = @(Get-Content $mx.FullName -ErrorAction SilentlyContinue)
  W ('    lines=' + $c.Count)
  # procurar sessões de leitura do DVR vindo do relay (127.0.0.1) recentes
  $read = @($c | Where-Object { $_ -match 'is reading from path' })
  W ('    "is reading from path" total=' + $read.Count)
  $read | Select-Object -Last 6 | ForEach-Object { W ('      ' + $_) }
  $pubs = @($c | Where-Object { $_ -match 'publishing|publisher connected|is publishing' })
  W ('    publisher/publishing lines=' + $pubs.Count)
  $pubs | Select-Object -Last 4 | ForEach-Object { W ('      ' + $_) }
  W '    ultimas 14:'
  $c | Select-Object -Last 14 | ForEach-Object { W ('      ' + $_) }
} else { W '  SEM log mediamtx' }

# ---------- 3) publisher ffmpeg + processo ----------
W '--- [3] processos ---'
$ff = Get-CimInstance Win32_Process -Filter "Name='ffmpeg.exe'" -ErrorAction SilentlyContinue
if ($ff) {
  W ('  ffmpeg pid=' + $ff.ProcessId)
  W ('    cmd=' + $ff.CommandLine.Substring(0, [Math]::Min(220, $ff.CommandLine.Length)))
} else { W '  SEM ffmpeg (publisher MORTO!)' }
foreach ($n in 'mediamtx','rtsp-http-helper') {
  $p = Get-CimInstance Win32_Process -Filter "Name LIKE '%$n%'" -ErrorAction SilentlyContinue
  if ($p) { $p | ForEach-Object { W ('  ' + $n + ' pid=' + $_.ProcessId + ' cmd=' + (($_.CommandLine) -split ' ')[0]) } }
  else { W ('  SEM processo ' + $n) }
}

# ---------- 4) listeners ----------
W '--- [4] listeners ---'
foreach ($port in 8000,8554,8556,9997) {
  $l = Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($l) {
    $p = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $l.OwningProcess) -ErrorAction SilentlyContinue
    W ('  :' + $port + ' pid=' + $l.OwningProcess)
    if ($p) { $n = $p.Name; if ($p.CommandLine) { $n = (($p.CommandLine -split ' ')[0] -split '\\\\')[-1] }; W ('    ' + $n) }
  } else { W ('  :' + $port + ' SEM LISTENER') }
}

# ---------- 5) bridge :8000 health ----------
W '--- [5] bridge health ---'
try {
  $h = Invoke-WebRequest -Uri 'http://192.168.5.54:8000/health' -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
  W ('  /health=' + $h.StatusCode + ' body=' + $h.Content)
} catch { W ('  /health ERRO: ' + $_.Exception.Message) }

W ('=== FIM ' + (Get-Date) + ' ===')
