$f = 'C:\ProgramData\HomelabScreenCamera\_dial-8554.keepalive2.log'
if (-not (Test-Path $f)) { 'NAO EXISTE: _dial-8554.keepalive2.log'; exit }
$c = Get-Content $f
Write-Output ('TOTAL linhas=' + $c.Count)
$n = $c | Where-Object { $_ -match 'DESCRIBE|SETUP|PLAY|TEARDOWN' }
Write-Output ('  com DESCRIBE/SETUP/PLAY/TEARDOWN = ' + @($n).Count)
Write-Output '--- ultimas 20 linhas ---'
$c | Select-Object -Last 20
