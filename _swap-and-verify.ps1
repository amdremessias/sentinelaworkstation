$ErrorActionPreference = 'Stop'
$Root = 'C:\ProgramData\HomelabScreenCamera'

# --- 1a) Identifica o python real da venv ---
$py = Join-Path $Root 'python\venv\Scripts\python.exe'
if (-not (Test-Path $py)) {
    $c = Get-ChildItem (Join-Path $Root 'python') -Recurse -Filter 'python.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { $py = $c.FullName }
}
if (-not (Test-Path $py)) { Write-Output 'PY-NOT-FOUND'; exit 2 }
Write-Output ('py=' + $py)

# --- 1b) Acha o tracker/helper ANTIGO que esta dono da :8554 (o relay puro) e mata SÓ ele ---
Write-Output '=== 1) matando o relay antigo puro :8554 (deixa bridge e mtx intactos) ==='
$list = Get-NetTCPConnection -State Listen -LocalPort 8554 -ErrorAction SilentlyContinue | Select-Object -First 1
if ($list) {
    $pid8554 = $list.OwningProcess
    Write-Output ('  listener pid=' + $pid8554)
    Get-CimInstance Win32_Process -Filter ('ProcessId=' + $pid8554) -ErrorAction SilentlyContinue |
        ForEach-Object { Write-Output ('  cmd=' + $_.CommandLine) }
    Stop-Process -Id $pid8554 -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
} else {
    Write-Output '  (nenhum listener :8554 - subindo direto)'
}

# --- 2) Sobe o helper CORRETO com OPTIONS-200-local na :8554 ---
$helper = Join-Path $Root 'rtsp-http-helper.py'
$logf = Join-Path $Root '_dial-8554-new.log'
Write-Output '=== 2) subindo helper OPTIONS-200-local na :8554 -> :8556 ==='
$h = Start-Process -FilePath $py `
    -ArgumentList @($helper, '0.0.0.0:8554', '127.0.0.1:8556', $logf) `
    -WorkingDirectory $Root `
    -RedirectStandardOutput (Join-Path $Root '_help-out.log') `
    -RedirectStandardError (Join-Path $Root '_help-err.log') `
    -PassThru
Start-Sleep -Seconds 4

Write-Output '=== 3) DONO da :8554 agora (deve ser o helper NOVO) ==='
$l2 = Get-NetTCPConnection -State Listen -LocalPort 8554 -ErrorAction SilentlyContinue | Select-Object -First 1
if ($l2) {
    Get-CimInstance Win32_Process -Filter ('ProcessId=' + $l2.OwningProcess) -ErrorAction SilentlyContinue |
        ForEach-Object { Write-Output ('  pid=' + $l2.OwningProcess + ' cmd=' + $_.CommandLine) }
} else { Write-Output '  SEM LISTENER :8554!' }

Write-Output '=== 4) teste OPTIONS anonimo via LAN-IP (exatamente como o DVR faz) - resposta CRUA ==='
$c = New-Object Net.Sockets.TcpClient
try {
    $c.Connect('192.168.5.54', 8554)
    $c.Client.ReceiveTimeout = 5000
    $s = $c.GetStream()
    $o = [Text.Encoding]::ASCII.GetBytes("OPTIONS rtsp://192.168.5.54:8554/desktop RTSP/1.0`r`nCSeq: 9`r`n`r`n")
    $s.Write($o, 0, $o.Length)
    $s.Flush()
    Start-Sleep -Milliseconds 900
    $b = New-Object byte[] 2048
    $n = $s.Read($b, 0, $b.Length)
    Write-Output ([Text.Encoding]::ASCII.GetString($b, 0, $n))
} catch {
    Write-Output ('  ERR ' + $_.Exception.Message)
} finally {
    try { $c.Close() } catch {}
}

Write-Output '=== 5) MediaMTX: sessoes de leitura recentes (esta havendo leitura real TCP?) ==='
Get-Content (Join-Path $Root 'mediamtx.log') -ErrorAction SilentlyContinue |
    Select-String -Pattern 'is reading from path' | Select-Object -Last 3 |
    ForEach-Object Line
