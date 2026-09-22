$Root='C:\ProgramData\HomelabScreenCamera'
$ff=(Get-Command ffmpeg -ErrorAction SilentlyContinue).Source

Write-Output ('=== rtsp-debug read-only ovifadm | ' + (Get-Date) + ' ===')

Write-Output '--- 1) ffmpeg verbose DESCRIBE interno :8556 ovifadm (texto do erro, nao so exit) ---'
& $ff -hide_banner -loglevel debug -rtsp_transport tcp -stimeout 12000000 -i 'rtsp://ovifadm:change-onvif-password@127.0.0.1:8556/desktop' -frames:v 1 -f null - 2>&1 | Select-Object -Last 45
Write-Output ('  exit=' + $LASTEXITCODE)
Write-Output ''

Write-Output '--- 2) ffmpeg verbose via helper :8554 ovifadm (o que o DVR faz) ---'
& $ff -hide_banner -loglevel debug -rtsp_transport tcp -stimeout 12000000 -i 'rtsp://ovifadm:change-onvif-password@192.168.5.54:8554/desktop' -frames:v 1 -f null - 2>&1 | Select-Object -Last 45
Write-Output ('  exit=' + $LASTEXITCODE)
Write-Output ''

Write-Output '--- 3) tail _mtx-out.log (publicacao desktop online?) ---'
Get-Content (Join-Path $Root '_mtx-out.log') -Tail 60 -ErrorAction SilentlyContinue | Where-Object { $_ -match 'desktop|publish|online|auth|ERR|WARN' } | Select-Object -Last 30
Write-Output ''

Write-Output '--- 4) tail _pub-err.log (publisher ffmpeg stderr) ---'
Get-Content (Join-Path $Root '_pub-err.log') -Tail 25 -ErrorAction SilentlyContinue
Write-Output ''

Write-Output '--- 5) tail _watchdog.log ---'
Get-Content (Join-Path $Root '_watchdog.log') -Tail 20 -ErrorAction SilentlyContinue
Write-Output ''

Write-Output '--- 6) listener 8556 interno + quem publica ---'
Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object LocalPort -in 8556 | ForEach-Object {
  $p = Get-CimInstance Win32_Process -Filter "ProcessId=$($_.OwningProcess)" -ErrorAction SilentlyContinue
  Write-Output ('  LISTEN ' + $_.LocalAddress + ':' + $_.LocalPort + ' pid=' + $_.OwningProcess + ' ' + $p.Name)
}
Write-Output '--- 7) conexoes RTSP ativas em 8556 (quem le/discute) ---'
Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -in 8556 } | ForEach-Object {
  Write-Output ('  ' + $_.RemoteAddress + ':' + $_.RemotePort + ' -> :8556 pid=' + $_.OwningProcess)
}
Write-Output '=== fim | ' + (Get-Date) + ' ==='
