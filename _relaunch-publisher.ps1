$Root = 'C:\ProgramData\HomelabScreenCamera'
$out  = Join-Path $Root '_relaunch-publisher.log'
function W($m){ Add-Content $out $m; Write-Output $m }
W ('=== relaunch publisher | ' + (Get-Date) + ' ===')

# acha ffmpeg (mesma logica do stack)
$ff = (Get-Command ffmpeg -ErrorAction Stop).Source
W ('  ffmpeg=' + $ff)

# mata publishers mortos (garantia)
Get-Process ffmpeg -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

$t = '_relaunch-pub-' + (Get-Date -Format 'HHmmss')
$pubLog = Join-Path $Root ($t + '.log')
$pubErr = Join-Path $Root ($t + '-err.log')

# publisher IDENTICO ao stack-full-up.ps1 (gdigrab -> mediamtx interno :8556)
$args = @(
  '-hide_banner','-loglevel','error',
  '-f','gdigrab','-framerate','25','-draw_mouse','1','-i','desktop',
  '-an','-c:v','libx264','-preset','veryfast','-tune','zerolatency',
  '-pix_fmt','yuv420p','-profile:v','main','-level:v','4.1','-g','50','-keyint_min','50',
  '-sc_threshold','0','-b:v','3000k','-maxrate','3000k','-bufsize','6000k',
  '-rtsp_transport','tcp','-f','rtsp',
  'rtsp://screen-publisher:change-publish-password@127.0.0.1:8556/desktop'
)
$pub = Start-Process -FilePath $ff -ArgumentList $args -WorkingDirectory $Root -PassThru `
  -RedirectStandardOutput $pubLog -RedirectStandardError $pubErr

Start-Sleep -Seconds 6

W '--- apos 6s ---'
# publisher vivo?
$f = @(Get-Process ffmpeg -ErrorAction SilentlyContinue)
W ('  ffmpeg count=' + @($f).Count + ' | pub pid=' + $pub.Id)
# mediamtx API (paths)
try {
  $r = Invoke-RestMethod -Uri 'http://127.0.0.1:9997/v3/paths/list' -TimeoutSec 5 -ErrorAction Stop
  $r.items | ForEach-Object { W ('  path=' + $_.name + ' ready=' + $_.ready + ' viewers=' + $_.viewers) }
} catch { W ('  mediamtx API ERRO: ' + $_.Exception.Message) }

# log do publisher (ha erro de captura de novo?)
W '--- log publisher (ultimas) ---'
if (Test-Path $pubErr) { @(Get-Content $pubErr) | Select-Object -Last 8 | ForEach-Object { W ('  ' + $_) } }
if (Test-Path $pubLog) { @(Get-Content $pubLog) | Select-Object -Last 4 | ForEach-Object { W ('  ' + $_) } }

W ('=== fim ' + (Get-Date) + ' ===')
