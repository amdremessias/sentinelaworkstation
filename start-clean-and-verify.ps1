$ErrorActionPreference = 'Stop'
$Root = 'C:\ProgramData\HomelabScreenCamera'

'=== 0. derruba tudo limpo (python/mediamtx/ffmpeg) ==='
Get-Process python,python3,python3.11,mediamtx,mediamtx_*,ffmpeg -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

'=== 1. sobe: mediamtx interno(8556) + bridge(8000) + helper publico(8554->8556) ==='
$py  = Join-Path $Root 'python\venv\Scripts\python.exe'
$ff  = (Get-Command ffmpeg -ErrorAction Stop).Source
$mtx = Join-Path $Root 'mediamtx.exe'
$logs = "$env:TEMP\hlsc"
Start-Process -FilePath $mtx -ArgumentList (Join-Path $Root 'mediamtx.yml') -WorkingDirectory $Root -RedirectStandardOutput "$logs-mtx.log" -RedirectStandardError "$logs-mtx-err.log"
Start-Sleep -Milliseconds 600
Start-Process -FilePath $py -ArgumentList (Join-Path $Root 'bridge.py') -WorkingDirectory $Root -RedirectStandardOutput "$logs-bridge.log" -RedirectStandardError "$logs-bridge-err.log"
Start-Process -FilePath $py -ArgumentList @('rtsp-http-helper.py','0.0.0.0:8554','127.0.0.1:8556') -WorkingDirectory $Root -RedirectStandardOutput "$logs-helper.log" -RedirectStandardError "$logs-helper-err.log"
Start-Sleep -Seconds ä»€ä¹ˆäºº

'=== 2. quem escuta 8000/8554/8556 ==='
Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -in 8000,8554,8556 } | ForEach-Object {
  $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$($_.OwningProcess)" -ErrorAction SilentlyContinue
  "{0}:{1} <- {2} (pid {3})" -f $_.LocalAddress,$_.LocalPort,$proc.Name,$_.OwningProcess
}

'=== 3. publisher (background) vai para a 8554 PUBLICA (helper detecta RTSP e repassa ao mediaMTX interno 8556) ==='
Start-Process -FilePath $ff -ArgumentList @('-hide_banner','-loglevel','error','-f','gdigrab','-framerate','15','-draw_mouse','1','-i','desktop','-an','-c:v','libx264','-preset','veryfast','-tune','zerolatency','-pix_fmt','yuv420p','-profile:v','main','-g','30','-keyint_min','30','-sc_threshold','0','-b:v','3000k','-maxrate','3000k','-bufsize','6000k','-rtsp_transport','tcp','-f','rtsp','rtsp://screen-publisher:change-publish-password@192.168.5.54:8554/desktop') -RedirectStandardOutput "$logs-pub.log" -RedirectStandardError "$logs-pub-err.log" -WorkingDirectory $Root
Start-Sleep -Seconds 6

'--- stream publicada? (API interna do mediamtx se habilitada) ---'
try { $s=Invoke-RestMethod 'http://127.0.0.1:9997/v3/paths/list' -TimeoutSec 5; if($s.items){$s.items|ForEach-Object{" path=$($_.name) ready=$($_.ready)"}} else {' (nenhum path)'} } catch { "api ERR $($_.Exception.Message)" }

'=== 4. PROBE HTTP do Intelbras -- helper na 8554 deve responder 200 ==='
try { $r=Invoke-WebRequest -UseBasicParsing 'http://192.168.5.54:8554/' -TimeoutSec 8; "probe HTTP -> $($r.StatusCode)" } catch { "probe ERR $($_.Exception.Message)" }

'=== 5. leitura RTSP VIA HELPER (todos na 8554) -- cada um com tempo limite ==='
'5a anonimo:'
& $ff -hide_banner -loglevel error -rtsp_transport tcp -stimeout 15000000 -i 'rtsp://192.168.5.54:8554/desktop' -frames:v 10 -f null - 2>&1
"anon exit=$LASTEXITCODE"
'5b ovifadm:'
& $ff -hide_banner -loglevel error -rtsp_transport tcp -stimeout 15000000 -i 'rtsp://ovifadm:change-onvif-password@192.168.5.54:8554/desktop' -frames:v 10 -f null - 2>&1
"onvif exit=$LASTEXITCODE"

'=== 6. health + snapshot bridge ==='
try { $r=Invoke-WebRequest -UseBasicParsing 'http://192.168.5.54:8000/health' -TimeoutSec 5; "health=$($r.StatusCode)" } catch { "health ERR $($_.Exception.Message)" }
try { $r=Invoke-WebRequest -UseBasicParsing 'http://192.168.5.54:8000/snapshot' -TimeoutSec 12; "snapshot=$($r.StatusCode) bytes=$($r.RawContentLength)" } catch { "snapshot ERR $($_.Exception.Message)" }

'=== 7. log mediamtx (interno) -- NOVAS linhas "invalid HTTP request"? (nao deve ter, probe morre no helper) ==='
Get-Content "$logs-mtx-err.log" -Tail 8 -ErrorAction SilentlyContinue

'=== 8. log helper: o que ele viu? (probe HTTP 200 vs RTSP repassado) ==='
Get-Content "$logs-helper.log" -Tail 6 -ErrorAction SilentlyContinue
'=== FIM ==='