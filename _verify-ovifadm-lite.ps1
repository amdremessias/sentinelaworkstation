$Root = 'C:\ProgramData\HomelabScreenCamera'
$ff = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source

Write-Output ('=== verify read-only ovifadm | ' + (Get-Date) + ' ===')

function Probe-RawPort([int]$port, [string]$method, [string]$path, [string]$extra) {
  try {
    $s = New-Object System.Net.Sockets.TcpClient
    $s.Connect('127.0.0.1', $port)
    $st = $s.GetStream()
    $req = "$method $path RTSP/1.0`r`nCSeq: 1`r`n$extra`r`n"
    $b = [Text.Encoding]::ASCII.GetBytes($req)
    $st.Write($b, 0, $b.Length); $st.Flush()
    Start-Sleep -Milliseconds 500
    $buf = New-Object byte[] 2048
    $n = $st.Read($buf, 0, $buf.Length)
    Write-Output ("  reply: " + [Text.Encoding]::ASCII.GetString($buf, 0, $n).Trim())
    $st.Close(); $s.Close()
  } catch { Write-Output ('  ERRO: ' + $_.Exception.Message) }
}

Write-Output '--- bridge :8000 /health ---'
try { $h = Invoke-WebRequest 'http://127.0.0.1:8000/health' -UseBasicParsing -TimeoutSec 8; Write-Output ('  status=' + [int]$h.StatusCode) } catch { Write-Output ('  ERRO: ' + $_.Exception.Message) }
Write-Output '--- bridge :8000 /snapshot ---'
try { $h = Invoke-WebRequest 'http://127.0.0.1:8000/snapshot' -UseBasicParsing -TimeoutSec 20; Write-Output ('  status=' + [int]$h.StatusCode + ' bytes=' + $h.RawContentLength) } catch { Write-Output ('  ERRO: ' + $_.Exception.Message) }
Write-Output '--- helper :8554 OPTIONS (anon) ---'
Probe-RawPort 8554 'OPTIONS' 'rtsp://127.0.0.1:8554/desktop' ''
Write-Output '--- helper :8554 GET_PARAMETER (ovifadm) ---'
Probe-RawPort 8554 'GET_PARAMETER' 'rtsp://127.0.0.1:8554/desktop' 'Authorization: Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('ovifadm:change-onvif-password'))

function Test-Read([string]$label, [string]$url) {
  $o = & $ff -hide_banner -loglevel error -rtsp_transport tcp -stimeout 15000000 -i $url -frames:v 6 -f null - 2>&1
  Write-Output ("  " + $label + " | exit=" + $LASTEXITCODE)
}

Write-Output '== leitura RTSP via helper :8554 (anon | ovifadm) =='
Test-Read 'anon   ' 'rtsp://127.0.0.1:8554/desktop'
Test-Read 'ovifadm' 'rtsp://ovifadm:change-onvif-password@127.0.0.1:8554/desktop'
Write-Output '== leitura RTSP interno :8556 ovifadm =='
Test-Read 'ovifadm' 'rtsp://ovifadm:change-onvif-password@127.0.0.1:8556/desktop'

Write-Output '== processos do stack =='
Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'python|ffmpeg|mediamtx' } | ForEach-Object {
  $cl = [string]$_.CommandLine
  if($cl.Length -gt 130){ $cl = $cl.Substring(0,130) }
  Write-Output ('  pid=' + $_.ProcessId + ' | ' + $_.Name + ' | ' + $cl)
}
Write-Output '=== fim | ' + (Get-Date) + ' ==='
