Get-Process ffmpeg,mediamtx,python -ErrorAction SilentlyContinue | Where-Object { $_.Path -match 'HomelabScreenCamera|ffmpeg' -or $_.ProcessName -eq 'mediamtx' } | Stop-Process -Force
Write-Host 'Transmissão e componentes beta encerrados.'
