$log = 'C:\ProgramData\HomelabScreenCamera\_dial-8554.newer.log'
if (Test-Path $log) {
  Get-Content $log | Where-Object { $_ -match '192\.168\.5\.31' } | Select-Object -Last 25
} else {
  'NAO EXISTE: _dial-8554.newer.log'
}
