$Root = 'C:\ProgramData\HomelabScreenCamera'
$out = Join-Path $Root '_verify-pub-v2.log'
Function W($m){ Add-Content $out $m; Write-Output $m }
W ('=== verify pub v2 | ' + (Get-Date) + ' ===')

# [1] qual a porta da API no mediamtx.yml (leitura)
W '--- [1] mediamtx.yml: porta API / rtsp / rtspAddress ---'
$yml = Join-Path $Root 'mediamtx.yml'
if (Test-Path $yml) {
  @(Get-Content $yml) | Select-String -Pattern 'api|address|port|9997|9998|9999|8556|8554' |
    ForEach-Object { W ('  ' + $_.Line.Trim()) }
} else { W '  SEM mediamtx.yml' }

# [2] publisher ffmpeg vivo agora?
W '--- [2] ffmpeg/publisher ---'
$ff = @(Get-Process ffmpeg -ErrorAction SilentlyContinue)
W ('  ffmpeg count=' + @($ff).Count)
$ff | ForEach-Object { W ('    pid=' + $_.Id + ' | start=' + $_.StartTime) }

# [3] MediaMTX API: achar porta correta (tenta 9997,9998,9999 + a do yml)
W '--- [3] MediaMTX API paths ---'
$apiPorts = 9997,9998,9999
foreach ($p in $apiPorts) {
  try {
    $r = Invoke-RestMethod -Uri ('http://127.0.0.1:' + $p + '/v3/paths/list') -TimeoutSec 4 -ErrorAction Stop
    W ('  :' + $p + ' OK | total=' + $r.pageInfo.total)
    $r.items | ForEach-Object { W ('    path=' + $_.name + ' ready=' + $_.ready + ' viewers=' + $_.viewers + ' source=' + $_.source) }
    break
  } catch { W ('  :' + $p + ' ERRO: ' + $_.Exception.Message) }
}

# [4] mediamtx log: desktop publicado recentemente?
W '--- [4] mediamtx log (desktop) ---'
$ml = Get-ChildItem $Root -File -Filter '*.log' | Where-Object { $_.Name -match '_mtx|mediamtx' } |
  Sort-Object LastWriteTime -Descending | Select-Object -First 2
foreach ($m in $ml) {
  W ('  [' + $m.Name + ' | ' + $m.LastWriteTime + ']')
  @(Get-Content $m.FullName -ErrorAction SilentlyContinue) |
    Where-Object { $_ -match 'desktop' } | Select-Object -Last 8 |
    ForEach-Object { W ('    ' + $_) }
}

W '=== fim ==='
