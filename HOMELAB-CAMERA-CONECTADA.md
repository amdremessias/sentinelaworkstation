# HomelabScreenCamera â€” VersÃ£o que CONECTA no DVR Intelbras

> Status: **DVR mostra canal VERDE, canal CONECTADO, e o preview de vÃ­deo funciona com o stream 1920x1080.**

Este documento registra a versÃ£o funcional da cÃ¢mera virtual ONVIF (captura da tela do PC â†’
stream RTSP â†’ DVR Intelbras `192.168.5.31`) e o *porquÃª* das correÃ§Ãµes que a fizeram conectar
e exibir vÃ­deo.

---

## 1. Resumo do que foi corrigido (e por que conectou)

| # | Problema | Causa raiz | CorreÃ§Ã£o |
|---|----------|------------|----------|
| 1 | DVR nÃ£o adicionava a cÃ¢mera ("Falha SOAP invÃ¡lida") | Bridge respondia no namespace **Media 1.0 (trt)**; o DVR Intelbras usa **Media 2.0 (tr2)** em `/onvif/media2_service` | Bridge responde em **tr2** (ver20/tr2) conforme WSDL ver20 da ONVIF |
| 2 | DVR sondava anonimamente e falhava | GetCapabilities/GetScopes precisam responder **sem autenticaÃ§Ã£o** (spec ONVIF; o firmware Intelbras sonda anÃ´nimo primeiro) | GetCapabilities/GetScopes anÃ´nimos no bridge |
| 3 | DVR ficava num loop sem chamar GetStreamUri | AnÃºncio ONVIF incompleto (sem StreamingCapabilities/ProfileCapabilities) | `capabilities()` anuncia StreamingCapabilities (RTP_TCP, RTP_RTSP_TCP), ProfileCapabilities, Events |
| 4 | **Preview "carregando" para sempre (vÃ­deo nÃ£o sobe no DVR)** | O stream publicado era a **resoluÃ§Ã£o nativa da tela (2966x900, ultrawide) com nÃ­vel H.264 5.0**, mas o ONVIF anuncia **1920x1080** â€” o DVR Ã© estrito: decodifica sÃ³ a resoluÃ§Ã£o anunciada com nÃ­vel â‰¤ 4.1 (o VLC aceita qualquer coisa, o DVR nÃ£o) | Publisher escala a captura para **1920x1080** (letterbox, mantÃ©m proporÃ§Ã£o) e forÃ§a **`-level:v 4.0`**, perfil Main, GOP 30, yuv420p |

**â†’ O item 4 era o "falta pouco":** o canal jÃ¡ ficava verde (o DVR valida o RTSP na adiÃ§Ã£o),
mas o preview nunca carregava porque a imagem recebida (2966x900 / level 5.0) nÃ£o era decodificÃ¡vel
pelo hardware do DVR. Depois de padronizar o stream em 1920x1080 nÃ­vel 4.0, o DVR exibe.

---

## 2. Arquitetura (topologia real)

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   gdigrab (ffmpeg)   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   RTSP TCP   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚  Desktop PC â”‚ â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â–¶ â”‚  MediaMTX    â”‚ â—€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ â”‚  rtsp-http-  â”‚
â”‚ (tela real) â”‚   15 fps Â· H264      â”‚ 127.0.0.1:8556 â”‚   interno    â”‚  helper.py   â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   1920x1080 lvl 4.0  â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜              â”‚ 0.0.0.0:8554 â”‚
                                                                   â””â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”˜
                                                                          â”‚ RTSP TCP pÃºblico
                                                                          â”‚ + probe HTTP 200
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”  SOAP ONVIF (tr2)    â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”                    â–¼
â”‚  DVR Intelbrasâ”‚ â—€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ â”‚  bridge.py   â”‚        â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚ 192.168.5.31 â”‚  GET/POST :8000     â”‚ 0.0.0.0:8000 â”‚        â”‚ URL entregue ao DVR: â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜                      â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜        â”‚ rtsp://ovifadm:â€¦â”‚
                                                             â”‚  @192.168.5.54:8554/ â”‚
                                                             â”‚  desktop             â”‚
                                                             â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
                        watchdog.py â€” revive qualquer peÃ§a da stack em â‰¤ 10 s
