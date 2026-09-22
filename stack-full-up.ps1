$ErrorActionPreference = 'Continue'

$Root = 'C:\ProgramData\HomelabScreenCamera'
$PyHidden = Join-Path $Root 'python\venv\Scripts\python.exe'
$Py = $PyHidden
if (-not (Test-Path $Py)) { $Py = Join-Path $Root 'python\venv\Scripts\python.exe' }

$BridgeScript = Join-Path $Root 'bridge.py'
$HelperScript = Join-Path $Root 'rtsp-http-helper.py'
$MtxExe = Join-Path $Root 'mediamtx.exe'
$MtxCfg = Join-Path $Root 'mediamtx.yml'
$FFmpeg = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
if (-not $FFmpeg) { $FFmpeg = Join-Path $Root 'ffmpeg.exe' }

$OutLog = Join-Path $Root '_stack-out.log'
$ErrLog = Join-Path $Root '_stack-err.log'

function Log($m) {
    $line = '[' + (Get-Date -Format 'HH:mm:ss') + '] ' + $m
    Write-Output $line
    Add-Content -Path $OutLog -Value $line
}

# ============================================================
# 1. Kill old instances of the stack
# ============================================================
Log 'Killing old stack processes...'
Get-Process -Name 'mediamtx' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process -Name 'ffmpeg' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'HomelabScreenCamera' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 2

# ============================================================
# 2. MediaMTX (internal RTSP :8556)
# ============================================================
Log 'Starting MediaMTX (:8556) ...'
$mtx = Start-Process -FilePath $MtxExe `
    -ArgumentList @($MtxCfg) `
    -WorkingDirectory $Root `
    -RedirectStandardOutput (Join-Path $Root '_mtx-out.log') `
    -RedirectStandardError (Join-Path $Root '_mtx-err.log') `
    -PassThru
Start-Sleep -Seconds 2

# ============================================================
# 3. ONVIF bridge (:8000)
# ============================================================
Log 'Starting bridge.py (:8000) ...'
$env:DEVICE_IP = '192.168.5.54'
$env:HTTP_PORT = '8000'
$env:ONVIF_USER = 'ovifadm'
$env:ONVIF_PASSWORD = 'change-onvif-password'
$env:RTSP_URL = 'rtsp://ovifadm:change-onvif-password@192.168.5.54:8554/desktop'
$br = Start-Process -FilePath $Py `
    -ArgumentList @($BridgeScript) `
    -WorkingDirectory $Root `
    -RedirectStandardOutput (Join-Path $Root '_bridge-out.log') `
    -RedirectStandardError (Join-Path $Root '_bridge-err.log') `
    -PassThru

# ============================================================
# 4. Helper (public :8554 -> internal :8556)
# ============================================================
Log 'Starting rtsp-http-helper.py (:8554 -> 127.0.0.1:8556) ...'
$hl = Start-Process -FilePath $Py `
    -ArgumentList @($HelperScript, '0.0.0.0:8554', '127.0.0.1:8556') `
    -WorkingDirectory $Root `
    -RedirectStandardOutput (Join-Path $Root '_helper-out.log') `
    -RedirectStandardError (Join-Path $Root '_helper-err.log') `
    -PassThru
Start-Sleep -Seconds 2

# ============================================================
# 5. Publisher ffmpeg DIRECT to internal :8556
#  Note: watchdog.py also spawns ffmpeg with matching PUBLISH_ARGS.
# ============================================================
# (Publisher is spawned by watchdog; keep this block for reference only)
Log 'Publisher args are defined in watchdog.py PUBLISH_ARGS. If you want to override via this script, edit the -profile:v, -level:v, -g, -keyint_min, -framerate below.'
Log 'Starting publisher ffmpeg (gdigrab -> rtsp://...@127.0.0.1:8556/desktop) ...'
$pub = Start-Process -FilePath $FFmpeg `
    -ArgumentList @(
        "-hide_banner","-loglevel","error",
        "-f","gdigrab","-framerate","25","-draw_mouse","1","-i","desktop",
        "-vf","scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2",
        "-an","-c:v","libx264","-preset","veryfast","-tune","zerolatency",
        "-pix_fmt","yuv420p","-profile:v","baseline","-level:v","4.0","-g","50","-keyint_min","50",
        "-colorspace","bt709","-color_primaries","bt709","-color_trc","bt709",
        "-x264-params","sliced-threads=0",
        "-sc_threshold","0","-b:v","3000k","-maxrate","3000k","-bufsize","6000k",
        "-rtsp_transport","tcp","-f","rtsp",
        "rtsp://screen-publisher:change-publish-password@127.0.0.1:8556/desktop"
    ) `
    -WorkingDirectory $Root `
    -RedirectStandardOutput (Join-Path $Root '_pub-out.log') `
    -RedirectStandardError (Join-Path $Root '_pub-err.log') `
    -PassThru

