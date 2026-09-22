$ErrorActionPreference = 'Stop'
$Root = 'C:\ProgramData\HomelabScreenCamera'
$py  = Join-Path $Root 'python\venv\Scripts\python.exe'
$ff  = (Get-Command ffmpeg -ErrorAction Stop).Source
$fp  = (Get-Command ffprobe -ErrorAction Stop).Source
$mtx = Join-Path $Root 'mediamtx.exe'
$t   = Join-Path $env:LOCALAPPDATA 'Temp\hv4'
$t0  = Get-Date

'=== 0. derruba TUDO (helper antigo na 8554 incluido) ==='
$c = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object LocalPort -in 8000,8554,8556
foreach ($x in $c) { Stop-Process -Id $x.OwningProcess -Force -ErrorAction SilentlyContinue }
Get-Process python,python3,python3.11,mediamtx,mediamtx.exe,ffmpeg,ffprobe -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

'=== 1. sobe: mediamtx interno(8556) + bridge(8000) ==='
$m = Start-Process -FilePath $mtx -ArgumentList (Join-Path $Root 'mediamtx.yml') -WorkingDirectory $Root -PassThru
$b = Start-Process -FilePath $py -ArgumentList (Join-Path $Root 'bridge.py') -WorkingDirectory $Root -PassThru

'=== 2. helper PUBLICO CORRIGIDO: 0.0.0.0:8554 -> 127.0.0.1:8556 ==='
$h = Start-Process -FilePath $py -ArgumentList @((Join-Path $Root 'rtsp-http-helper.py'),'0.0.0.0:8554','127.0.0.1:8556') -WorkingDirectory $Root -PassThru -RedirectStandardOutput "$t-helper.log" -RedirectStandardError "$t-helper-err.log"
Start-Sleep -Seconds 3

'=== 3. quem escuta agora ==='
Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object LocalPort -in 8000,8554,8556 | ForEach-Object {
  $p = Get-CimInstance Win32_Process -Filter "ProcessId=$($_.OwningProcess)" -ErrorAction SilentlyContinue
  "{0}:{1} <- {2} (pid {3})" -f $_.LocalAddress,$_.LocalPort,$p.Name,$_.OwningProcess
}

'=== 4. publisher ffmpeg -> 127.0.0.1:8554 (via helper CORRIGIDO) ==='
$pub = Start-Process -FilePath $ff -ArgumentList @('-hide_banner','-loglevel','error','-f','gdigrab','-framerate','15','-draw_mouse','1','-i','desktop','-an','-c:v','libx264','-preset','veryfast','-tune','zerolatency','-pix_fmt','yuv420p','-profile:v','main','-g','30','-keyint_min','30','-sc_threshold','0','-b:v','3000k','-maxrate','3000k','-bufsize','6000k','-rtsp_transport','tcp','-f','rtsp','rtsp://screen-publisher:change-publish-password@127.0.0.1:8554/desktop') -WorkingDirectory $Root -PassThru -RedirectStandardOutput "$t-pub.log" -RedirectStandardError "$t-pub-err.log"
Start-Sleep -Seconds 5
"publisher alive=$([bool](Get-Process -Id $pub.Id -ErrorAction SilentlyContinue))"

'=== 5. PROBE HTTP do Intelbras -> helper (deve 200, DVR fica verde) ==='
try { $r=Invoke-WebRequest -UseBasicParsing 'http://192.168.5.54:8554/' -TimeoutSec 8; "probe=$($r.StatusCode)" } catch { "probe ERR $($_.Exception.Message)" }

'=== 6. leitura RTSP com WATCHDOG por job (kill em 20s, nunca pendura) ==='
function ReadWatch($label,$url) {
  $j = Start-Job -ScriptBlock { param($ff,$u) & $ff -hide_banner -loglevel error -rtsp_transport tcp -i $u -frames:v 10 -f null - 2>&1; "exit=$LASTEXITCODE" } -ArgumentList $ff,$url
  if (Wait-Job $j -Timeout 20) { "[$label] $(Receive-Job $j)" } else { Stop-Job $j; "[$label] TIMEOUT(20s)" }
  Remove-Job $j -Force -ErrorAction SilentlyContinue
}
'6a) anon:'
ReadWatch 'anon' 'rtsp://192.168.5.54:8554/desktop'
'6b) ovifadm:'
ReadWatch 'onvif' 'rtsp://ovifadm:change-onvif-password@192.168.5.54:8554/desktop'

'=== 7. health + snapshot bridge ==='
try { $r=Invoke-WebRequest -UseBasicParsing 'http://192.168.5.54:8000/health' -TimeoutSec 6; "health=$($r.StatusCode)" } catch { "health ERR $($_.Exception.Message)" }
try { $r=Invoke-WebRequest -UseBasicParsing 'http://192.168.5.54:8000/snapshot' -TimeoutSec 15; "snapshot=$($r.StatusCode) bytes=$($r.RawContentLength)" } catch { "snapshot ERR $($_.Exception.Message)" }

"=== total $([math]::Round(((Get-Date)-$t0).TotalSeconds))s - stack NO AR p/ DVR testar ==="