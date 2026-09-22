$Root = 'C:\ProgramData\HomelabScreenCamera'
$out = Join-Path $Root '_verify-pub-post-relaunch.log'
Function W($m){ Add-Content $out $m; Write-Output $m }
W ('=== verify pub pós-relaunch | ' + (Get-Date) + ' ===')

# Acha a porta real da API do MediaMTX lendo o YAML (a última sessão usou :9997/:9998 errado)
W '--- [1] apiPortSource do mediamtx.yml (API) ---'
$yml = Join-Path $Root 'mediamtx.yml'
if (Test-Path $yml) {
  @(Get-Content $yml) | Select-String -Pattern 'api|9997|9998|9999|port' |
    ForEach-Object { W ('  ' + $_.Line.Trim()) }
} else { W '  SEM mediamtx.yml' }

W '--- [2] ffmpeg agora (o publisher relauncado em pé?) ---'
$ff = @(Get-Process ffmpeg -ErrorAction SilentlyContinue)
W ('  ffmpeg count=' + @($ff).Count)
$ff | ForEach-Object { W ('    pid=' + $_.Id + ' | start=' + $_.StartTime) }

W '--- [3] mediamtx log: desktop publicado DEPOIS do relaunch? ---'
Get-ChildItem $Root -File | Where-Object { $_.Name -match 'mediamtx' -and $_.Extension -eq '.log' -and $_.Name -notmatch '\.(out|err)' } |
  Sort-Object LastWriteTime -Descending | Select-Object -First 2 |
  ForEach-Object {
    W ('  [' + $_.Name + ' | ' + $_.LastWriteTime + ']')
    $c = @(Get-Content $_.FullName -ErrorAction SilentlyContinue)
    $pub = @($c | Where-Object { $_ -match 'is publishing|publisher connected|ready: yes' })
    W ('    "publishing/connected ready"=' + $pub.Count)
    $pub | Select-Object -Last 4 | ForEach-Object { W ('      ' + $_) }
    W '    ultimas desktop (10):'
    @($c | Where-Object { $_ -match 'desktop' }) | Select-Object -Last 10 |
      ForEach-Object { W ('      ' + $_) }
  }

W ('=== fim ' + (Get-Date) + ' ===')
