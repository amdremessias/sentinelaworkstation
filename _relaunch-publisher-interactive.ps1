$Root = 'C:\ProgramData\HomelabScreenCamera'
$ff   = (Get-Command ffmpeg -ErrorAction Stop).Source
$t    = Join-Path $Root ('_interactive-pub-' + (Get-Date -Format 'HHmmss'))
$pubLog = $t + '-pub.log'
$pubErr = $t + '-pub-err.log'

'=== publisher INTERATIVO (sessao logada, tela desbloqueada) | ' + (Get-Date) + ' ==='

# Mata publisher antigo (morto mesmo, mas por garantia)
Get-Process ffmpeg -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# Publica desktop -> mediamtx interno :8556 (mesmos args do stack-full-up.ps1)
$pub = Start-Process -FilePath $ff `
    -ArgumentList @('-hide_banner','-loglevel','error','-f','gdigrab','-framerate','25','-draw_mouse','1','-i','desktop',`
        '-an','-c:v','libx264','-preset','veryfast','-tune','zerolatency','-pix_fmt','yuv420p','-profile:v','main','-g','50','-keyint_min','50',`
        '-sc_threshold','0','-b:v','3000k','-maxrate','3000k','-bufsize','6000k',`
        '-rtsp_transport','tcp','-f','rtsp','rtsp://screen-publisher:change-publish-password@127.0.0.1:8556/desktop') `
    -WorkingDirectory $Root -PassThru `
    -RedirectStandardOutput $pubLog -RedirectStandardError $pubErr

Start-Sleep -Seconds 6

# Verifica se o mediamtx passou a ter o desktop publicado (API 9997)
'--- verifica publicacao do desktop (6s depois) ---'
try {
    $r = Invoke-RestMethod -Uri 'http://127.0.0.1:9997/v3/paths/list' -TimeoutSec 5 -ErrorAction Stop
    $r.items | ForEach-Object { '  path=' + $_.name + ' ready=' + $_.ready + ' viewers=' + $_.viewers }
} catch { '  API 9997 erro: ' + $_.Exception.Message }

# ffmpeg vivo?
$f = @(Get-Process ffmpeg -ErrorAction SilentlyContinue)
'  ffmpeg count=' + @($f).Count

'=== fim | pid pub=' + $pub.Id + ' | log=' + $pubErr + ' ==='
