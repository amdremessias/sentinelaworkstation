$Root='C:\ProgramData\HomelabScreenCamera'
if(-not (Test-Path $Root)){ $Root='C:\ProgramData\HomelabScreenCamera' }
Write-Output ('ROOT=' + $Root)
Write-Output ''
Write-Output '=== 1) arquivos ATIVOS com onvif-admin residual (exclui backups) ==='
Get-ChildItem $Root -File | Where-Object {
  $_.Name -notmatch '\.(bak|old|orig|pre-ovifadm|pre-|\.old|\.bak|\.orig)|\.(bak|old|orig)$|pre-ovifadm'
} | ForEach-Object {
  $c = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
  if($c -and $c -match 'onvif-admin'){
    Write-Output ('  [RESIDUAL] ' + $_.Name)
  }
}

Write-Output ''
Write-Output '=== 2) arquivos ativos contendo ovifadm (confirmar swap aplicado) ==='
Get-ChildItem $Root -File | Where-Object { $_.Extension -in '.py','.ps1','.yml','.yaml' -and $_.Name -notmatch '\.(bak|old|orig|pre-)|^_' } | ForEach-Object {
  $c = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
  if($c -and $c -match 'ovifadm'){ Write-Output ('  [OVIFADM] ' + $_.Name) }
}

Write-Output ''
Write-Output '=== 3) processos do stack (ativ0s) ==='
Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'python|ffmpeg|mediamtx' } | ForEach-Object {
  $cl = [string]$_.CommandLine
  if($cl.Length -gt 130){ $cl = $cl.Substring(0,130) }
  Write-Output ('  pid=' + $_.ProcessId + ' | ' + $_.Name + ' | ' + $cl)
}

Write-Output ''
Write-Output '=== 4) mediamtx.yml: usuarios (nums de linha) ==='
Get-Content (Join-Path $Root 'mediamtx.yml') | ForEach-Object -Begin {$i=0} {
  $i++
  if($_ -match '^\s*-\s*user:|^\s*pass:' ){ Write-Output ('  L' + $i + ': ' + $_.Trim()) }
}

Write-Output ''
Write-Output '=== 5) bridge.py RTSP_URL / ONVIF_USER ==='
Select-String -Path (Join-Path $Root 'bridge.py') -Pattern 'RTSP_URL|ONVIF_USER|ONVIF_PASSWORD|ovifadm|onvif-admin' | ForEach-Object { Write-Output ('  L' + $_.LineNumber + ': ' + $_.Line.Trim()) }

Write-Output ''
Write-Output '=== 6) watchdog.py env dict (credenciais publicadas) ==='
Select-String -Path (Join-Path $Root 'watchdog.py') -Pattern 'ONVIF_USER|ONVIF_PASSWORD|RTSP_URL|ovifadm|onvif-admin|base64' | ForEach-Object { Write-Output ('  L' + $_.LineNumber + ': ' + $_.Line.Trim()) }
