$ErrorActionPreference = 'Stop'
$Root = 'C:\ProgramData\HomelabScreenCamera'
$py   = Join-Path $Root 'python\venv\Scripts\python.exe'
$ff   = (Get-Command ffmpeg -ErrorAction Stop).Source
$t    = Join-Path $env:LOCALAPPDATA 'Temp\hlx'
$t0   = Get-Date

'=== 0. derruba SOMENTE o helper antigo (quem escuta 8554) + qualquer ffmpeg/pub ==='
$oldHelper = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object LocalPort -eq 8554 | Select-Object -First 1
if ($oldHelper) { $pidOld = $oldHelper.OwningProcess; "helper antigo pid=$pidOld"; Stop-Process -Id $pidOld -Force -ErrorAction SilentlyContinue }
Get-Process ffmpeg -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

'=== 1. religa helper CORRIGIDO (tupla UPSTREAM_ADDR) : 8554 publico -> 8556 interno ==='
$h = Start-Process -FilePath $py -ArgumentList @('rtsp-http-helper.py','0.0.0.0:8554','127.0.0.1:8556') -WorkingDirectory $Root -PassThru -RedirectStandardOutput "$t-helper.log" -RedirectStandardError "$t-helper-err.log"
Start-Sleep -Seconds 3
"helper alive=$([bool](Get-Process -Id $h.Id -ErrorAction SilentlyContinue)) pid=$($h.Id)"

'=== 2. quem escuta 8554 agora (deve ser helper venv python) ==='
Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object LocalPort -in 8554,8556 | ForEach-Object {
  $p = Get-CimInstance Win32_Process -Filter "ProcessId=$($_.OwningProcess)" -ErrorAction SilentlyContinue
  "{0}:{1} <- {2} (pid {3})" -f $_.LocalAddress,$_.LocalPort,$p.Name,$_.OwningProcess
}

'=== 3. publisher ffmpeg (background, nao trava o shell) ==='
$pub = Start-Process -FilePath $ff -ArgumentList @('-hide_banner','-loglevel','error','-f','gdigrab','-framerate','15','-draw_mouse','1','-i','desktop','-an','-c:v','libx264','-preset','veryfast','-tune','zerolatency','-pix_fmt','yuv420p','-profile:v','main','-g','30','-keyint_min','30','-sc_threshold','0','-b:v','3000k','-maxrate','3000k','-bufsize','6000k','-rtsp_transport','tcp','-f','rtsp','rtsp://screen-publisher:change-publish-password@127.0.0.1:8554/desktop') -WorkingDirectory $Root -PassThru -RedirectStandardOutput "$t-pub.log" -RedirectStandardError "$t-pub-err.log"
Start-Sleep -Seconds 6
"pub alive=$([bool](Get-Process -Id $pub.Id -ErrorAction SilentlyContinue))"

'=== 4. teste: probe HTTP do Intelbras (helper deve responder 200) ==='
try { $r=Invoke-WebRequest -UseBasicParsing 'http://127.0.0.1:8554/' -TimeoutSec 6; "probe HTTP -> $($r.StatusCode)" } catch { "probe ERR $($_.Exception.Message)" }

'=== 5. leitura RTSP VIA HELPER com WATCHDOG (mata em 12s, nunca pendura) ==='
function WatchdogRead([string]$label,[string]$url) {
  $out = Join-Path $Root "read-$label.log"
  Remove-Item $out -ErrorAction SilentlyContinue
  $p = Start-Process -FilePath $ff -ArgumentList @('-hide_banner','-loglevel','error','-rtsp_transport','tcp','-rw_timeout','10000000','-stimeout','10000000','-i',$url,'-frames:v','10','-f','null','-') -PassThru -RedirectStandardError $out
  $deadline = (Get-Date).AddSeconds(14)
  $done = $false
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 400
    if ($p.HasExited) { $done = $true; break }
  }
  if ($done) { "read[$label] exit=$($p.ExitCode)" }
  else { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; "read[$label] TIMEOUT (pendurou, morto pelo watchdog)" }
  if (Test-Path $out) { Get-Content $out -Tail 5 | ForEach-Object { "    $_" } }
}
'anonimo:'
WatchdogRead 'anon' 'rtsp://127.0.0.1:8554/desktop'
'ovifadm:'
WatchdogRead 'onvif' 'rtsp://ovifadm:change-onvif-password@127.0.0.1:8554/desktop'

'=== 6. bridge health + snapshot (deve funcionar agora que RTSP flui) ==='
try { $r=Invoke-WebRequest -UseBasicParsing 'http://127.0.0.1:8000/health' -TimeoutSec 6; "health=$($r.StatusCode)" } catch { "health ERR $($_.Exception.Message)" }
try { $r=Invoke-WebRequest -UseBasicParsing 'http://127.0.0.1:8000/snapshot' -TimeoutSec 15; "snapshot=$($r.StatusCode) bytes=$($r.RawContentLength)" } catch { "snapshot ERR $($_.Exception.Message)" }

"=== total: $([math]::Round(((Get-Date)-$t0).TotalSeconds))s â€” stack NO AR para o DVR ====="