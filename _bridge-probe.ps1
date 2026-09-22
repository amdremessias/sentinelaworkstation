$Root = 'C:\ProgramData\HomelabScreenCamera'
Function W($m){ Add-Content -Path (Join-Path $Root '_bridge-probe.log') -Value $m; Write-Output $m }

W ('=== bridge + tcp 31 durante re-add | ' + (Get-Date) + ' ===')

# 1) quem escuta :8000 (bridge) e :8556 (mtx)
foreach ($port in 8000,8556) {
  $l = Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($l) {
    $p = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $l.OwningProcess) -ErrorAction SilentlyContinue
    W ('  :' + $port + ' pid=' + $l.OwningProcess)
    if ($p) { W ('    cmd=' + $p.CommandLine) }
  } else { W ('  :' + $port + ' SEM LISTENER') }
}

# 2) todo log do bridge (procura .31 e .31:8000)
W '--- logs do bridge: procurando contato 192.168.5.31 ---'
Get-ChildItem $Root -Filter '*bridge*.log' | ForEach-Object {
  W ('  [' + $_.Name + '] (mtime=' + $_.LastWriteTime + ')')
  $mm = Get-Content $_.FullName -ErrorAction SilentlyContinue | Where-Object { $_ -match '192\.168\.5\.31|8000' }
  @($mm) | Select-Object -Last 10 | ForEach-Object { W ('    ' + $_) }
}

# 3) quem teve conexao TCP toda p/ :8000 nos ultimos 15 min (estilo ID do DVR)
W '--- conexoes TCP recentes a :8000 (quem tentou?) ---'
$t0 = (Get-Date).AddMinutes(-15)
Get-NetTCPConnection -State Established -LocalPort 8000 -ErrorAction SilentlyContinue |
  Where-Object { $_.CreationTime -gt $t0 } |
  ForEach-Object { W ('    ' + $_.RemoteAddress + ':' + $_.RemotePort + ' desde ' + $_.CreationTime) }

W ('=== fim bridge-probe ' + (Get-Date) + ' ===')
