$Root = 'C:\ProgramData\HomelabScreenCamera'
$log = Join-Path $Root '_dial-8554.keepalive2.log'
$out = Join-Path $Root '_read-keepalive2-31.log'
Function W($m){ Add-Content $out $m; Write-Output $m }
W ('=== read keepalive2 foco-DVR ' + (Get-Date) + ' ===')
if (-not (Test-Path $log)) { W '  SEM LOG keepalive2'; exit }
$c = Get-Content $log
W ('  total=' + $c.Count)
$dvr = @($c | Where-Object { $_ -match '192\.168\.5\.31' })
W ('  do-DVR(192.168.5.31)=' + $dvr.Count)
W '  --- TODAS as do-DVR, em ordem ---'
$dvr | ForEach-Object { W ('    ' + $_) }
W '  --- ultimas 12 (geral) ---'
$c | Select-Object -Last 12 | ForEach-Object { W ('    ' + $_) }
W ('=== fim ' + (Get-Date) + ' ===')