```

- **MediaMTX** (`mediamtx.yml`): servidor RTSP **interno**, escondido da LAN (`rtspAddress 127.0.0.1:8556`). Recebe o publish do ffmpeg e entrega o stream.
- **rtsp-http-helper.py** (`0.0.0.0:8554`): face **pÃºblica** para o DVR. Responde o probe HTTP da Intelbras com **200** (exigÃªncia do DVR) e tunela o RTSP real para o MediaMTX interno.
- **bridge.py** (`0.0.0.0:8000`): ponte ONVIF 2.0 (Media 2.0 / tr2) que o DVR consulta â€” perfis, stream URI, OSD, mÃ¡scaras, analytics, encoder options.
- **watchdog.py**: supervisor â€” verifica a stack com socket cru (DESCRIBE RTSP + HTTP) e revive ffmpeg/bridge/helper/mediamtx quando necessÃ¡rio.

### O caminho do vÃ­deo no DVR
1. DVR consulta `http://192.168.5.54:8000` (SOAP ONVIF, namespace **tr2**).
2. `GetProfiles` â†’ bridge entrega perfil `profile_1` com **1920x1080 / H264**.
3. `GetStreamUri` â†’ bridge devolve `rtsp://ovifadm:change-onvif-password@192.168.5.54:8554/desktop`.
4. DVR conecta em `:8554` (probe HTTP 200 â†’ RTSP TCP) e lÃª o stream H264 **1920x1080, Main, level 4.0, 15 fps**.

---

## 3. ParÃ¢metros do publisher (ffmpeg gdigrab)

```powershell
ffmpeg -hide_banner -loglevel error `
  -f gdigrab -framerate 15 -draw_mouse 1 -i desktop `
  -vf "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2" `
  -an -c:v libx264 -preset veryfast -tune zerolatency `
  -pix_fmt yuv420p -profile:v main -level:v 4.0 `
  -g 30 -keyint_min 30 -sc_threshold 0 `
  -b:v 3000k -maxrate 3000k -bufsize 6000k `
  -rtsp_transport tcp -f rtsp `
  rtsp://screen-publisher:change-publish-password@127.0.0.1:8556/desktop
```

| ParÃ¢metro | Valor | Motivo |
|-----------|-------|--------|
| `-f gdigrab -i desktop` | captura da tela | o que o usuÃ¡rio quer transmitir |
| `-framerate 15` | 15 fps | sobra p/ DVR sem pesar na CPU |
| `-vf scale=1920:1080:force_original_aspect_ratio=decrease,pad=...` | 1920x1080 letterbox | **resoluÃ§Ã£o anunciada no ONVIF â‰ˆ resoluÃ§Ã£o real** (sem distorcer ultrawide) |
| `-profile:v main -level:v 4.0` | Main / 4.0 | **decodificaÃ§Ã£o garantida no DVR** (nÃ­vel â‰¤ 4.1; level 5.0 da tela nativa nÃ£o decodificava) |
| `-g 30 -keyint_min 30` | GOP 2 s | keyframe frequente â†’ preview abre rÃ¡pido |
| `-tune zerolatency` | baixa latÃªncia | sem B-frames/lookahead, Ãºtil p/ screen capture |
| `-rtsp_transport tcp` | TCP | DVR Intelbras usa TCP (media2 `RTP_TCP`/`RTP_RTSP_TCP`) |

> **Nota (ffmpeg 9.0):** nÃ£o usar `-stimeout` / `-rw_timeout` â€” essa build nÃ£o aceita;
> apenas `-rtsp_transport tcp`.

---

## 4. Credenciais e endpoints

| Item | Valor |
|------|-------|
| UsuÃ¡rio ONVIF | `ovifadm` / `change-onvif-password` |
| UsuÃ¡rio publish (mediamtx) | `screen-publisher` / `change-publish-password` |
| URL RTSP pÃºblica (vai pro DVR) | `rtsp://ovifadm:change-onvif-password@192.168.5.54:8554/desktop` |
| URL RTSP interna (publish) | `rtsp://screen-publisher:change-publish-password@127.0.0.1:8556/desktop` |
| Ponte ONVIF (SOAP) | `http://192.168.5.54:8000` (endpooints `/onvif/device_service`, `/onvif/media2_service`, etc.) |
| Health/Snapshot | `http://127.0.0.1:8000/health`, `http://127.0.0.1:8000/snapshot` |

### DVR (192.168.5.31)
- Adicionar canal por protocolo **ONVIF** (Intelbras-1 Ã© protocolo privado Dahua/porta 37777 â€” **nÃ£o** serve para a cÃ¢mera virtual).
- Porta HTTP ONVIF: **8000** (se o DVR teimar na 80, o bridge precisa de listener extra na 80).

