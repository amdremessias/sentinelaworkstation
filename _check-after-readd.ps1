$Root = 'C:\ProgramData\HomelabScreenCamera'
$out = Join-Path $Root '_check-after-readd.txt'
Function W($m){ Add-Content -Path $out -Value $m; Write-Output $m }

W ('=== check-after-readd ' + (Get-Date) + ' ===')
W '--- 1) listeners ---'
foreach ($port in 8000,8554,8556) {
  $l = Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($l) { W ("  :" + $port + " pid=" + $l.OwningProcess) }
  else { W ("  :" + $port + " SEM LISTENER") }
}

W '--- 2) helper dono :8554 (tem que ser o KEEPALIVE2:CSeq-echo) ---'
$l = Get-NetTCPConnection -State Listen -LocalPort 8554 -ErrorAction SilentlyContinue | Select-Object -First 1
if ($l) {
  $p = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $l.OwningProcess) -ErrorAction SilentlyContinue
  W ('  pid=' + $l.OwningProcess)
  if ($p) { W ('  cmd=' + $p.CommandLine) }
} else { W '  SEM dono:8554' }

W '--- 3) bridge /health (verde vem daqui) ---'
try {
  $r = Invoke-RestMethod -Uri 'http://127.0.0.1:8000/health' -TimeoutSec 4 -ErrorAction Stop
  W ('  /health -> OK: ' + ($r | ConvertTo-Json -Compress))
} catch { W ('  /health ERR ' + $_.Exception.Message) }

W '--- 4) log helper KEEPALIVE2: conectou DVR (192.168.5.31) apos re-add? ---'
$k2 = Join-Path $Root '_dial-8554.keepalive2.log'
if (Test-Path $k2) {
  $all = Get-Content $k2
  W ('  total=' + $all.Count)
  $dvr = $all | Where-Object { $_ -match '192\.168\.5\.31' }
  W ('  do-DVR(192.168.5.31)=' + @($dvr).Count)
  W '  --- do-DVR (todas) ---'
  @($dvr) | ForEach-Object { W ('    ' + $_) }
  if (@($dvr).Count -eq 0) { W '    (NENHUMA conexao do DVR apos o re-add!)' }
  W '  --- ultimas 6 (geral) ---'
  $all | Select-Object -Last 6 | ForEach-Object { W ('    ' + $_) }
} else { W '  sem log keepalive2' }
W ('=== fim ' + (Get-Date) + ' ===')
