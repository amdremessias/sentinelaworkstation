$Root='C:\ProgramData\HomelabScreenCamera'
$II = Get-Content (Join-Path $Root '_DI-ROOT.txt') -ErrorAction SilentlyContinue
if($II){ $Root=$II }

Write-Output ('==== state-check | ' + (Get-Date) + ' | root=' + $Root + ' ====')
Write-Output ''
Write-Output '--- porta 8554 / helper ---'
$n = Get-NetTCPConnection -LocalPort 8554 -State Listen -ErrorAction SilentlyContinue
if($n){ $p = $n | ForEach-Object { $_.OwningProcess } | Select-Object -Unique; Write-Output ('  LISTEN 8554 pid=' + ($p -join ',')) } else { Write-Output '  NAO escutando 8554' }
Write-Output '--- porta 8000 / bridge ---'
$n = Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue
if($n){ $p = $n | ForEach-Object { $_.OwningProcess } | Select-Object -Unique; Write-Output ('  LISTEN 8000 pid=' + ($p -join ',')) } else { Write-Output '  NAO escutando 8000' }
Write-Output '--- porta 8556 / mediamtx interno ---'
$n = Get-NetTCPConnection -LocalPort 8556 -State Listen -ErrorAction SilentlyContinue
if($n){ $p = $n | ForEach-Object { $_.OwningProcess } | Select-Object -Unique; Write-Output ('  LISTEN 8556 pid=' + ($p -join ',')) } else { Write-Output '  NAO escutando 8556' }
Write-Output ''
Write-Output '--- processos do stack ---'
Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'python|ffmpeg|mediamtx' } | ForEach-Object {
  $cl = [string]$_.CommandLine
  if($cl.Length -gt 120){ $cl = $cl.Substring(0,120) }
  [PSCustomObject]@{ PID=$_.ProcessId; Name=$_.Name; Cmd=$cl }
} | Format-Table -AutoSize | Out-String -Width 200

Write-Output ''
Write-Output '--- credencial ovifadm nos pontos runtime (deve conter ovifadm, NAO onvif-admin) ---'
Write-Output 'bridge.py:'
Select-String -Path (Join-Path $Root 'bridge.py') -Pattern 'RTSP_URL|ONVIF_USER|ONVIF_PASSWORD' | ForEach-Object { '  L' + $_.LineNumber + ': ' + $_.Line.Trim() }
Write-Output 'watchdog.py:'
Select-String -Path (Join-Path $Root 'watchdog.py') -Pattern 'ONVIF_USER|ONVIF_PASSWORD|RTSP_URL' | ForEach-Object { '  L' + $_.LineNumber + ': ' + $_.Line.Trim() }
Write-Output 'mediamtx.yml:'
Select-String -Path (Join-Path $Root 'mediamtx.yml') -Pattern 'user:|pass:' | ForEach-Object { '  L' + $_.LineNumber + ': ' + $_.Line.Trim() }
Write-Output ''
Write-Output '--- residual onvif-admin em .py/.ps1/.yml ativos ---'
Get-ChildItem $Root -File | Where-Object { $_.Extension -in '.py','.ps1','.yml','.yaml' -and $_.Name -notmatch '\.(old|bak|orig|pre-|pre-ovifadm|\.old\.)' } | ForEach-Object {
  $c = @(Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue)
  if($c -and $c -match 'onvif-admin'){ Write-Output ('  [RESIDUAL] ' + $_.Name) }
}
Write-Output '--- fim state-check ---'
