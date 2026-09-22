$ErrorActionPreference = 'Continue'
$Root = 'C:\ProgramData\HomelabScreenCamera'

Write-Output '=== 1) dono da :8554 agora (TEM que ser rtsp-http-helper.py = OPTIONS-200-local) ==='
$l = Get-NetTCPConnection -State Listen -LocalPort 8554 -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $l) { Write-Output '  NAO HA listener :8554! (helper morto)'; exit 2 }
$p = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $l.OwningProcess) -ErrorAction SilentlyContinue
Write-Output ('  pid=' + $l.OwningProcess)
if ($p) { Write-Output ('  cmd=' + $p.CommandLine) }
if ($p.CommandLine -match 'rtsp-http-helper') { Write-Output '  -> helper CORRETO (OPTIONS-200-local) OK' }
elseif ($p.CommandLine -match 'dial-spy|_dial') { Write-Output '  -> AINDA E O RELAY PURO/SPY ANTIGO - TROCA NAO EFETIVOU' }
else { Write-Output '  -> OUTRO processo, verificar' }
Write-Output ''

Write-Output '=== 2) OPTIONS anonimo via LAN-IP 192.168.5.54:8554 (exatamente como o DVR faz) - o DVR recebe 200 ou 401? ==='
$tcp = New-Object Net.Sockets.TcpClient
$resp = ''
try {
    $tcp.Connect('192.168.5.54', 8554)
    $tcp.ReceiveTimeout = 4000
    $s = $tcp.GetStream()
    $o = [Text.Encoding]::ASCII.GetBytes("OPTIONS rtsp://192.168.5.54:8554/desktop RTSP/1.0`r`nCSeq: 1`r`n`r`n")
    $s.Write($o, 0, $o.Length)
    $s.Flush()
    Start-Sleep -Milliseconds 800
    $buf = New-Object byte[] 1024
    $n = 0
    try { $n = $s.Read($buf, 0, $buf.Length) } catch {}
    $resp = [Text.Encoding]::ASCII.GetString($buf, 0, $n)
    Write-Output $resp
    if ($resp -match '401') { Write-Output '  !! 401 -> helper AINDA relayando OPTIONS pro MTX (auth on) -> DVR trava. TROCA NAO EFETIVOU.' }
    elseif ($resp -match '200 OK') { Write-Output '  -> 200 OK local. Regra Intelbras correta ATIVA. O DVR deveria destravar pro DESCRIBE agora.' }
} catch {
    Write-Output ('  ERR ' + $_.Exception.Message)
} finally {
    try { $tcp.Close() } catch {}
}