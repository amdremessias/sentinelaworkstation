$ErrorActionPreference = 'Continue'
$Root = 'C:\ProgramData\HomelabScreenCamera'
$Root = 'C:\ProgramData\HomelabScreenCamera'
$py = Join-Path $Root 'python\venv\Scripts\python.exe'
if (-not (Test-Path $py)) {
    $p = Get-Command python -ErrorAction SilentlyContinue
    if ($p) { $py = $p.Source } else {
        $cand = Get-ChildItem (Join-Path $Root 'python') -Recurse -Filter 'python.exe' -ErrorAction SilentlyContinue
        if ($cand) { $py = $cand[0].FullName }
    }
}
if (-not $py) { Write-Output 'PY-NOT-FOUND'; exit 2 }
Write-Output ('py=' + $py)

Write-Output '=== 1) matar SOMENTE o relay puro :8554 (O ANTIGO que devolve 401 no OPTIONS) ==='
Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match '_dial-spy|dial-spy' } |
    ForEach-Object {
        Write-Output ('  kill pid=' + $_.ProcessId)
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
Start-Sleep -Seconds 2

Write-Output '=== 2) subir o helper CORRETO (OPTIONS->200-local) na :8554 ==='
$logf = Join-Path $Root '_dial-8554-helper.log'
$h = Start-Process -FilePath $py `
    -ArgumentList @((Join-Path $Root 'rtsp-http-helper.py'), '0.0.0.0:8554', '127.0.0.1:8556', $logf) `
    -WorkingDirectory $Root `
    -RedirectStandardOutput (Join-Path $Root '_h-out.log') `
    -RedirectStandardError (Join-Path $Root '_h-err.log') `
    -PassThru
Start-Sleep -Seconds 5

Write-Output '=== 3) listeners :8000/:8554/:8556 ==='
Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
    Where-Object { $_.LocalPort -in 8000, 8554, 8556 } |
    Select-Object LocalAddress, LocalPort, OwningProcess |
    Sort-Object LocalPort | Format-Table -AutoSize

Write-Output '=== 4) bridge via LAN-IP (o DVR vê assim) ==='
try {
    $b = Invoke-WebRequest 'http://192.168.5.54:8000/health' -UseBasicParsing -TimeoutSec 8
    Write-Output ('  LAN /health -> ' + [int]$b.StatusCode + ' ' + $b.Content)
} catch {
    Write-Output ('  LAN /health ERR ' + $_.Exception.Message)
}

Write-Output '=== 5) teste OPTIONS anônimo estilo-DVR (helper responde 200? NAO deve ser 401) ==='
try {
    $c = New-Object Net.Sockets.TcpClient
    $c.Connect('192.168.5.54', 8554)
    $s = $c.GetStream()
    $o = [System.Text.Encoding]::ASCII.GetBytes("OPTIONS rtsp://192.168.5.54:8554/desktop RTSP/1.0`r`nCSeq: 1`r`n`r`n")
    $s.Write($o, 0, $o.Length)
    $s.Flush()
    Start-Sleep -Milliseconds 800
    $buf = New-Object byte[] 1024
    $n = $s.Read($buf, 0, $buf.Length)
    Write-Output ([System.Text.Encoding]::ASCII.GetString($buf, 0, $n))
    $c.Close()
} catch {
    Write-Output ('  OPTIONS-test ERR ' + $_.Exception.Message)
}

Write-Output '=== 6) ultimas linhas do log do helper ==='
Get-Content $logf -ErrorAction SilentlyContinue | Select-Object -Last 8
