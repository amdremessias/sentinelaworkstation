$Root = 'C:\ProgramData\HomelabScreenCamera'
$out = Join-Path $Root '_publisher-dead-check.log'
Function W($m){ Add-Content -Path $out -Value $m; Write-Output $m }
W ('=== publisher-dead incl. logs | ' + (Get-Date) + ' ===')

# ffmpeg (posso estar com nome/path diferente ou rodando como outro processo)
W '--- processos ffmpeg/ffplay/vlc/mtx ---'
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match 'ffmpeg|ffplay|vlc|mediamtx' } |
  ForEach-Object { W ('  pid=' + $_.ProcessId + ' name=' + $_.Name) ; if ($_.CommandLine) { W ('    ' + $_.CommandLine.Substring(0,[Math]::Min(200,$_.CommandLine.Length))) } }
$ff = @(Get-CimInstance Win32_Process -Filter "Name='ffmpeg.exe'" -ErrorAction SilentlyContinue)
W ('  ffmpeg count=' + @($ff).Count)

# MediaMTX tem o path /desktop publicado agora? (API 9997 JSON se ligada, senao inferir por log)
W '--- mediamtx log atual (procura publisher/read/path desktop) ---'
$mxLogCand = @(Get-ChildItem $Root -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'mtx|mediamtx' -and $_.Extension -match '\.log|\.txt' })
$mxLog = $mxLogCand | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($mxLog) {
  W ('  [log=' + $mxLog.Name + ' | ' + $mxLog.LastWriteTime + ']')
  $c = @(Get-Content $mxLog.FullName -ErrorAction SilentlyContinue)
  W ('  lines=' + $c.Count)
  W '  --- procura linhas desktop ---'
  $c | Where-Object { $_ -match 'desktop' } | Select-Object -Last 12 | ForEach-Object { W ('    ' + $_) }
  W '  --- ultimas 10 ---'
  $c | Select-Object -Last 10 | ForEach-Object { W ('    ' + $_) }
} else { W '  SEM log mediamtx' }

# publisher died? watchdog? arquivos de launcher
W '--- launcher/publisher scripts recentes ---'
Get-ChildItem $Root -File -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match 'watchdog|publish|ffmpeg|stack|pipeline' } |
  Sort-Object LastWriteTime -Descending | Select-Object -First 8 |
  ForEach-Object { W ('  ' + $_.Name + ' | ' + $_.LastWriteTime) }

# debugando a porta 9997 (API mtx)
W '--- api 9997 (teste) ---'
try { $r = Invoke-WebRequest 'http://127.0.0.1:9997/v3/paths/list' -TimeoutSec 3 -UseBasicParsing; W ('  ' + $r.StatusCode + ' ' + $r.Content) }
catch { W ('  ERRO ' + $_.Exception.Message) }

W ('=== fim ' + (Get-Date) + ' ===')
