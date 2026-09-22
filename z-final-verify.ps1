$ErrorActionPreference = 'Stop'
$Root = 'C:\ProgramData\HomelabScreenCamera'
$py   = Join-Path $Root 'python\venv\Scripts\python.exe'
$mtx  = Join-Path $Root 'mediamtx.exe'
$ff   = (Get-Command ffmpeg -ErrorAction Stop).Source
$ffx  = (Get-Command ffprobe -ErrorAction Stop).Source
$t    = "$env:LOCALAPPDATA\Temp\hsc-final"
$t0   = Get-Date

'=== 0. derruba helper antigo em memoria (8554) + publisher + ffmpeg ==='
$a = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object LocalPort -eq 8554 | Select-Object -First 1
if ($a) { $old=$a.OwningProcess; "helper-antigo pid=$old"; Stop-Process -Id $old -Force -ErrorAction SilentlyContinue }
Get-Process ffmpeg -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

'=== 1. helper novo (arquivo corrigido com tupla) na 8554 publico ==> 8556 interno ==='
$hn = Start-Process -FilePath $py -ArgumentList @((Join-Path $Root 'rtsp-http-helper.py'),'0.0.0.0:8554','127.0.0.1:8556') -WorkingDirectory $Root -PassThru -RedirectStandardOutput "$t-helper.log" -RedirectStandardError "$t-helper-err.log"
Start-Sleep -Seconds 4
'=== 2. quem escuta 8554 agora ==='
Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object LocalPort -eq 8554 | ForEach-Object {
  $pp = Get-CimInstance Win32_Process -Filter "ProcessId=$($_.OwningProcess)" -ErrorAction SilentlyContinue
  "8554 <- $($pp.Name) pid=$($_.OwningProcess)"
}

'=== 3. probe HTTP do Intelbras => helper deve dar 200 (DVR fica verde) ==='
try { $r=Invoke-WebRequest -UseBasicParsing 'http://192.168.5.54:8554/' -TimeoutSec 8; "probe=$($r.StatusCode)" } catch { "probe ERR $($_.Exception.Message)" }

'=== 4. leitura RTSP via helper com WATCHDOG (kill apos 15s, nunca pendura) ==='
function TestRead($label,$url) {
  $p = Start-Process -FilePath $ff -ArgumentList @('-hide_banner','-loglevel','error','-rtsp_transport','tcp','-i',$url,'-frames:v','10','-f','null','-') -PassThru -RedirectStandardError "$t-$label.log"
  $deadline = (Get-Date).AddSeconds(15)
  $alive = $true
  while ((Get-Date) -lt $deadline) {
    if ($p.HasExited) { $alive=$false; break }
    Start-Sleep -Milliseconds 400
  }
  if ($alive) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; "$label = TIMEOUT(15s)" }
  else { "$label = exit $($p.ExitCode)" }
}
'4a) anon:'
TestRead 'anon' 'rtsp://192.168.5.54:8554/desktop'
'4b) ovifadm:'
TestRead 'onvif' 'rtsp://ovifadm:change-onvif-password@192.168.5.54:8554/desktop'

'=== 5. bridge health + snapshot via LAN ==='
try { $r=Invoke-WebRequest -UseBasicParsing 'http://192.168.5.54:8000/health' -TimeoutSec 5; "health=$($r.StatusCode)" } catch { "health ERR $($_.Exception.Message)" }
try { $r=Invoke-WebRequest -UseBasicParsing 'http://192.168.5.54:8000/snapshot' -TimeoutSec 12; "snapshot=$($r.StatusCode) bytes=$($r.RawContentLength)" } catch { "snapshot ERR $($_.Exception.Message)" }

"=== total $([math]::Round(((Get-Date)-$t0).TotalSeconds))s | stack NO AR p/ o DVR testar ==="