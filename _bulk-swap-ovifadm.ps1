$ErrorActionPreference = 'Continue'
$Root = 'C:\ProgramData\HomelabScreenCamera'
$log  = Join-Path $Root '_bulk-swap-ovifadm.log'
function W($m) { Add-Content $log $m; Write-Output $m }
W ('=== bulk swap onvif-admin->ovifadm | ' + (Get-Date) + ' ===')

# Somente arquivos ATIVOS do root (exclui .old/.bak/.pre-*/.orig e backups de swap)
$excl = '\\.(old|bak|orig|pre-|ovifadm|swap|\.old|\.bak|\.pre-|\.orig)(\\.|$)|\.(old|bak|pre-.*|orig)(\\.|$)'
$changed = 0
$scanned = 0

Get-ChildItem $Root -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
  $_.Extension -in '.py','.ps1','.yml','.yaml','.txt','.md','.json'
} | ForEach-Object {
  $name = $_.Name
  if ($name -match '(^_swap-|\.old$|\.bak$|\.orig$|\.pre-|^_bulk-swap-)') { return }
  $cRaw = $null
  try { $cRaw = Get-Content $_.FullName -Raw -ErrorAction Stop } catch { return }
  if (-not $cRaw) { return }
  if ($cRaw -notmatch 'onvif-admin') { return }
  $scanned++

  # backup único
  $bak = $_.FullName + '.pre-ovifadm.bak'
  if (-not (Test-Path $bak)) { Copy-Item $_.FullName $bak -Force }

  $new = $cRaw -replace 'onvif-admin','ovifadm'
  if ($new -ne $cRaw) {
    Set-Content -Path $_.FullName -Value $new -Encoding UTF8 -NoNewline
    $changed++
    W ('  [' + $_.Name + '] trocado (backup .pre-ovifadm.bak)')
  }
}
W ('--- varredura residual (arquivos ativos com onvif-admin restantes) ---')
Get-ChildItem $Root -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
  $_.Extension -in '.py','.ps1','.yml','.yaml','.txt','.md','.json' -and
  $_.Name -notmatch '(^_swap-|\.old$|\.bak$|\.orig$|\.pre-|^_bulk-swap-)'
} | ForEach-Object {
  try { $cRaw = Get-Content $_.FullName -Raw -ErrorAction Stop } catch { return }
  if ($cRaw -and $cRaw -match 'onvif-admin') { W ('  [RESIDUAL ' + $_.Name + '] still has onvif-admin!') }
}
W ('--- resumo: scanned=' + $scanned + ' changed=' + $changed + ' | fim ' + (Get-Date) + ' ---')
