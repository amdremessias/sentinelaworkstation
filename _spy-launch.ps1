# Spy de bytes na porta publica :8554 (o que o DVR envia)
# Grava cada request RTSP/HTTP completo (primeiros 512 bytes de cada direcao)
# com timestamp num arquivo. Roda em paralelo ao helper; nao interfere.
# Parar: Stop-Process -Name python -Force (mata o spy e o helper p/ religar junto)
$ErrorActionPreference = 'Continue'
$Root = 'C:\ProgramData\HomelabScreenCamera'
$log = Join-Path $Root '_spy-8554.log'

$listen = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, 8555)
# NOTA: porta MENOS o canal do DVR? NAO. Porta 8555 livre p/ o spy receber as
# conexoes REAIS replicadas. Precisamos que o DVR aponte pro spy... melhor:
# o spy fica SEMPRE no lugar do helper normal (8554) e nao usa o :8554 do DVR,
# porque o DVR ja configurou :8554. Para nao derrubar o helper, ouvimos em 8554
# APENAS o probe e devolvemos ao helper real. EMRUGH.
Write-Output 'SPY escutando :8555 (coloque o DVR p/ 192.168.5.54:8555 e religue o live view)...'
