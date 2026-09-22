$ErrorActionPreference='Stop'
$Root='C:\ProgramData\HomelabScreenCamera'
$py=Join-Path $Root 'python\venv\Scripts\python.exe'
$mt=(Join-Path $Root 'mediamtx.exe')
$ff=(Get-Command ffmpeg -ErrorAction Stop).Source
$t=Join-Path $env:LOCALAPPDATA 'Temp\hlx4'
$t0=Get-Date

'=== 0. derruba TUDO (stack limpo) ==='
Get-Process python,python3.11,mediamtx,mediamtx.exe,ffmpeg -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

'=== 1. sobe: mediamtx interno(8556) + bridge(8000) + helper PUBLICO(8554->8556) ==='
$m=Start-Process -FilePath $mt -ArgumentList (Join-Path $Root 'mediamtx.yml') -WorkingDirectory $Root -PassThru -RedirectStandardOutput "$t-mtx.log" -RedirectStandardError "$t-mtx-err.log"
$b=Start-Process -FilePath $py -ArgumentList (Join-Path $Root 'bridge.py') -WorkingDirectory $Root -PassThru -RedirectStandardOutput "$t-br.log" -RedirectStandardError "$t-br-err.log"
$h=Start-Process -FilePath $py -ArgumentList @((Join-Path $Root 'rtsp-http-helper.py'),'0.0.0.0:8554','127.0.0.1:8556') -WorkingDirectory $Root -PassThru -RedirectStandardOutput "$t-h.log" -RedirectStandardError "$t-h-err.log"
Start-Sleep -Seconds 4

'=== 2. quem escuta 8000/8554/8556 agora ==='
Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object LocalPort -in 8000,8554,8556 | ForEach-Object {
  $p=Get-CimInstance Win32_Process -Filter "ProcessId=$($_.OwningProcess)" -ErrorAction SilentlyContinue
  "{0}:{1} <- {2} (pid {3})" -f $_.LocalAddress,$_.LocalPort,$p.Name,$_.OwningProcess
}

'=== 3. publisher ffmpeg DIRETO ao interno 8556 (sem helper no publish) ==='
$pub=Start-Process -FilePath $ff -ArgumentList @('-hide_banner','-loglevel','error','-f','gdigrab','-framerate','15','-draw_mouse','1','-i','desktop','-an','-c:v','libx264','-preset','veryfast','-tune','zerolatency','-pix_fmt','yuv420p','-profile:v','main','-g','30','-keyint_min','30','-sc_threshold','0','-b:v','3000k','-maxrate','3000k','-bufsize','6000k','-rtsp_transport','tcp','-f','rtsp','rtsp://screen-publisher:change-publish-password@127.0.0.1:8556/desktop') -WorkingDirectory $Root -PassThru -RedirectStandardOutput "$t-pub.log" -RedirectStandardError "$t-pub-err.log"
Start-Sleep -Seconds 8
"publisher alive=$([bool](Get-Process -Id $pub.Id -ErrorAction SilentlyContinue))"
Get-Content "$t-pub-err.log" -Tail 8 -ErrorAction SilentlyContinue

'=== 4. PROBE HTTP do Intelbras -> helper deve responder 200 (DVR verde) ==='
try { $r=Invoke-WebRequest -UseBasicParsing 'http://192.168.5.54:8554/' -TimeoutSec 8; "probe=$($r.StatusCode)" } catch { "probe ERR $($_.Exception.Message)" }

'=== 5. leitura RTSP VIA HELPER com watchdog 20s (nao pendura) ==='
function TestRead($label,$url){
  $j=Start-Job -ScriptBlock { param($ff,$u) & $ff -hide_banner -loglevel error -rtsp_transport tcp -i $u -frames:v 10 -f null - 2>&1; "exit=$LASTEXITCODE" } -ArgumentList $ff,$url
  if (Wait-Job $j -Timeout 22) { "[$label] $(Receive-Job $j)" } else { Stop-Job $j -ErrorAction SilentlyContinue; "[$label] TIMEOUT(22s)" }
  Remove-Job $j -Force -ErrorAction SilentlyContinue
}
'5a) anonimo (via helper 8554):'
TestRead 'anon' 'rtsp://192.168.5.54:8554/desktop'
'5b) ovifadm (via helper 8554):'
TestRead 'onvif' 'rtsp://ovifadm:change-onvif-password@192.168.5.54:8554/desktop'

'=== 6. bridge health + snapshot ==='
try { $r=Invoke-WebRequest -UseBasicParsing 'http://192.168.5.54:8000/health' -TimeoutSec 6; "health=$($r.StatusCode)" } catch { "health ERR $($_.Exception.Message)" }
try { $r=Invoke-WebRequest -UseBasicParsing 'http://192.168.5.54:8000/snapshot' -TimeoutSec 15; "snapshot=$($r.StatusCode) bytes=$($r.RawContentLength)" } catch { "snapshot ERR $($_.Exception.Message)" }

"=== total $([math]::Round(((Get-Date)-$t0).TotalSeconds))s - stack NO AR p/ DVR testar ==="
