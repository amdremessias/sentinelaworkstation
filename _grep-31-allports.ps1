$Root = 'C:\ProgramData\HomelabScreenCamera'
$out = Join-Path $Root '_grep-31-allports.txt'
Function W($m){ Add-Content -Path $out -Value $m; Write-Output $m }

W ('=== grep 192.168.5.31 em todos logs | ' + (Get-Date) + ' ===')

# helper :8554 atual (keepalive2) - ja visto, pulando
# bridge :8000 -> procuramos no log do bridge
$bridgelogs = Get-ChildItem $Root -Filter '*bridge*' -File -ErrorAction SilentlyContinue
W ('--- bridge (logs) ---')
foreach ($f in $bridgelogs) {
  $m = @(Get-Content $f.FullName -ErrorAction SilentlyContinue | Where-Object { $_ -match '192\.168\.5\.31' })
  W ('  [' + $f.Name + '] m=0x31=' + $m.Count)
  if ($m.Count -gt 0) { $m | Select-Object -Last 6 | ForEach-Object { W ('    ' + $_) } }
}

# MediaMTX :8556 - log
W '--- mediamtx (log) ultimas 30 ---'
$mtx = Get-ChildItem $Root -Include '*.log' -File -Recurse -Depth 2 -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'mediamtx|mtx' } | Select-Object -First 3
foreach ($f in $mtx) {
  W ('  [' + $f.FullName + ']')
  Get-Content $f.FullName -ErrorAction SilentlyContinue | Select-Object -Last 30 | ForEach-Object { W ('    ' + $_) }
}

# quem esta escutando :8000 e :8556 agora
W '--- listeners :8000 :8556 :8554 ---'
foreach ($port in 8000,8556,8554) {
  $l = Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($l) {
    $p = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $l.OwningProcess) -ErrorAction SilentlyContinue
    W ('  :' + $port + ' pid=' + $l.OwningProcess)
    if ($p) { W ('    cmd=' + $p.CommandLine) }
  } else { W ('  :' + $port + ' SEM LISTENER!') }
}
W ('=== fim ' + (Get-Date) + ' ===')
