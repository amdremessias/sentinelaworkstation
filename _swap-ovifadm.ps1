$Root = 'C:\ProgramData\HomelabScreenCamera'
$log  = Join-Path $Root '_swap-ovifadm.log'
Add-Content $log ('=== swap onvif-admin -> ovifadm | ' + (Get-Date) + ' ===')
$changed = 0

# Arquivos ativos (exclui backups .old/.bak/.pre-*) que contêm 'onvif-admin'
$targets = @(
  'bridge.py','watchdog.py','mediamtx.yml','stack-full-up.ps1',
  'stack-up-direct-publish.ps1','restart-bridge-only.ps1',
  'restart-helper-and-verify.ps1','restart-and-verify.ps1',
  'restart-helper-quick.ps1','final-restart-and-verify.ps1',
  'final-clean-restart.ps1','start-clean-and-verify.ps1',
  'start-visible.ps1','start-and-verify.ps1','relaunch-clean-verify.ps1',
  'verify-2.ps1','verify-3.ps1','verify-4.ps1','do-verify.ps1',
  'final-helper-publish.ps1','final-http-probe.ps1',
  'start-clean-and-verify.ps1','stack-full-up.ps1','relaunch-publisher.ps1',
  'rtsp-http-helper.py','rtsp-http-relay.py','rtsp-http-bridge.py'
) | Select-Object -Unique

foreach ($name in $targets) {
  $f = Join-Path $Root $name
  if (-not (Test-Path $f)) { continue }
  $c = @(Get-Content $f -Raw -ErrorAction SilentlyContinue)
  if (-not $c) { continue }
  if ($c -notmatch 'onvif-admin') { continue }

  # backup
  $bak = $f + '.pre-ovifadm'
  if (-not (Test-Path $bak)) { Copy-Item $f $bak -Force }
  $n = @($c)
  if ($n -match 'onvif-admin') {
    $n2 = $n -replace 'onvif-admin','ovifadm'
    Set-Content -Path $f -Value $n2 -Encoding UTF8
    $changed++
    Add-Content $log ('  [' + $name + '] onvif-admin -> ovifadm (backup: ' + (Split-Path $bak -Leaf) + ')')
    Write-Output ('  [' + $name + '] trocado')
  }
}

# Também varre todos os .py ativos por qualquer ocorrência restante (segurança)
$left = @(Get-ChildItem $Root -File -Filter '*.py' | Where-Object { $_.Name -notmatch '\.(old|bak|pre-|orig)' } |
  Where-Object { (Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue) -match 'onvif-admin' })
foreach ($f in $left) {
  $c = Get-Content $f.FullName -Raw
  $bak = $f.FullName + '.pre-ovifadm'
  if (-not (Test-Path $bak)) { Copy-Item $f.FullName $bak -Force }
  Set-Content -Path $f.FullName -Value ($c -replace 'onvif-admin','ovifadm') -Encoding UTF8
  $changed++
  Add-Content $log ('  [extra:' + $f.Name + '] trocado')
  Write-Output ('  [extra:' + $f.Name + '] trocado')
}

Add-Content $log ('  total trocados=' + $changed + ' | fim ' + (Get-Date))
Write-Output ('  total=' + $changed)
Add-Content $log '=== fim ==='
