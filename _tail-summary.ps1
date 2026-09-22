$log = 'C:\ProgramData\HomelabScreenCamera\_dial-8554.newer.log'
if (-not (Test-Path $log)) { 'NAO EXISTE: _dial-8554.newer.log'; exit }
$lines = Get-Content $log
Write-Output ("TOTAL=" + $lines.Count)
Write-Output '--- por tipo ---'
$lines | ForEach-Object {
  if     ($_ -match 'KEEPALIVE')            { 'KEEPALIVE' }
  elseif ($_ -match '-> 200-local')         { '200-LOCAL' }
  elseif ($_ -match 'RELAY')                { 'RELAY' }
  elseif ($_ -match 'DESCRIBE')             { 'DESCRIBE' }
  elseif ($_ -match 'SETUP')                { 'SETUP' }
  elseif ($_ -match 'PLAY')                 { 'PLAY' }
  elseif ($_ -match 'OPTIONS')              { 'OPTIONS' }
  elseif ($_ -match 'HTTP')                 { 'HTTP-PROBE' }
  else                                      { 'OUTRO' }
} | Group-Object | ForEach-Object { Write-Output ('  ' + $_.Name + ' = ' + $_.Count) }
Write-Output '--- ultimas 15 linhas ---'
$lines | Select-Object -Last 15
