#!/usr/bin/env python3
"""rtsp-http-helper.py - Intelbras-ONVIF virtual-camera helper for :8554.

Answers a DVR-style anonymous OPTIONS with a local 200 (Intelbras DVRs never
attach credentials to OPTIONS; MediaMTX with auth on would 401 -> the DVR
stops). Crucially:

  * the 200 ECHOES the DVR's own CSeq (Intelbras correlates request/response
    by CSeq; a fixed \"CSeq: 1\" makes it drop the reply and re-OPTIONS
    forever - the exact \"carregando\" loop we debugged);
  * the connection is KEPT open and the remainder (DESCRIBE/SETUP/PLAY...)
    is relayed to MediaMTX on the SAME socket - what Intelbras-1 expects
    after the OPTIONS 200.

Plain HTTP probes still get an HTTP 200 local + close.
Everything else (a full RTSP request) is transparently relayed to MediaMTX.
Every byte of the optional CSeq is echoed back verbatim.
"""
import os
import socket
import sys
import threading
from datetime import datetime

LISTEN = sys.argv[1] if len(sys.argv) > 1 else "0.0.0.0:8554"
UPSTREAM = sys.argv[2] if len(sys.argv) > 2 else "127.0.0.1:8556"
LOGFILE = sys.argv[3] if len(sys.argv) > 3 else os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "_dial-8554.log"
)
LL = threading.Lock()
SS = len  # placeholder never used; avoids E501 style lint noise


def log(msg):
    line = f"[{datetime.now().strftime('%H:%M:%S.%f')[:-3]}] {msg}"
    try:
        with LL:
            with open(LOGFILE, "a", encoding="utf-8") as fh:
                fh.write(line + "\n")
    except OSError:
        pass
    print(line, flush=True)


def relay_forward(src, dst, initial=b""):
    try:
        if initial:
            dst.sendall(initial)
        while True:
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
    except OSError:
        pass
    finally:
        for s in (src, dst):
            try:
                s.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            try:
                s.close()
            except OSError:
                pass


def duplex(conn, up, initial_to_up=b""):
    # create_connection() and the initial probe read use finite timeouts, but
    # an RTSP session must survive slow DVR negotiation and idle keep-alives.
    conn.settimeout(None)
    up.settimeout(None)
    t1 = threading.Thread(target=relay_forward, args=(conn, up, initial_to_up), daemon=True)
    t2 = threading.Thread(target=relay_forward, args=(up, conn), daemon=True)
    t1.start()
    t2.start()


def echo_cseq_offset(head):
    """Return index of the CSeq header value in a request head, or None."""
    idx = head.find(b"CSeq:")
    if idx < 0:
        idx = head.find(b"Cseq:")
        if idx < 0:
            return None
    line_end = head.find(b"\r\n", idx)
    if line_end < 0:
        line_end = head.find(b"\n", idx)
    return (idx, line_end) if line_end > 0 else (idx, len(head))


