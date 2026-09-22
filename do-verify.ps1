$ErrorActionPreference = 'Stop'
$Root = 'C:\ProgramData\HomelabScreenCamera'
$py   = Join-Path $Root 'python\venv\Scripts\python.exe'
$mtx  = Join-Path $Root 'mediamtx.exe'
$ff   = (Get-Command ffmpeg -ErrorAction Stop).Source
$t    = "$env:LOCALAPPDATA\Temp\hlv"
$t0 = Get-Date

'=== 0. derruba tudo ==='
Get-Process python,python3,python3.11,mediamtx,mediamtx.exe,ffmpeg -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

'=== 1. sobe: mediamtx(interno) + bridge(8000) + helper(8554 publico) ==='
$m = Start-Process -FilePath $mtx -ArgumentList (Join-Path $Root 'mediamtx.yml') -WorkingDirectory $Root -PassThru -RedirectStandardOutput "$t-mtx.log" -RedirectStandardError "$t-mtx-err.log"
$pyExe = (Get-Command $py -ErrorAction SilentlyContinue)
if (-not (Test-Path $py)) { throw "venv python NAO existe em $py" }
$b = Start-Process -FilePath $py -ArgumentList (Join-Path $Root 'bridge.py') -WorkingDirectory $Root -PassThru -RedirectStandardOutput "$t-bridge.log" -RedirectStandardError "$t-bridge-err.log"
$h = Start-Process -FilePath $py -ArgumentList @('rtsp-http-helper.py','0.0.0.0:8554','127.0.0.1:8556') -WorkingDirectory $Root -PassThru -RedirectStandardOutput "$t-helper.log" -RedirectStandardError "$t-helper-err.log"
Start-Sleep -Seconds 4

'=== 2. quem escuta 8000/8554/8556 ==='
Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -in 8000,8554,8556 } | ForEach-Object {
  $pw = Get-CimInstance Win32_Process -Filter "ProcessId=$($_.OwningProcess)" -ErrorAction SilentlyContinue
  "{0}:{1} <- {2} (pid {3})" -f $_.LocalAddress,$_.LocalPort,$pw.Name,$_.OwningProcess
}

'=== 3. publisher em background via helper 8554 (nao bloqueia) ==='
$pub = Start-Process -FilePath $ff -ArgumentList @('-hide_banner','-loglevel','error','-f','gdigrab','-framerate','15','-draw_mouse','1','-i','desktop','-an','-c:v','libx264','-preset','veryfast','-tune','zerolatency','-pix_fmt','yuv420p','-profile:v','main','-g','30','-keyint_min','30','-sc_threshold','0','-b:v','3000k','-maxrate','3000k','-bufsize','6000k','-rtsp_transport','tcp','-f','rtsp','rtsp://screen-publisher:change-publish-password@192.168.5.54:8554/desktop') -WorkingDirectory $Root -PassThru -RedirectStandardOutput "$t-pub.log" -RedirectStandardError "$t-pub-err.log"
Start-Sleep -Seconds 6
"publisher alive=$([bool](Get-Process -Id $pub.Id -ErrorAction SilentlyContinue))"

'=== 4. PROBE HTTP do Intelbras (helper deve responder 200) ==='
try { $r=Invoke-WebRequest -UseBasicParsing 'http://192.168.5.54:8554/' -TimeoutSec 8; "probe HTTP exit=$($r.StatusCode)" } catch { "probe ERR $($_.Exception.Message)" }

'=== 5. leitura RTSP VIA HELPER com -stimeout (nao pendura) ==='
'5a) anonimo:'
& $ff -hide_banner -loglevel error -rtsp_transport tcp -stimeout 15000000 -i 'rtsp://192.168.5.54:8554/desktop' -frames:v 10 -f null - 2>&1
"anon exit=$LASTEXITCODE"
'5b) ovifadm:'
& $ff -hide_banner -loglevel error -rtsp_transport tcp -stimeout 15000000 -i 'rtsp://ovifadm:change-onvif-password@192.168.5.54:8554/desktop' -frames:v 10 -f null - 2>&1
"ovifadm exit=$LASTEXITCODE"

'=== 6. bridge health + snapshot via IP LAN ==='
try { $r=Invoke-WebRequest -UseBasicParsing 'http://192.168.5.54:8000/health' -TimeoutSec 8; "health=$($r.StatusCode)" } catch { "health ERR $($_.Exception.Message)" }
try { $r=Invoke-WebRequest -UseBasicParsing 'http://192.168.5.54:8000/snapshot' -TimeoutSec 15; "snapshot=$($r.StatusCode) bytes=$($r.RawContentLength)" } catch { "snapshot ERR $($_.Exception.Message)" }

'=== 7. mediamtx API: stream desktop publicado? (via 9997 se ligada) ==='
try { $s=Invoke-RestMethod 'http://127.0.0.1:9997/v3/paths/list' -TimeoutSec 5; if($s.items){$s.items|ForEach-Object{" path=$($_.name) ready=$($_.ready) readers=$($_.readers)"}}; 'api OK' } catch { "api ERR $($_.Exception.Message)" }

"=== total segundos: $([math]::Round(((Get-Date)-$t0).TotalSeconds)) ==="
'=== FIM ==='