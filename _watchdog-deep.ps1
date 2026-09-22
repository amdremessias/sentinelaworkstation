$Root = 'C:\ProgramData\HomelabScreenCamera'
$out = Join-Path $Root '_watchdog-check.log'
function W($m) { Add-Content -Path $out -Value $m; Write-Output $m }

W ('=== publisher/watchdog deep | ' + (Get-Date) + ' ===')

# 1) Todos os .ps1/.py do root (para achar o publisher script + watchdog)
W '--- scripts do root ---'
Get-ChildItem $Root -File | Where-Object { $_.Name -match 'publisher|screen|watchdog|stack|ffmpeg|gdigrab|relay|helper|bridge|launch' } |
  Sort-Object LastWriteTime -Descending | Select-Object -First 12 |
  ForEach-Object { W ('  [' + $_.Name + ' | ' + $_.LastWriteTime + ']') }

# 2) descobrir TODOS os .log recentes
W '--- logs recentes ---'
Get-ChildItem $Root -File -Filter '*.log' |
  Sort-Object LastWriteTime -Descending | Select-Object -First 20 |
  ForEach-Object { W ('  [' + $_.Name + ' | ' + $_.LastWriteTime + ' | ' + [math]::Round($_.Length/1KB,1) + 'KB]') }

# 3) janela de credenciais/publicador no mediamtx.yml - sem segredos, so a parte publish/screen
W '--- mediamtx.yml (paths/screen/desktop/pub) ---'
$yml = Join-Path $Root 'mediamtx.yml'
if (Test-Path $yml) {
  Get-Content $yml | Select-String -Pattern 'desktop|screen|path|publish|read' | ForEach-Object { W ('  ' + $_.Line) }
} else { W '  SEM mediamtx.yml' }

# 4) ffmpeg log ultimos
W '--- ffmpeg/publisher logs ---'
@(Get-ChildItem $Root -File -Filter '*.log' | Where-Object { $_.Name -match 'ffmpeg|screen|publi|gdigrab' } |
  Sort-Object LastWriteTime -Descending | Select-Object -First 3) |
  ForEach-Object {
    W ('  [' + $_.Name + ' | ' + $_.LastWriteTime + ']')
    @(Get-Content $_.FullName -ErrorAction SilentlyContinue) | Select-Object -Last 14 | ForEach-Object { W ('    ' + $_) }
  }

W ('=== fim ' + (Get-Date) + ' ===')
