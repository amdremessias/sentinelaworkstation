#!/usr/bin/env python3
"""watchdog.py - keeps the HomelabScreenCamera stack alive.

Every CHECK interval it makes sure:
  * MediaMTX (RTSP :8556 loopback) is listening
  * ONVIF bridge (:8000) answers /health
  * rtsp-http-helper (:8554) is listening
  * the 'desktop' path is being published (MediaMTX API on 127.0.0.1:9997);
    if not, it restarts the ffmpeg gdigrab publisher

Children are launched hidden (CREATE_NO_WINDOW) with the same commands as
stack-full-up.ps1. All restart events are logged to _watchdog.log.

Single-instance guard: binds 127.0.0.1:48127 as a lock; if it is already
bound, this process exits immediately.
"""
import os
import shutil
import socket
import subprocess
import sys
import time

ROOT = r"C:\ProgramData\HomelabScreenCamera"
PY = os.path.join(ROOT, "python", "venv", "Scripts", "python.exe")
MTX = os.path.join(ROOT, "mediamtx.exe")
MTX_CFG = os.path.join(ROOT, "mediamtx.yml")
BRIDGE = os.path.join(ROOT, "bridge.py")
HELPER = os.path.join(ROOT, "rtsp-http-helper.py")
WATCHDOG_LOG = os.path.join(ROOT, "_watchdog.log")
LOCK_PORT = 48127
CHECK_SECONDS = 10

FFMPEG = (
    os.getenv("FFMPEG")
    or shutil.which("ffmpeg")
    or r"C:\Users\m3ss14s\AppData\Local\Microsoft\WinGet\Packages\Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe\ffmpeg-9.0-full_build\bin\ffmpeg.exe"
)

BRIDGE_ENV = {
    "DEVICE_IP": "192.168.5.54",
    "HTTP_PORT": "8000",
    "ONVIF_USER": "ovifadm",
    "ONVIF_PASSWORD": "change-onvif-password",
    "RTSP_URL": "rtsp://ovifadm:change-onvif-password@192.168.5.54:8554/desktop",
    "BIND_IP": "0.0.0.0",
}

PUBLISH_ARGS = [
    "-hide_banner", "-loglevel", "error",
    "-f", "gdigrab", "-framerate", "25", "-draw_mouse", "1", "-i", "desktop",
    # The Intelbras DVR decodes only streams whose resolution matches the
    # ONVIF-advertised size (1920x1080) and whose H.264 level <= 4.1. The
    # desktop is often ultrawide (e.g. 2966x900) which the DVR cannot
    # decode, so scale + letterbox to 1080p and cap the level.
    # Camera-typical PAL encoding for strict HW decoders: 25 fps with VUI
    # (BT.709 colorimetry so x264 emits timing_info), GOP 50 (2 s), and
    # sliced-threads off (-tune zerolatency enables it, producing ~20
    # slices/frame unlike real cameras' 1 slice/frame).
    "-vf", "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2",
    "-pix_fmt", "yuv420p", "-profile:v", "baseline", "-level:v", "3.1",
    "-g", "50", "-keyint_min", "50",
    "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709",
    "-x264-params", "sliced-threads=0",
    "-sc_threshold", "0", "-b:v", "3000k", "-maxrate", "3000k", "-bufsize", "6000k",
    # Add silent audio track (some Dahua/Intelbras DVRs require audio to decode video)
    "-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=48000",
    "-c:a", "aac", "-b:a", "64k", "-ar", "48000", "-ac", "2",
    "-map", "0:v:0", "-map", "1:a:0",
    "-rtsp_transport", "tcp", "-f", "rtsp",
    "rtsp://screen-publisher:change-publish-password@127.0.0.1:8556/desktop",
]


