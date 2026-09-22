$Root = 'C:\ProgramData\HomelabScreenCamera'
$out = Join-Path $Root '_watchdog-diag.log'
function W($m) { Add-Content -Path $out -Value $m; Write-Output $m }
W ('=== watchdog diag | ' + (Get-Date) + ' ===')

W '--- [1] watchdog/relaunch scripts no root ---'
Get-ChildItem $Root -File | Where-Object { $_.Name -match 'watchdog|relaunch|dead-check|monitor|cron|task' } |
  Sort-Object LastWriteTime -Descending | Select-Object -First 8 |
  ForEach-Object { W ('  [' + $_.Name + ' | ' + $_.LastWriteTime + ']') }

W '--- [2] watchdog/publisher logs recentes ---'
Get-ChildItem (Join-Path $Root '_watchdog*.log') -File -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending | Select-Object -First 4 |
  ForEach-Object {
    W ('  [' + $_.Name + ' | ' + $_.LastWriteTime + ']')
    @(Get-Content $_.FullName -ErrorAction SilentlyContinue) |
      Where-Object { $_ -match 'SUBINDO|publisher|ffmpeg|desktop offline|ERRO|Error' } |
      Select-Object -Last 8 | ForEach-Object { W ('      ' + $_) }
  }

# como o watchdog relanca o publisher (procura linhas ffmpeg/gdigrab) — só leitura da config
W '--- [3] watchdog.py: config do publisher (PUBLISH_ARGS) ---'
$wd = Join-Path $Root 'watchdog.py'
if (Test-Path $wd) {
  @(Get-Content $wd) | Select-String -Pattern 'PUBLISH_ARGS|gdigrab|ffmpeg|desktop|shell|os\.system|Popen|subprocess' |
    Select-Object -First 12 | ForEach-Object { W ('    ' + $_.Line.Trim()) }
} else { W '  SEM watchdog.py' }

W '--- [4] publisher processos agora + mediamtx API paths (9997) ---'
$ff = @(Get-Process ffmpeg -ErrorAction SilentlyContinue)
W ('  ffmpeg count=' + @($ff).Count)
try {
  $r = Invoke-RestMethod -Uri 'http://127.0.0.1:9997/v3/paths/list' -TimeoutSec 4 -ErrorAction Stop
  W ('  mediamtx API OK: total=' + $r.pageInfo.total)
  $r.items | ForEach-Object { W ('    path=' + $_.name + ' ready=' + $_.ready + ' viewers=' + $_.viewers + ' source=' + $_.source) }
} catch { W ('  mediamtx API ERRO: ' + $_.Exception.Message) }

W ('=== fim ' + (Get-Date) + ' ===')
