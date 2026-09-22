$Root = 'C:\ProgramData\HomelabScreenCamera'
$out = Join-Path $Root '_chk-after-readd.txt'
Add-Content $out ('=== chk-after-readd ' + (Get-Date) + ' ===')
$lines | ForEach-Object { Add-Content $out $_ ; Write-Output $_ }
