$Root = 'C:\ProgramData\HomelabScreenCamera'
$out = Join-Path $Root '_verify-pub-clean.log'
function W($m){ Add-Content $out $m; Write-Output $m }
W ('=== verify pub clean | ' + (Get-Date) + ' ===')

W '--- [1] ffmpeg publisher hoje agora ---'
$ff = @(Get-Process ffmpeg -ErrorAction SilentlyContinue)
W ('  ffmpeg count=' + @($ff).Count)
$ff | ForEach-Object { W ('    pid=' + $_.Id + ' | start=' + $_.StartTime) }

W '--- [2] MediaMTX API paths (v3) :9997 / :9998 ---'
foreach ($p in 9997,9998) {
  W ('  :' + $p)
  try {
    $r = Invoke-RestMethod -Uri ('http://127.0.0.1:' + $p + '/v3/paths/list') -TimeoutSec 4 -ErrorAction Stop
    W ('    total=' + $r.pageInfo.total)
    @($r.items) | ForEach-Object { W ('      path=' + $_.name + ' ready=' + $_.ready + ' viewers=' + $_.viewers) }
  } catch { W ('    ERRO: ' + $_.Exception.Message) }
}

W '--- [3] mediamtx.log: desktop publicado? (linhas desktop ultimas 10) ---'
$mlog = Get-ChildItem $Root -File | Where-Object { $_.Name -match 'mediamtx|mtx' -and $_.Extension -eq '.log' -and $_.Name -notmatch 'diag|diag2' } |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($mlog) {
  W ('  [' + $mlog.Name + ' | ' + $mlog.LastWriteTime + ']')
  @(Get-Content $mlog.FullName -ErrorAction SilentlyContinue) | Where-Object { $_ -match 'desktop' } |
    Select-Object -Last 12 | ForEach-Object { W ('    ' + $_) }
} else { W '  SEM log mediamtx' }

W ('=== fim ' + (Get-Date) + ' ===')