---

## 5. Subir a stack (caminho canÃ´nico)

```powershell
cd C:\ProgramData\HomelabScreenCamera
powershell -ExecutionPolicy Bypass -File .\stack-full-up.ps1
```

O script sobe mediamtx â†’ bridge â†’ helper â†’ publisher (janela fica visÃ­vel durante a captura) â†’ **watchdog**, e verifica listeners, processos, probe HTTP e stream.

### Parar
```powershell
powershell -ExecutionPolicy Bypass -File .\stop-visible.ps1
```

### VerificaÃ§Ã£o rÃ¡pida
```powershell
# stream publicado (deve ser 1920x1080, Main, level 4.0, 15fps)
.\ffprobe -rtsp_transport tcp -show_entries stream=width,height,profile,level,r_frame_rate -of json "rtsp://ovifadm:change-onvif-password@127.0.0.1:8556/desktop"

# ponte viva
Invoke-WebRequest http://127.0.0.1:8000/health

# DVR conectado no helper (RemoteAddress 192.168.5.31)
Get-NetTCPConnection | ? { $_.LocalPort -eq 8554 -and $_.State -eq 'Established' }
```

### RegressÃµes (todas PASS nesta versÃ£o)
```powershell
.\python\venv\Scripts\python.exe .\soap-selftest.py      # selftest ONVIF
.\python\venv\Scripts\python.exe .\_dvr-flow-test.py     # fluxo DVR (GetCapabilities anÃ´nimo + tr2)
.\python\venv\Scripts\python.exe .\_cfg-ops-test.py      # ops de configuraÃ§Ã£o (OSD/mask/analytics/encoder)
```

---

## 6. Arquivos-chave

| Arquivo | Papel |
|---------|-------|
| `bridge.py` | Ponte ONVIF Media 2.0 (tr2) â€” perfis, stream URI, capabilities, OSD/mask/analytics |
| `mediamtx.yml` | MediaMTX interno `127.0.0.1:8556` (usuÃ¡rios publish/read) |
| `rtsp-http-helper.py` | Probe HTTP 200 Intelbras + proxy RTSP pÃºblico `:8554` â†’ `:8556` |
| `watchdog.py` | Supervisor auto-heal (`PUBLISH_ARGS` contÃ©m os parÃ¢metros H264 corretos) |
| `stack-full-up.ps1` | Script canÃ´nico de subida + verificaÃ§Ã£o (inicia o watchdog ao final) |
| `start-visible.ps1` | Subida manual com captura em janela visÃ­vel (usa `:8554` direto) |
| `_bridge-dump.log` | Dump das requisiÃ§Ãµes SOAP do DVR (diagnÃ³stico de quirks) |
| `_mtx-out.log` | Log do MediaMTX (sessÃµes `created`/`is reading`/`destroyed`) |

---

## 7. DiagnÃ³stico rÃ¡pido se algo falhar

| Sintoma | Verificar | AÃ§Ã£o |
|---------|-----------|------|
| Canal vermelho / "Falha SOAP" | `_bridge-dump.log` tem requisiÃ§Ã£o? `Invoke-WebRequest http://192.168.5.54:8000/health` | Ponte caiu? watchdog sobe em â‰¤10 s; conferir namespace tr2 no log |
| Verde mas preview travado | ffprobe no `:8556`: width/height/prof/level | Deve ser `1920x1080 / Main / 40` â€” se voltou ao nativo da tela, o publisher antigo subiu (reiniciar watchdog) |
| DVR nÃ£o conecta no RTSP | `Get-NetTCPConnection LocalPort 8554` | DVR conectado? probe HTTP 200? helper vivo? |
| SessÃ£o cai toda hora | `_mtx-out.log` `destroyed: terminated` | Reconectar/readonar o canal ou reiniciar DVR p/ limpar sessÃ£o antiga |

---

## 8. PendÃªncias conhecidas (nÃ£o bloqueiam)

- **Autostart**: nÃ£o existe tarefa "no logon". O publisher exige sessÃ£o interativa; pendente agendar `stack-full-up.ps1` no logon.
- **Porta HTTP 80**: se o DVR ignorar "Porta HTTP: 8000" na adiÃ§Ã£o (fixar ONVIF na 80), falta listener extra na porta 80 no bridge.
- **ResoluÃ§Ã£o da tela**: se a tela mudar (ex.: conectar um monitor maior), o letterbox recalcula sozinho â€” o stream continua 1920x1080.