def log(msg):
    line = "[%s] %s" % (time.strftime("%H:%M:%S"), msg)
    print(line, flush=True)
    try:
        with open(WATCHDOG_LOG, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass


def tcp_up(host, port, timeout=1.0):
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


def bridge_healthy():
    # Plain TCP/HTTP to avoid urllib honoring system proxies (which breaks
    # loopback checks and makes the watchdog think the bridge is down).
    try:
        import http.client
        c = http.client.HTTPConnection("127.0.0.1", 8000, timeout=2)
        c.request("GET", "/health")
        r = c.getresponse()
        ok = r.status == 200
        c.close()
        if ok:
            return True
    except Exception:
        pass
    try:
        import http.client
        c = http.client.HTTPConnection("192.168.5.54", 8000, timeout=2)
        c.request("GET", "/health")
        r = c.getresponse()
        ok = r.status == 200
        c.close()
        return ok
    except Exception:
        return False


def desktop_ready():
    # Raw RTSP DESCRIBE against the internal MediaMTX listener: MediaMTX
    # answers 200 OK only while someone is publishing the path, and errors
    # (404/456/401) when it is offline. This avoids the authenticated HTTP
    # API (which needs credentials and returns 401 without them).
    import base64
    try:
        s = socket.create_connection(("127.0.0.1", 8556), timeout=3)
        s.settimeout(3)
        auth = base64.b64encode(b"ovifadm:change-onvif-password").decode()
        req = (
            "DESCRIBE rtsp://127.0.0.1:8556/desktop RTSP/1.0\r\n"
            "CSeq: 1\r\n"
            "Authorization: Basic %s\r\n"
            "Accept: application/sdp\r\n"
            "\r\n" % auth
        )
        s.sendall(req.encode())
        data = b""
        while b"\r\n\r\n" not in data:
            chunk = s.recv(4096)
            if not chunk:
                break
            data += chunk
        s.close()
        first = data.split(b"\r\n", 1)[0].decode("utf-8", "replace")
        return "200" in first
    except Exception:
        try:
            s.close()
        except Exception:
            pass
        return False


def spawn(args, out, err, env=None):
    full_env = dict(os.environ)
    if env:
        full_env.update(env)
    out_h = open(out, "w", encoding="utf-8")
    err_h = open(err, "w", encoding="utf-8")
    try:
        creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
        return subprocess.Popen(
            args, cwd=ROOT, env=full_env,
            stdout=out_h, stderr=err_h,
            creationflags=creationflags,
        )
    except Exception as e:
        log("FALHA ao iniciar %s: %r" % (args[0], e))
        return None


def ensure(name, needed, start, logfile):
    if needed():
        return
    log("SUBINDO %s" % name)
    spawn(start, logfile + "-out.log", logfile + "-err.log")


def main():
    # Single instance: try to hold the lock port.
    lock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        lock.bind(("127.0.0.1", LOCK_PORT))
        lock.listen(1)
    except OSError:
        log("outro watchdog ativo; saindo")
        sys.exit(0)

    log("watchdog iniciado (check a cada %ds)" % CHECK_SECONDS)
    while True:
        try:
            # 1. MediaMTX
            if not tcp_up("127.0.0.1", 8556):
                log("SUBINDO mediamtx")
                spawn([MTX, MTX_CFG], os.path.join(ROOT, "_mtx-out.log"), os.path.join(ROOT, "_mtx-err.log"))
                time.sleep(2)
            # 2. Bridge (HTTP :8000)
            if not bridge_healthy():
                log("SUBINDO bridge.py")
                br_env = dict(BRIDGE_ENV)
                spawn([PY, BRIDGE], os.path.join(ROOT, "_bridge-out.log"), os.path.join(ROOT, "_bridge-err.log"), env=br_env)
                time.sleep(2)
            # 3. Helper (:8554)
            if not tcp_up("127.0.0.1", 8554):
                log("SUBINDO rtsp-http-helper")
                spawn([PY, HELPER, "0.0.0.0:8554", "127.0.0.1:8556"], os.path.join(ROOT, "_helper-out.log"), os.path.join(ROOT, "_helper-err.log"))
                time.sleep(1)
            # 4. Publisher (stream ready?)
            if not desktop_ready():
                log("SUBINDO publisher ffmpeg (stream desktop offline)")
                spawn([FFMPEG] + PUBLISH_ARGS, os.path.join(ROOT, "_pub-out.log"), os.path.join(ROOT, "_pub-err.log"))
        except Exception as e:
            log("erro no ciclo do watchdog: %r" % e)
        time.sleep(CHECK_SECONDS)


if __name__ == "__main__":
    main()