$Root     = 'C:\ProgramData\HomelabScreenCamera'
$log      = Join-Path $Root '_swap-onvif-ovifadm-v2.log'
$excl     = '\.(old|bak|pre-|orig|pre-ovifadm|pre-onvif|\.bak$|\.old$)|\.old\.|\.bak\.|\.pre-|\.orig$'
$exts     = '\.(py|ps1|yml|yaml|json)$'
$targets  = @(
  'bridge.py','watchdog.py','soap-selftest.py','mediamtx.yml',
  'stack-full-up.ps1','final-clean-restart.ps1','start-clean-and-verify.ps1',
  'start-clean-verify.ps1','restart-and-verify.ps1','restart-helper-and-verify.ps1',
  'restart-bridge-only.ps1','restart-helper-quick.ps1','restart-helper-and-verify.ps1',
  'restart-helper-and-verify.ps1','start-and-verify.ps1','start-visible.ps1',
  'final-restart-and-verify.ps1','start-clean-and-verify.ps1','relaunch-clean-verify.ps1',
  'start-clean-and-verify.ps1','final-no-helper-publish.ps1','do-verify.ps1',
  'verify-2.ps1','verify-3.ps1','z-final-verify.ps1','final-restart-and-verify.ps1'
)
$changed   = 0
$checked   = 0

Add-Content $log ('=== swap onvif-admin->ovifadm v2 | ' + (Get-Date) + ' ===')
foreach ($name in $targets) {
  $path = Join-Path $Root $name
  if (-not (Test-Path $path)) { continue }
  $c = @(Get-Content $path -Raw -ErrorAction SilentlyContinue)
  if (-not $c) { continue }
  $checked++
  if ($c -notmatch 'onvif-admin') { continue }

  $bak = $path + '.pre-ovifadm'
  if (-not (Test-Path $bak)) { Copy-Item $path $bak -Force }

  $n = $c -replace 'onvif-admin','ovifadm'
  Set-Content -Path $path -Value $n -Encoding UTF8
  $changed++
  Add-Content $log ('  [' + $name + '] trocado (backup: ' + (Split-Path $bak -Leaf) + ')')
  Write-Output ('  [' + $name + '] trocado')
}
Add-Content $log ('  checked=' + $checked + ' changed=' + $changed)

# --- varredura residual: quaisquer ativos do root com onvif-admin ---
Add-Content $log '--- varredura residual ativos ---'
Get-ChildItem $Root -File | Where-Object {
  $_.Name -notmatch $excl -and $_.Name -match $exts
} | ForEach-Object {
  $c = @(Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue)
  if ($c -and $c -match 'onvif-admin') {
    Add-Content $log ('  [RESIDUAL ' + $_.Name + '] contem onvif-admin!')
  }
}
Add-Content $log ('=== fim | ' + (Get-Date) + ' ===')
Add-Content $log ''
Write-Output ("--- total: checked=$checked changed=$changed ---")
