$ErrorActionPreference = 'Continue'
$Root = 'C:\ProgramData\HomelabScreenCamera'
$Py = Join-Path $Root 'python\venv\Scripts\python.exe'
if (-not (Test-Path $Py)) { $Py = Join-Path $Root 'python\venv\Scripts\python.exe' }

# Kill ONLY old bridge python (leave helper :8554 and spy :8554 running)
Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'HomelabScreenCamera' -and $_.CommandLine -notmatch 'rtsp-http-helper|_dp' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 1

# Environment must match what mediamtx.yml expects (internal :8556 upstream)
$env:DEVICE_IP = '192.168.5.54'
$env:HTTP_PORT = '8000'
$env:ONVIF_USER = 'ovifadm'
$env:ONVIF_PASSWORD = 'change-onvif-password'
$env:RTSP_URL = 'rtsp://ovifadm:change-onvif-password@192.168.5.54:8554/desktop'

$br = Start-Process -FilePath $Py `
    -ArgumentList @((Join-Path $Root 'bridge.py')) `
    -WorkingDirectory $Root `
    -RedirectStandardOutput (Join-Path $Root '_bridge-out.log') `
    -RedirectStandardError (Join-Path $Root '_bridge-err.log') `
    -PassThru
Start-Sleep -Seconds 3

Write-Output '=== bridge :8000 ==='
try { $r = Invoke-WebRequest 'http://127.0.0.1:8000/health' -UseBasicParsing -TimeoutSec 6 }
catch { Write-Output ('  ERR ' + $_.Exception.Message); exit 1 }
Write-Output ('  /health -> ' + [int]$r.StatusCode + ' ' + $r.Content)
Write-Output '=== OK: agora DVR deve VOLTAR A APARECER a camera 192.168.5.54 na lista ONVIF + conseguir religar verde ==='
Write-Output 'Solicito: religa o DVR agora (PESQUISAR/cadastro), a camera deve reaparecer. Deixa o live ]>20s e me fala.'