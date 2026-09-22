$Root = 'C:\ProgramData\HomelabScreenCamera'
$log = Join-Path $Root '_swap-onvif-ovifadm.log'
Function W($m){ Add-Content $log $m; Write-Output $m }
W ('=== swap onvif-admin -> ovifadm | ' + (Get-Date) + ' ===')

# Alvos: TODOS os .py/.ps1/.yml ativos do root que contenham 'onvif-admin'
$targets = @(
  'bridge.py','watchdog.py','stack-full-up.ps1','stack-full-up.ps1',
  'stack-full-up.ps1','final-clean-restart.ps1','start-clean-and-verify.ps1',
  'restart-and-verify.ps1','restart-helper-and-verify.ps1','restart-bridge-only.ps1',
  'start-visible.ps1','start-and-verify.ps1','stack-full-publish.ps1',
  'mediamtx.yml','do-verify.ps1','_publisher-dead-check.ps1','_dvr-flow-test.py',
  '_dvr-client-capture.py','_dvr-stream-dump.py','_rtsp-probe.py','_live-config-check.py'
)
$changed = 0

foreach ($name in $targets) {
  $f = Join-Path $Root $name
  if (-not (Test-Path $f)) { continue }
  $c = @(Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue)
  if (-not $c) { continue }
  if ($c -notmatch 'onvif-admin') { continue }

  # backup antes (uma única vez)
  $bak = $f.FullName + '.pre-ovifadm'
  if (-not (Test-Path $bak)) { Copy-Item $f.FullName $bak -Force }

  $n = ($c -replace 'onvif-admin','ovifadm')
  Set-Content -Path $f.FullName -Value $n -Encoding UTF8
  $changed++
  W ('  [' + $name + '] trocado')
}

# Segurança: varrer quaisquer outros arquivos ativos do root com onvif-admin
W '--- varredura residual (arquivos ativos com onvif-admin) ---'
Get-ChildItem $Root -File | Where-Object {
    $_.Name -notmatch '\.(old|bak|pre-ovifadm|pre-|orig|pre-dvr|pre-onvif|backup)' -and
    $_.Extension -in '.py','.ps1','.yml','.yaml','.json'
  } |
  ForEach-Object {
    $content = @(Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue)
    if ($content -and $content -match 'onvif-admin') {
      W ('  [RESIDUAL ' + $_.Name + '] contem onvif-admin!')
    }
  }

W ('  total trocados=' + $changed)
W ('=== fim ' + (Get-Date) + ' ===')