def handle(conn, addr):
    conn.settimeout(6.0)
    head = b""
    try:
        while len(head) < 32000:
            chunk = conn.recv(2048)
            if not chunk:
                break
            head += chunk
            # Read the complete RTSP/HTTP header when it is available. A DVR
            # can split the request across TCP packets; classifying on the
            # first line and forwarding that partial request upstream leaves
            # MediaMTX waiting forever for the missing headers.
            if b"\r\n\r\n" in head or b"\n\n" in head:
                break
    except OSError:
        pass

    if not head:
        try:
            conn.close()
        except OSError:
            pass
        return

    first_line = head.split(b"\n", 1)[0].strip()
    method = first_line.split(b" ", 1)[0].strip().upper() if first_line else b""
    # The 6s timeout above is only for the initial probe. Do not let it kill
    # the long-lived RTSP connection while the DVR negotiates or plays.
    conn.settimeout(None)
    is_rtsp = method in (
        b"DESCRIBE", b"SETUP", b"PLAY", b"TEARDOWN", b"ANNOUNCE",
        b"RECORD", b"GET_PARAMETER", b"SET_PARAMETER", b"PAUSE",
        b"REDIRECT", b"OPTIONS",
    ) or b"RTSP/1.0" in first_line or b"rtsp://" in first_line

    if not is_rtsp:
        # Plain HTTP probe (Intelbras connectivity / web). -> 200 and close.
        log(f"CONN {addr[0]}:{addr[1]} HTTP-PROBE first=[{first_line[:80]!r}] -> 200-close")
        try:
            conn.sendall(
                b"HTTP/1.1 200 OK\r\n"
                b"Server: Intelbras-ONVIF-Virtual-Camera/1.0\r\n"
                b"Connection: close\r\n"
                b"Content-Length: 0\r\n"
                b"\r\n"
            )
        except OSError:
            pass
        try:
            conn.close()
        except OSError:
            pass
        return

    if method == b"OPTIONS":
        # Answer OPTIONS ourselves with 200, ECHOING the DVR's own CSeq
        # (Intelbras correlates by CSeq; a fixed CSeq:1 makes it re-OPTIONS
        # forever). Then keep the socket open and relay everything after the
        # OPTIONS (DESCRIBE/SETUP/PLAY) to MediaMTX on the same connection.
        cseq_hdr = echo_cseq_offset(head)
        cseq_val = b"1"
        if cseq_hdr:
            seg = head[cseq_hdr[0]:cseq_hdr[1]]
            val = seg.split(b":", 1)[1].strip() if b":" in seg else b""
            if val.isdigit():
                cseq_val = val
            log(f"CONN {addr[0]}:{addr[1]} OPTIONS CSeq={cseq_val!r} first=[{first_line[:80]!r}] -> 200-local-echo-CSeq-KEEPALIVE")
        else:
            log(f"CONN {addr[0]}:{addr[1]} OPTIONS (sem CSeq) first=[{first_line[:80]!r}] -> 200-local-CSeq1-KEEPALIVE")

        resp = (
            b"RTSP/1.0 200 OK\r\n"
            b"CSeq: " + cseq_val + b"\r\n"
            b"Public: OPTIONS, DESCRIBE, SETUP, TEARDOWN, PLAY, PAUSE, "
            b"GET_PARAMETER, SET_PARAMETER\r\n"
            b"Server: Intelbras-ONVIF-Virtual-Camera/1.0\r\n"
            b"\r\n"
        )
        try:
            conn.sendall(resp)
        except OSError:
            try:
                conn.close()
            except OSError:
                pass
            return

        # Keep the socket open and relay the rest to MediaMTX.
        try:
            up = socket.create_connection(
                (UPSTREAM.rsplit(":", 1)[0], int(UPSTREAM.rsplit(":", 1)[1])),
                timeout=8.0,
            )
            up.settimeout(None)
        except OSError as e:
            log(f"CONN {addr[0]}:{addr[1]} OPTIONS upstream-ERR {e!r} -> close")
            try:
                conn.close()
            except OSError:
                pass
            return
        # The local OPTIONS response replaces the original request. Only
        # forward bytes after its complete header (usually the next pipelined
        # RTSP request); never forward a partial OPTIONS line upstream.
        rest = b""
        idx = head.find(b"\r\n\r\n")
        if idx >= 0:
            rest = head[idx + 4:]
        else:
            idx = head.find(b"\n\n")
            if idx >= 0:
                rest = head[idx + 2:]
        duplex(conn, up, rest)
        return

    # Real RTSP request (DESCRIBE/SETUP/PLAY/...) -> proxy to MediaMTX.
    log(f"CONN {addr[0]}:{addr[1]} RTSP first=[{first_line[:80]!r}] -> relay")
    try:
        up = socket.create_connection(
            (UPSTREAM.rsplit(":", 1)[0], int(UPSTREAM.rsplit(":", 1)[1])),
            timeout=8.0,
        )
        up.settimeout(None)
        up.sendall(head)
    except OSError as e:
        log(f"CONN {addr[0]}:{addr[1]} upstream-ERR {e!r} -> close")
        try:
            conn.close()
        except OSError:
            pass
        return
    try:
        duplex(conn, up)
    except Exception:
        pass


def main():
    host, port = LISTEN.rsplit(":", 1)
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((host, int(port)))
    srv.listen(128)
    log(f"HELPER-UP listen={LISTEN} upstream={UPSTREAM} -> OPTIONS-200-ECHO-CSEQ-KEEPALIVE")
    while True:
        try:
            conn, addr = srv.accept()
        except OSError:
            break
        threading.Thread(target=handle, args=(conn, addr), daemon=True).start()


if __name__ == "__main__":
    main()
