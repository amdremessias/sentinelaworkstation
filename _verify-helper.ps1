$ErrorActionPreference = 'Continue'
$Root = 'C:\ProgramData\HomelabScreenCamera'
# 1) quem escuta :8554 agora + cmdline do dono (tem que ser o helper c/ OPTIONS-200 local)
Write-Output '=== 1) dono da :8554 (tem que ser rtsp-http-helper.py, NAO dial-spy/relay puro) ==='
$l = Get-NetTCPConnection -State Listen -LocalPort 8554 -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $l) { Write-Output '  NAO HA listener :8554!' } else {
    Write-Output ('  pid=' + $l.OwningProcess)
    $p = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $l.OwningProcess) -ErrorAction SilentlyContinue
    Write-Output ('  cmd=' + $p.CommandLine)
    if ($p.CommandLine -match 'rtsp-http-helper') { Write-Output '  -> helper CORRETO (OPTIONS-200-local) OK' }
    elseif ($p.CommandLine -match 'dial-spy') { Write-Output '  -> EH O RELAY PURO ANTIGO! precisa trocar' }
    else { Write-Output '  -> outro processo' }
}
Write-Output ''
# 2) teste OPTIONS anonimo EXATAMENTE como o DVR faz: via LAN-IP 192.168.5.54:8554, sem credencial
Write-Output '=== 2) OPTIONS anonimo via LAN-IP (:8554), como o DVR ==='
$tcp = New-Object Net.Sockets.TcpClient
try {
    $tcp.Connect('192.168.5.54', 8554)
    $tcp.ReceiveTimeout = 4000
    $s = $tcp.GetStream()
    $o = [Text.Encoding]::ASCII.GetBytes("OPTIONS rtsp://192.168.5.54:8554/desktop RTSP/1.0`r`nCSeq: 1`r`n`r`n")
    $s.Write($o, 0, $o.Length)
    $s.Flush()
    Start-Sleep -Milliseconds 700
    $buf = New-Object byte[] 2048
    $n = 0
    try { $n = $s.Read($buf, 0, $buf.Length) } catch {}
    $resp = [Text.Encoding]::ASCII.GetString($buf, 0, $n)
    Write-Output $resp
    if ($resp -match '401') { Write-Output '  !! 401 -> DVR vai travar (auth challenge) - helper ERRADO' }
    elseif ($resp -match '200') { Write-Output '  -> 200 OK local - correto p/ Intelbras' }
} catch {
    Write-Output ('  ERR ' + $_.Exception.Message)
} finally {
    try { $tcp.Close() } catch {}
}
Write-Output ''
# 3) ultimas linhas do log do helper (o dialogo do DVR depois da troca)
Write-Output '=== 3) log helper : ultimas 8 linhas ==='
Get-Content (Join-Path $Root '_dial-8554-helper.log') -ErrorAction SilentlyContinue | Select-Object -Last 8 | ForEach-Object { Write-Output ('  ' + $_) }
Write-Output ''
# 4) MediaMTX: sessao de leitura TCP criada para o DVR? (com TCP = video atravessou)
Write-Output '=== 4) MTX: sessoes de leitura (alguem leu video de verdade, com TCP) ==='
Get-Content (Join-Path $Root '_mtx-out.log') -ErrorAction SilentlyContinue | Select-String -Pattern 'is reading from path' | Select-Object -Last 4 | ForEach-Object Line
