$ErrorActionPreference = 'Continue'
$Root = 'C:\ProgramData\HomelabScreenCamera'
$out = Join-Path $Root '_swap-verify-results.txt'
Function W($m){ Add-Content -Path $out -Value $m; Write-Output $m }

# === 1) identifica o dono atual de :8554 e sua cmdline (precisa ser o rtsp-http-helper.py NOVO com KEEPALIVE) ===
$l = Get-NetTCPConnection -State Listen -LocalPort 8554 -ErrorAction SilentlyContinue | Select-Object -First 1
W ('=== 1) dono atual :8554 ===')
if (-not $l) { W '  SEM LISTENER :8554!'; exit 1 }
$op = $l.OwningProcess
$proc = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $op) -ErrorAction SilentlyContinue
W ('  pid=' + $op)
W ('  cmd=' + $proc.CommandLine)
$started = $proc.CreationDate

# === 2) a helper file de disco que vamos subir (deve ter KEEPALIVE) tem essa marca? ===
$helperf = Join-Path $Root 'rtsp-http-helper.py'
$mt = (Get-Item $helperf).LastWriteTime
W ('=== 2) helper de disco: mtime=' + $mt + ' hora-atual=' + (Get-Date))

# === 3) mata SOMENTE o dono da :8554 (deixa bridge :8000, mtx :8556, publisher de pe) ===
W '=== 3) matando SOLO o dono da :8554 (nada mais) ==='
if ($proc) { Stop-Process -Id $op -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 2

# === 4) sobe o helper NOVO da disco na :8554 com log proprio ===
$py = Join-Path $Root 'python\venv\Scripts\python.exe'
if (-not (Test-Path $py)) { $py = (Get-Command python).Source }
$logf = Join-Path $Root '_dial-8554.newer.log'
W '=== 4) subindo helper NOVO (OPTIONS-200-local + keepalive + relay rest) ==='
$h = Start-Process -FilePath $py `
    -ArgumentList @($helperf, '0.0.0.0:8554', '127.0.0.1:8556', $logf) `
    -WorkingDirectory $Root `
    -RedirectStandardOutput (Join-Path $Root '_h2-out.log') `
    -RedirectStandardError (Join-Path $Root '_h2-err.log') `
    -PassThru
Start-Sleep -Seconds 4

# === 5) confirma: dono NOVO + teste OPTIONS anonimo byte-por-byte ===
$l2 = Get-NetTCPConnection -State Listen -LocalPort 8554 -ErrorAction SilentlyContinue | Select-Object -First 1
W ('=== 5) dono NOVO :8554 -> pid=' + $(if($l2){$l2.OwningProcess}else{'NENHUM'}))
$p2 = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $(if($l2){$l2.OwningProcess}else{'0'})) -ErrorAction SilentlyContinue
if ($p2) { W ('  cmd=' + $p2.CommandLine) }

W '=== 6) teste OPTIONS anonimo estilo-DVR (exatamente o que o Intelbras manda) ==='
try {
    $tcp = New-Object Net.Sockets.TcpClient
    $tcp.Connect('192.168.5.54', 8554)
    $tcp.ReceiveTimeout = 8000
    $s = $tcp.GetStream()
    $opt = [Text.Encoding]::ASCII.GetBytes("OPTIONS rtsp://192.168.5.54:8554/desktop RTSP/1.0`r`nCSeq: 3`r`n`r`n")
    $s.Write($opt, 0, $opt.Length); $s.Flush()
    $buf = New-Object byte[] 1024
    $n = $s.Read($buf, 0, $buf.Length)
    $resp = [Text.Encoding]::ASCII.GetString($buf, 0, $n)
    W ('  [OPTIONS-resp] ' + $resp.Trim())
    if ($resp -match '200 OK') { W '  -> 200 OK: DVR deveria destravar e seguir pra DESCRIBE' }
    elseif ($resp -match '401') { W '  -> 401! AINDA TRAVADO (helper errado no ar)' }
} catch { W ('  ERR ' + $_.Exception.Message) }

W '=== 7) log do HELPER NOVO: tem CONN do DVR APOS a religada? (viu DESCRIBE?) ==='
Get-Content $logf -ErrorAction SilentlyContinue | Where-Object { $_ -match '192\.168\.5\.31' } | Select-Object -Last 8 | ForEach-Object { W ('  ' + $_) }