Start-Sleep -Seconds 6

# ============================================================
# 5b. Watchdog (mantem a stack viva: revive publisher/helper/etc.)
# ============================================================
Log 'Starting watchdog.py (auto-heal) ...'
$wd = Start-Process -FilePath $Py `
    -ArgumentList @((Join-Path $Root 'watchdog.py')) `
    -WorkingDirectory $Root `
    -RedirectStandardOutput (Join-Path $Root '_watchdog-out.log') `
    -RedirectStandardError (Join-Path $Root '_watchdog-err.log') `
    -PassThru
Start-Sleep -Seconds 2

# ============================================================
# 6. Verify
# ============================================================
Log '=== STACK STARTED ==='
Log '--- listeners ---'
Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
    Where-Object { $_.LocalPort -in 8000,8554,8556 } |
    Select-Object LocalAddress,LocalPort,OwningProcess |
    Sort-Object LocalPort |
    ForEach-Object { Log ('  listen ' + $_.LocalAddress + ':' + $_.LocalPort + ' pid=' + $_.OwningProcess) }

Log '--- process alive ---'
foreach ($pair in @(
        @('mediamtx', $mtx),
        @('bridge', $br),
        @('helper', $hl),
        @('publisher-ffmpeg', $pub),
        @('watchdog', $wd))) {
    $p = Get-Process -Id $pair[1].Id -ErrorAction SilentlyContinue
    if ($p) { Log ('  ALIVE ' + $pair[0] + ' (pid ' + $p.Id + ')') }
    else { Log ('  DEAD  ' + $pair[0]) }
}

Log '--- HTTP probe on :8554 (what the DVR does) ---'
$sock = New-Object System.Net.Sockets.TcpClient
try {
    $sock.Connect('127.0.0.1', 8554)
    $st = $sock.GetStream()
    $req = [Text.Encoding]::ASCII.GetBytes("GET /onvif/device_service HTTP/1.0`r`n`r`n")
    $st.Write($req, 0, $req.Length)
    $st.Flush()
    Start-Sleep -Milliseconds 500
    $buf = New-Object byte[] 2048
    try { $n = $st.Read($buf, 0, $buf.Length) } catch { $n = 0 }
    if ($n -gt 0) { Log ('  probe reply: ' + [Text.Encoding]::ASCII.GetString($buf, 0, $n).Trim()) }
    else { Log '  probe reply: (empty)' }
    $st.Close()
} catch {
    Log ('  probe ERROR: ' + $_.Exception.Message)
}
$sock.Close()

Log '--- bridge health + snapshot ---'
try {
    $h = Invoke-WebRequest -Uri 'http://127.0.0.1:8000/health' -UseBasicParsing -TimeoutSec 8
    Log ('  /health -> ' + [int]$h.StatusCode)
} catch { Log ('  /health ERROR: ' + $_.Exception.Message) }
try {
    $s = Invoke-WebRequest -Uri 'http://127.0.0.1:8000/snapshot' -UseBasicParsing -TimeoutSec 20
    Log ('  /snapshot -> ' + [int]$s.StatusCode + ' bytes=' + $s.RawContentLength)
} catch { Log ('  /snapshot ERROR: ' + $_.Exception.Message) }

Log '=== DONE ==='
