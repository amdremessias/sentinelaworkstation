$ErrorActionPreference='Stop'
$Root='C:\ProgramData\HomelabScreenCamera'
$py=Join-Path $Root 'python\venv\Scripts\python.exe'
$ff=(Get-Command ffmpeg -ErrorAction Stop).Source
$t=Join-Path $env:LOCALAPPDATA 'Temp\relaunch-clean'
$t0=Get-Date

'== 0. derruba helper ANTIGO (que rodava o codigo com bug da string) + publisher =='
$conn8554=Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object {$_.LocalPort -eq 8554} | Select-Object -First 1
if($conn8554){$oldpid=$conn8554.OwningProcess; "helper antigo pid=$oldpid"; Stop-Process -Id $oldpid -Force -ErrorAction SilentlyContinue}
Get-Process ffmpeg -ErrorAction SilentlyContinue|Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

'== 1. sobe helper CORRIGIDO (disco tem UPSTREAM_ADDR tupla) na 8554 publico -> 8556 interno =='
$h=Start-Process -FilePath $py -ArgumentList @((Join-Path $Root 'rtsp-http-helper.py'),'0.0.0.0:8554','127.0.0.1:8556') -WorkingDirectory $Root -PassThru -RedirectStandardOutput "$t-h.log" -RedirectStandardError "$t-h-err.log"
Start-Sleep -Seconds 4
"helper alive=$([bool](Get-Process -Id $h.Id -ErrorAction SilentlyContinue)) pid=$($h.Id)"

'== 2. quem escuta 8554 agora (deve ser o venv helper) =='
Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue|Where-Object {$_.LocalPort -eq 8554}|ForEach-Object{$p=Get-CimInstance Win32_Process -Filter "ProcessId=$($_.OwningProcess)" -ErrorAction SilentlyContinue; "8554 <- $($p.Name) pid=$($_.OwningProcess)"}

'== 3. PROBE HTTP do Intelbras (helper responde 200, DVR fica verde) =='
try{$r=Invoke-WebRequest -UseBasicParsing 'http://192.168.5.54:8554/' -TimeoutSec 8; "probe=$($r.StatusCode)"}catch{"probe ERR $($_.Exception.Message)"}

'== 4. publisher ffmpeg -> 8554 publico (helper repassa pro interno 8556) =='
$ffa=@('-hide_banner','-loglevel','error','-f','gdigrab','-framerate','15','-draw_mouse','1','-i','desktop','-an','-c:v','libx264','-preset','veryfast','-tune','zerolatency','-pix_fmt','yuv420p','-profile:v','main','-g','30','-keyint_min','30','-sc_threshold','0','-b:v','3000k','-maxrate','3000k','-bufsize','6000k','-rtsp_transport','tcp','-f','rtsp','rtsp://screen-publisher:change-publish-password@127.0.0.1:8554/desktop')
$p=Start-Process -FilePath $ff -ArgumentList $ffa -WorkingDirectory $Root -PassThru -RedirectStandardOutput "$t-pub.log" -RedirectStandardError "$t-pub-err.log"
Start-Sleep -Seconds 8
"publisher alive=$([bool](Get-Process -Id $p.Id -ErrorAction SilentlyContinue)) pid=$($p.Id)"

'== 5. leitura RTSP VIA HELPER publico com WATCHDOG 25s (matar se pendurar, NAO bloqueia) =='
function TestRead($label,$url){
  $j=Start-Job -ArgumentList $ff,$url -ScriptBlock { param($f,$u) & $f -hide_banner -loglevel error -rtsp_transport tcp -i $u -frames:v 10 -f null - 2>&1; "exit=$LASTEXITCODE" }
  if(Wait-Job $j -Timeout 25){"[$label] $((Receive-Job $j)|Out-String)"} else {Stop-Job $j; "[$label] TIMEOUT(25s)"}
  Remove-Job $j -Force -ErrorAction SilentlyContinue
}
'5a anonimo:'
TestRead anon 'rtsp://192.168.5.54:8554/desktop'
'5b ovifadm:'
TestRead onvif 'rtsp://ovifadm:change-onvif-password@192.168.5.54:8554/desktop'

'== 6. bridge health + snapshot =='
try{$r=Invoke-WebRequest -UseBasicParsing 'http://192.168.5.54:8000/health' -TimeoutSec 6;"health=$($r.StatusCode)"}catch{"health ERR $($_.Exception.Message)"}
try{$r=Invoke-WebRequest -UseBasicParsing 'http://192.168.5.54:8000/snapshot' -TimeoutSec 12;"snapshot=$($r.StatusCode) bytes=$($r.RawContentLength)"}catch{"snapshot ERR $($_.Exception.Message)"}

"=== total $([math]::Round(((Get-Date)-$t0).TotalSeconds))s â€” stack NO AR p/ DVR testar ==="
'=== helper log =='
Get-Content "$t-h.log" -Tail 4 -ErrorAction SilentlyContinue
'=== helper err (deve estar vazio = sem ValueError) =='
Get-Content "$t-h-err.log" -Tail 6 -ErrorAction SilentlyContinue