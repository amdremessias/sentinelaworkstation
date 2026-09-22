$ErrorActionPreference = 'Stop'
$Root = 'C:\ProgramData\HomelabScreenCamera'
$py   = Join-Path $Root 'python\venv\Scripts\python.exe'
$ff   = (Get-Command ffmpeg -ErrorAction Stop).Source
$t    = Join-Path $env:LOCALAPPDATA 'Temp\hlq'
$t0   = Get-Date

'=== 0. derruba o HELPER VELHO (quem escuta 8554, vai rodar o codigo novo) + publisher ==='
$c = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -eq 8554 } | Select-Object -First 1
if ($c) { "helper antigo pid=$($c.OwningProcess)"; Stop-Process -Id $c.OwningProcess -Force -ErrorAction SilentlyContinue }
Get-Process ffmpeg -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

'=== 1. sobe helper NOVO (codigo do disco, tupla) na 8554 publico -> 8556 interno ==='
$h = Start-Process -FilePath $py -ArgumentList @((Join-Path $Root 'rtsp-http-helper.py'),'0.0.0.0:8554','127.0.0.1:8556') -WorkingDirectory $Root -PassThru -RedirectStandardOutput "$t-h.log" -RedirectStandardError "$t-h-err.log"
Start-Sleep -Seconds 4
"helper alive=$([bool](Get-Process -Id $h.Id -ErrorAction SilentlyContinue)) pid=$($h.Id)"

'=== 2. quem escuta 8000/8554/8556 agora ==='
Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -in 8000,8554,8556 } | ForEach-Object {
  $p = Get-CimInstance Win32_Process -Filter "ProcessId=$($_.OwningProcess)" -ErrorAction SilentlyContinue
  "{0}:{1} <- {2} (pid {3})" -f $_.LocalAddress,$_.LocalPort,$p.Name,$_.OwningProcess
}

'=== 3. publisher ffmpeg VIA HELPER (publica desktop pela 8554 -> 8556) ==='
$pub = Start-Process -FilePath $ff -ArgumentList @('-hide_banner','-loglevel','error','-f','gdigrab','-framerate','15','-draw_mouse','1','-i','desktop','-an','-c:v','libx264','-preset','veryfast','-tune','zerolatency','-pix_fmt','yuv420p','-profile:v','main','-g','30','-sc_threshold','0','-b:v','3000k','-maxrate','3000k','-bufsize','6000k','-rtsp_transport','tcp','-f','rtsp','rtsp://screen-publisher:change-publish-password@192.168.5.54:8554/desktop') -WorkingDirectory $Root -PassThru -RedirectStandardError "$t-pub.log"
Start-Sleep -Seconds 6
"publisher alive=$([bool](Get-Process -Id $pub.Id -ErrorAction SilentlyContinue))"

'=== 4. PROBE HTTP do Intelbras -> helper responde 200 (DVR fica verde) ==='
try { $r=Invoke-WebRequest -UseBasicParsing 'http://192.168.5.54:8554/' -TimeoutSec 8; "probe HTTP -> $($r.StatusCode)" } catch { "probe ERR $($_.Exception.Message)" }

'=== 5. leitura RTSP via helper com WATCHDOG (mata em 20s, nao pendura) ==='
function TestRead($label,$url){
  $out = "$t-$label.log"
  $job = Start-Job -ScriptBlock { param($ff,$url) & $ff -hide_banner -loglevel error -rtsp_transport tcp -i $url -frames:v 10 -f null - 2>&1; "exit=$LASTEXITCODE" } -ArgumentList $ff,$url
  if (Wait-Job $job -Timeout 20) { "[$label] $(Receive-Job $job)" } else { Stop-Job $job -ErrorAction SilentlyContinue; "[$label] TIMEOUT(20s) - matado" }
  Remove-Job $job -Force -ErrorAction SilentlyContinue
}
TestRead 'anon' 'rtsp://192.168.5.54:8554/desktop'
TestRead 'onvif' 'rtsp://ovifadm:change-onvif-password@192.168.5.54:8554/desktop'

'=== 6. bridge health + snapshot ==='
try { $r=Invoke-WebRequest -UseBasicParsing 'http://192.168.5.54:8000/health' -TimeoutSec 6; "health=$($r.StatusCode)" } catch { "health ERR $($_.Exception.Message)" }
try { $r=Invoke-WebRequest -UseBasicParsing 'http://192.168.5.54:8000/snapshot' -TimeoutSec 15; "snapshot=$($r.StatusCode) bytes=$($r.RawContentLength)" } catch { "snapshot ERR $($_.Exception.Message)" }

"=== total $([math]::Round(((Get-Date)-$t0).TotalSeconds))s - stack NO AR p/ DVR testar ==="
