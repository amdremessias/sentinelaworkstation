$ErrorActionPreference = 'Stop'
$Root = 'C:\ProgramData\HomelabScreenCamera'
$py  = Join-Path $Root 'python\venv\Scripts\python.exe'
$mtx = Join-Path $Root 'mediamtx.exe'
$ff  = (Get-Command ffmpeg -ErrorAction Stop).Source
$t   = "$env:LOCALAPPDATA\Temp\hlsc-v2"

'=== 0. derruba tudo limpo ==='
Get-Process python,python3,python3.11,mediamtx,ffmpeg -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

'=== 1. sobe a stack (mediamtx interno 8556 + bridge 8000 + helper publico 8554) ==='
$m = Start-Process -FilePath $mtx -ArgumentList (Join-Path $Root 'mediamtx.yml') -WorkingDirectory $Root -PassThru -RedirectStandardOutput "$t-mtx.log" -RedirectStandardError "$t-mtx-err.log"
$b = Start-Process -FilePath $py -ArgumentList (Join-Path $Root 'bridge.py') -WorkingDirectory $Root -PassThru -RedirectStandardOutput "$t-bridge.log" -RedirectStandardError "$t-bridge-err.log"
$px = Start-Process -FilePath $py -ArgumentList @('rtsp-http-helper.py','0.0.0.0:8554','127.0.0.1:8556') -WorkingDirectory $Root -PassThru -RedirectStandardOutput "$t-helper.log" -RedirectStandardError "$t-helper-err.log"
Start-Sleep -Seconds 3
"mediamtx=$([bool](Get-Process $m.Id -ErrorAction SilentlyContinue)) bridge=$([bool](Get-Process $b.Id -ErrorAction SilentlyContinue)) helper=$([bool](Get-Process $px.Id -ErrorAction SilentlyContinue))"

'=== 2. quem escuta 8000/8554/8556 ==='
Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -in 8000,8554,8556 } | ForEach-Object {
  $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$($_.OwningProcess)" -ErrorAction SilentlyContinue
  "{0}:{1} <- {2} (pid {3})" -f $_.LocalAddress,$_.LocalPort,$proc.Name,$_.OwningProcess
}

'=== 3. publisher real (gdigrab desktop) VIA HELPER 8554 -> mediamtx interno 8556 ==='
$pub = Start-Process -FilePath $ff -ArgumentList @('-hide_banner','-loglevel','error','-f','gdigrab','-framerate','15','-draw_mouse','1','-i','desktop','-an','-c:v','libx264','-preset','veryfast','-tune','zerolatency','-pix_fmt','yuv420p','-profile:v','main','-g','30','-keyint_min','30','-sc_threshold','0','-b:v','3000k','-maxrate','3000k','-bufsize','6000k','-rtsp_transport','tcp','-f','rtsp','rtsp://screen-publisher:change-publish-password@192.168.5.54:8554/desktop') -PassThru -RedirectStandardOutput "$t-pub.log" -RedirectStandardError "$t-pub-err.log"
Start-Sleep -Seconds 6
"publisher alive=$([bool](Get-Process $pub.Id -ErrorAction SilentlyContinue))"

'=== 4. PROBE HTTP do Intelbras (o que derrubava no mediamtx) -> helper deve responder 200 ==='
try { $r=Invoke-WebRequest -UseBasicParsing 'http://192.168.5.54:8554/' -TimeoutSec 8; "probe HTTP -> $($r.StatusCode)" } catch { "probe ERR $($_.Exception.Message)" }

'=== 5. leitura RTSP VIA HELPER (8554), anonima E ovifadm, com timeout ---> NAO PODE PENDURAR ==='
'5a) anonima:'
& $ff -hide_banner -loglevel error -rtsp_transport tcp -stimeout 15000000 -i 'rtsp://192.168.5.54:8554/desktop' -frames:v 10 -f null - 2>&1
"anon exit=$LASTEXITCODE"
'5b) ovifadm:'
& $ff -hide_banner -loglevel error -rtsp_transport tcp -stimeout 15000000 -i 'rtsp://ovifadm:change-onvif-password@192.168.5.54:8554/desktop' -frames:v 10 -f null - 2>&1
"onvif exit=$LASTEXITCODE"

'=== 6. bridge health + snapshot ==='
try { $r=Invoke-WebRequest -UseBasicParsing 'http://192.168.5.54:8000/health' -TimeoutSec 5; "health=$($r.StatusCode)" } catch { "health ERR $($_.Exception.Message)" }
try { $r=Invoke-WebRequest -UseBasicParsing 'http://192.168.5.54:8000/snapshot' -TimeoutSec 12; "snapshot=$($r.StatusCode) bytes=$($r.RawContentLength)" } catch { "snapshot ERR $($_.Exception.Message)" }

'=== 7. mediamtx API interna: desktop publicado e com leitores? ==='
try { $s = Invoke-RestMethod 'http://127.0.0.1:9997/v3/paths/list' -TimeoutSec 5; if($s.items){$s.items|ForEach-Object{"path=$($_.name) ready=$($_.ready) readers=$($_.readers)"}}else{'nenhum path'} } catch { "api ERR $($_.Exception.Message)" }

'=== 8. ultimas linhas do log do mediamtx (nao deve ter "invalid HTTP request" novo) ==='
Get-Content "$t-mtx.log" -Tail 5 -ErrorAction SilentlyContinue
'=== FIM ==='