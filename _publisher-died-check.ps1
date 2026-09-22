$Root = 'C:\ProgramData\HomelabScreenCamera'
$out = Join-Path $Root '_publisher-died-check.log'
Function W($m){ Add-Content -Path $out -Value $m; Write-Output $m }
W ('=== publisher dead check | ' + (Get-Date) + ' ===')

# 1) processos ffmpeg/ffplay/vlc + publisher relacionado
W '--- processos ---'
$cand = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match 'ffmpeg|ffplay|vlc|mediamtx' } |
  Select-Object ProcessId,Name,ParentProcessId
$cand | ForEach-Object { W ('  pid=' + $_.ProcessId + ' ' + $_.Name + ' parent=' + $_.ParentProcessId) }
W ('  ffmpeg=' + @($cand | Where-Object Name -eq 'ffmpeg.exe').Count + ' vlc=' + @($cand | Where-Object Name -eq 'vlc.exe').Count)

# 2) log mediamtx — procurar quando perdeu o publisher e linhas desktop recentes
$m = Get-ChildItem $Root -File -Filter '*mediamtx*log*' | Where-Object { $_.Name -notmatch 'lined' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($m) {
  W ('--- mediamtx log: ' + $m.Name + ' | ' + $m.LastWriteTime + ' | lines=' + @(Get-Content $m.FullName).Count)
  # registrar quando foi a ultima leitura/leitor e o que ocorre agora
  W '  (ultimas linhas com desktop / publisher)'
  Get-Content $m.FullName | Where-Object { $_ -match 'desktop' } | Select-Object -Last 8 | ForEach-Object { W ('    ' + $_) }
}

# 3) launcher / watchdog log (motivo da queda do publisher)
W '--- logs watchdog/stack ---'
$wd = @(Get-ChildItem $Root -File -Filter '*watchdog*.log' | Sort-Object LastWriteTime -Descending | Select-Object -First 2)
foreach ($f in $wd) {
  W ('  [' + $f.Name + ' | ' + $f.LastWriteTime + ']')
  Get-Content $f.FullName | Select-Object -Last 15 | ForEach-Object { W ('    ' + $_) }
}
W ('--- fim ' + (Get-Date) + ' ---')
