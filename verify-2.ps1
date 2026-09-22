$ErrorActionPreference = 'Stop'
$Root = 'C:\ProgramData\HomelabScreenCamera'
$ff   = (Get-Command ffmpeg -ErrorAction Stop).Source
$t0   = Get-Date

'=== 2. processos vivos? ==='
Get-Process mediamtx,python,python3.11,ffmpeg -ErrorAction SilentlyContinue |
  Select-Object ProcessName,Id,StartTime | Format-Table -AutoSize

'=== 3. mediamtx interno: o path /desktop esta publicado? (API 9997) ==='
try {
  $l = Invoke-RestMethod 'http://127.0.0.1:9997/v3/paths/list' -TimeoutSec 6
  if ($l.items) { $l.items | ForEach-Object { "  path=$($_.name) ready=$($_.ready) readers=$($_.readers)" } } else { '  (nenhum path)' }
} catch { "  api ERR $($_.Exception.Message)" }

'=== 4. PROBE HTTP do Intelbras (deve dar 200) ==='
try { $r=Invoke-WebRequest -UseBasicParsing 'http://192.168.5.54:8554/' -TimeoutSec 8; "  probe=$($r.StatusCode)" } catch { "  probe ERR $($_.Exception.Message)" }

'=== 5. leitura RTSP via helper com watchdog de 22s ==='
function DoRead([string]$label,[string]$url){
  $out = Join-Path $env:TEMP "hl-$label.log"
  $p = Start-Process -FilePath $ff -ArgumentList @('-hide_banner','-loglevel','error','-rtsp_transport','tcp','-i',$url,'-frames:v','10','-f','null','-') -PassThru -RedirectStandardError $out -RedirectStandardOutput "$out.out"
  $deadline = (Get-Date).AddSeconds(22)
  $done = $false
  while ((Get-Date) -lt $deadline) {
    if ($p.HasExited) { $done=$true; break }
    Start-Sleep -Milliseconds 400
  }
  if ($done) { "  $label exit=$($p.ExitCode)" }
  else { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; "  $label TIMEOUT (22s) - pendurou" }
  if (Test-Path $out) { $e=Get-Content $out -Tail 4 -ErrorAction SilentlyContinue; if($e){ $e | ForEach-Object { "      $_" } } }
}
'5a) anonimo via helper:'
DoRead 'anon' 'rtsp://192.168.5.54:8554/desktop'
'5b) ovifadm via helper:'
DoRead 'onvif' 'rtsp://ovifadm:change-onvif-password@192.168.5.54:8554/desktop'

'=== 6. bridge health + snapshot ==='
try { $r=Invoke-WebRequest -UseBasicParsing 'http://192.168.5.54:8000/health' -TimeoutSec 6; "  health=$($r.StatusCode)" } catch { "  health ERR $($_.Exception.Message)" }
try { $r=Invoke-WebRequest -UseBasicParsing 'http://192.168.5.54:8000/snapshot' -TimeoutSec 12; "  snapshot=$($r.StatusCode) bytes=$($r.RawContentLength)" } catch { "  snapshot ERR $($_.Exception.Message)" }

"=== total $([math]::Round(((Get-Date)-$t0).TotalSeconds))s ==="
'=== FIM (stack segue NO AR para o DVR testar) ==='