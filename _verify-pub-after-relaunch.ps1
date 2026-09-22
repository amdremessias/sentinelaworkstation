$Root = 'C:\ProgramData\HomelabScreenCamera'
$out = Join-Path $Root '_verify-pub-after-relaunch.log'
Function W($m){ Add-Content -Path $out -Value $m; Write-Output $m }

W ('=== verify publisher apos relaunch | ' + (Get-Date) + ' ===')

# [1] ffmpeg vivo agora?
$ff = @(Get-Process ffmpeg -ErrorAction SilentlyContinue)
W ('  ffmpeg count=' + @($ff).Count)
$ff | ForEach-Object { W ('    pid=' + $_.Id + ' | ' + $_.StartTime) }

# [2] MediaMTX API (9997) — desktop publicado?
W '  --- mediamtx API :9997 ---'
try {
  $r = Invoke-RestMethod -Uri 'http://127.0.0.1:9997/v3/paths/list' -TimeoutSec 5 -ErrorAction Stop
  W ('    total=' + $r.pageInfo.total)
  @($r.items) | ForEach-Object {
    W ('    path=' + $_.name + ' ready=' + $_.ready + ' viewers=' + $_.viewers + ' totalReaders=' + $_.totalReaders)
  }
} catch { W ('    ERRO API 9997: ' + $_.Exception.Message) }
try {
  $r2 = Invoke-RestMethod -Uri 'http://127.0.0.1:9997/v3/paths/get/desktop' -TimeoutSec 5 -ErrorAction Stop
  W ('    (get/desktop) ready=' + $r2.ready + ' viewers=' + $r2.viewers)
} catch { W ('    ERRO get/desktop: ' + $_.Exception.Message) }

# [3] logs publisher recentes (morreu de novo? com o erro 5?)
W '  --- publisher logs recentes ---'
Get-ChildItem $Root -File | Where-Object { $_.Name -match '_relaunch-pub|_pub' -and $_.Extension -in '.log','-err.log' } |
  Sort-Object LastWriteTime -Descending | Select-Object -First 4 |
  ForEach-Object {
    W ('    [' + $_.Name + ' | ' + $_.LastWriteTime + ']')
    @(Get-Content $_.FullName -ErrorAction SilentlyContinue) | Select-Object -Last 5 |
      ForEach-Object { W ('      ' + $_) }
  }

# [4] rtsp helper :8554 segue vivo (nao mexi, so confirma)
W '  --- listeners ---'
foreach ($p in 8000,8554,8556,9997) {
  $l = Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue | Select-Object -First 1
  W ('    :' + $p + ' -> ' + $(if($l){'LISTEN pid='+$l.OwningProcess}else{'SEM listener'}))
}
try {
  $h = Invoke-WebRequest -Uri 'http://127.0.0.1:8000/health' -TimeoutSec 4 -UseBasicParsing -ErrorAction Stop
  W ('    bridge /health = ' + [int]$h.StatusCode)
} catch { W ('    bridge /health ERRO: ' + $_.Exception.Message) }

W ('=== fim ' + (Get-Date) + ' ===')
