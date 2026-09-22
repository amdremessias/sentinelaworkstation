$Root = 'C:\ProgramData\HomelabScreenCamera'
Function W($m){ Write-Output $m }

W '=== A) MediaMTX :8556 - processos e log ==='
W '--- processos com mediamtx na cmdline ---'
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'mediamtx' } | ForEach-Object { W ('  pid=' + $_.ProcessId + ' started=' + $_.CreationDate) }

W '--- log do MediaMTX (sessoes desktop / erros) ---'
$mtlogs = @('mediamtx.log','_mediamtx.log','_mtx.log')
foreach ($n in $mtlogs) {
  $p = Join-Path $Root $n
  if (Test-Path $p) {
    W ('  [' + $n + '] ultimas 6:')
    Get-Content $p -ErrorAction SilentlyContinue | Select-Object -Last 6 | ForEach-Object { W ('    ' + $_) }
  }
}
W '--- stdout/err da pasta (se helper/publisher jogou algo) ---'
Get-ChildItem $Root -Filter '_h*.log' -ErrorAction SilentlyContinue | Select-Object -First 6 | ForEach-Object {
  W ('  [' + $_.Name + '] (' + $_.Length + 'b, mtime ' + $_.LastWriteTime + ')')
}

W ''
W '=== B) helper :8554 - err/out logs ==='
Get-ChildItem $Root -Filter '_h2*.log' -ErrorAction SilentlyContinue | ForEach-Object {
  W ('  [' + $_.Name + '] fim:')
  Get-Content $_.FullName -ErrorAction SilentlyContinue | Select-Object -Last 5 | ForEach-Object { W ('    ' + $_) }
}

W ''
W '=== C) o que o helper NOVO logou por inteiro (todas linhas, nao so DVR) ==='
$lf = Join-Path $Root '_dial-8554.newer.log'
if (Test-Path $lf) {
  $c = Get-Content $lf
  W ('  total=' + $c.Count)
  $c | Select-Object -Last 12 | ForEach-Object { W ('    ' + $_) }
} else { W '  (sem log newer)' }
