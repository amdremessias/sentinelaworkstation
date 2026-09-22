$ErrorActionPreference = 'Continue'
$Root = 'C:\ProgramData\HomelabScreenCamera'

Write-Output '=== 1) dono do listener :8554 (deve ser o helper NOVO c/ OPTIONS->200-local) ==='
try {
    $l = Get-NetTCPConnection -State Listen -LocalPort 8554 -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $l) { Write-Output '  FALHA: sem listener :8554'; exit 2 }
    $op = $l.OwningProcess
    $proc = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $op) -ErrorAction SilentlyContinue
    Write-Output ('  pid=' + $op)
    Write-Output ('  cmd=' + $proc.CommandLine)
    if ($proc.CommandLine -match 'rtsp-http-helper.py') { Write-Output '  -> e o helper NOVO OK (OPTIONS-200-local)' }
    elseif ($proc.CommandLine -match '_dial-spy') { Write-Output '  -> ALERTA: e o relay puro antigo (_dial-spy) - TROCA NAO VALEU' }
    else { Write-Output '  -> outro processo, conferir' }
} catch { Write-Output ('  ERR ' + $_.Exception.Message) }

Write-Output ''
Write-Output '=== 2) teste vivo byte-a-byte: OPTIONS anonimo estilo-DVR p/ 192.168.5.54:8554 (o que o DVR faz de verdade) ==='
$tcp = New-Object Net.Sockets.TcpClient
try {
    $tcp.Connect('192.168.5.54', 8554)
    $tcp.ReceiveTimeout = 5000
    $s = $tcp.GetStream()
    $req = [Text.Encoding]::ASCII.GetBytes("OPTIONS rtsp://192.168.5.54:8554/desktop RTSP/1.0`r`nCSeq: 99`r`n`r`n")
    $s.Write($req, 0, $req.Length)
    $s.Flush()
    Start-Sleep -Milliseconds 900
    $buf = New-Object byte[] 2048
    $n = $s.Read($buf, 0, $buf.Length)
    $resp = [Text.Encoding]::ASCII.GetString($buf, 0, $n)
    Write-Output $resp
    if ($resp -match '401') { Write-Output '  RESULTADO: 401 -> DVR vai travar (algm respondeu 401 - problema real)  <<<<' }
    elseif ($resp -match '200') { Write-Output '  RESULTADO: 200 OK local -> DVR deveria avancar p/ DESCRIBE  >>>>' }
} catch { Write-Output ('  ERR ' + $_.Exception.Message) }
try { $tcp.Close() } catch {}

Write-Output ''
Write-Output '=== 3) MediaMTX registrou sessao de LIDA real do DVR agora (o DVR mandou DESCRIBE/SETUP/PLAY)? ==='
Get-Content (Join-Path $Root '_mtx-out.log') -ErrorAction SilentlyContinue |
    Select-String -Pattern "is reading from path 'desktop'" | Select-Object -Last 6 |
    ForEach-Object Line

Write-Output ''
Write-Output '=== 4) origem do dialogo no spy (o DVR chegou a mandar DESCRIBE?) ==='
Get-Content (Join-Path $Root '_dial-8554.log') -ErrorAction SilentlyContinue |
    Select-String -Pattern 'DESCRIBE|SETUP|PLAY|OPTIONS' | Select-Object -Last 10 |
    ForEach-Object Line