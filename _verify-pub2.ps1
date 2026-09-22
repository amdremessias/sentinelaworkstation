$Root = 'C:\ProgramData\HomelabScreenCamera'
$out = Join-Path $Root '_verify-pub2.log'
Function W($m){ Add-Content $out $m; Write-Output $m }
W ('=== verify pub2 | ' + (Get-Date) + ' ===')

W '--- [1] ffmpeg vivo? ---'
$ff = @(Get-Process ffmpeg -ErrorAction SilentlyContinue)
W ('  ffmpeg count=' + @($ff).Count)
$ff | ForEach-Object { W ('    pid=' + $_.Id + ' | started=' + $_.StartTime) }

W '--- [2] mediamtx API :8556 paths (9997/9998) ---'
foreach ($p in 9997,9998) {
  W ('  api :' + $p)
  try {
    $r = Invoke-RestMethod -Uri ('http://127.0.0.1:' + $p + '/v3/paths/list') -TimeoutSec 4 -ErrorAction Stop
    W ('    OK total=' + $r.pageInfo.total)
    $r.items | ForEach-Object { W ('    path=' + $_.name + ' ready=' + $_.ready + ' viewers=' + $_.viewers + ' source=' + $_.source) }
  } catch { W ('    ERRO: ' + $_.Exception.Message) }
}

W '--- [3] últimas linhas do publisher relaunch log ---'
@(Get-ChildItem $Root -File | Where-Object { $_.Name -match '_relaunch-publisher|pub' -and $_.Extension -eq '.log' } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 3) |
  ForEach-Object {
    W ('  [' + $_.Name + ' | ' + $_.LastWriteTime + ']')
    @(Get-Content $_.FullName -ErrorAction SilentlyContinue) | Select-Object -Last 5 | ForEach-Object { W ('    ' + $_) }
  }

W ('=== fim ' + (Get-Date) + ' ===')
