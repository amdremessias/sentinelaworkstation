$Root = 'C:\ProgramData\HomelabScreenCamera'
$out = Join-Path $Root '_swap-verify-cseq.txt'
Function W($m){ Add-Content -Path $out -Value $m; Write-Output $m }
$helperf = Join-Path $Root 'rtsp-http-helper.py'
$py = Join-Path $Root 'python\venv\Scripts\python.exe'
if (-not (Test-Path $py)) { $py = (Get-Command python).Source }

W ('=== swap helper CSeq-echo + KEEPALIVE  |  inicio=' + (Get-Date) + ' ===')
$l = Get-NetTCPConnection -State Listen -LocalPort 8554 -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $l) { W '  SEM LISTENER :8554!'; exit 1 }
$op = $l.OwningProcess
$p = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $op) -ErrorAction SilentlyContinue
W ('  dono-atual :8554 pid=' + $op)
W ('    cmd=' + $p.CommandLine)
W ('    iniciou=' + $p.CreationDate)
W ('  helper-disk mtime=' + (Get-Item $helperf).LastWriteTime)

W '--- matando SOLO o dono da :8554 ---'
Stop-Process -Id $op -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

W '--- subindo helper NOVO (CSeq-echo + KEEPALIVE) na :8554 ---'
$logf = Join-Path $Root '_dial-8554.keepalive2.log'
$h = Start-Process -FilePath $py -ArgumentList @($helperf,'0.0.0.0:8554','127.0.0.1:8556',$logf) -WorkingDirectory $Root -RedirectStandardOutput (Join-Path $Root '_h-k2-out.log') -RedirectStandardError (Join-Path $Root '_h-k2-err.log') -PassThru
Start-Sleep -Seconds 4

$l2 = Get-NetTCPConnection -State Listen -LocalPort 8554 -ErrorAction SilentlyContinue | Select-Object -First 1
W ('  dono-NOVO :8554 pid=' + $(if($l2){$l2.OwningProcess}else{'NENHUM'}))
$p2 = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $(if($l2){$l2.OwningProcess}else{'0'})) -ErrorAction SilentlyContinue
if ($p2) { W ('    cmd=' + $p2.CommandLine) }

W '=== teste OPTIONS anonimo estilo-DVR (CSeq: 9 - nao-trivial) ==='
try {
  $tcp = New-Object Net.Sockets.TcpClient
  $tcp.Connect('127.0.0.1', 8554)
  $tcp.ReceiveTimeout = 8000
  $s = $tcp.GetStream()
  $opt = [Text.Encoding]::ASCII.GetBytes("OPTIONS rtsp://192.168.5.54:8554/desktop RTSP/1.0`r`nCSeq: 9`r`n`r`n")
  $s.Write($opt,0,$opt.Length); $s.Flush()
  $buf = New-Object byte[] 1024
  $n = $s.Read($buf,0,$buf.Length)
  $resp = [Text.Encoding]::ASCII.GetString($buf,0,$n)
  W ('  resp=' + ($resp -replace "`r`n",' | '))
  if ($resp -match 'CSeq: 9') { W '  -> 200 com CSeq: 9 ecoado: DVR deveria correlacionar e seguir para DESCRIBE!' }
  elseif ($resp -match 'CSeq: 1') { W '  -> ATENCAO: CSeq: 1 fixo (AINDA O BUG DO LOOP)!' }
  elseif ($resp -match '401') { W '  -> 401!' }
}
catch { W ('  ERR ' + $_.Exception.Message) }

W '--- log helper novo (ultimas linhas) ---'
if (Test-Path $logf) { Get-Content $logf | Select-Object -Last 8 | ForEach-Object { W ('  ' + $_) } }
W ('=== FIM swap-verify-cseq ' + (Get-Date) + ' ===')
