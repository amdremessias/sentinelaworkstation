#!/usr/bin/env python3
"""
RTSP-port proxy with HTTP probe answer for Intelbras DVRs.
Intelbras MHDX DVRs, when verifying an ONVIF camera, connect to the RTSP
port and send an HTTP request expecting a 200 (documented Intelbras quirk).
MediaMTX only speaks RTSP there, so the probe fails and the camera never
turns green. This proxy answers the HTTP probe with 200 and forwards real
RTSP to MediaMTX on an internal port.

Usage: bridge_rtsp_proxy.py <listen_port> <upstream_rtsp_host> <upstream_rtsp_port>
Example: bridge_rtsp_proxy.py 8554 127.0.0.1 8556
"""
import socket
import sys
import threading
import time

LISTEN_PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8554
UPSTREAM_HOST = sys.argv[2] if len(sys.argv) > 2 else "127.0.0.1"
UPSTREAM_PORT = int(sys.argv[3]) if len(sys.argv) > 3 else 8556

RTSP_METHODS = {
    "OPTIONS", "DESCRIBE", "SETUP", "PLAY", "TEARDOWN",
    "ANNOUNCE", "RECORD", "GET_PARAMETER", "SET_PARAMETER", "PAUSE",
}

HTTP_200 = (
    b"HTTP/1.1 200 OK\r\n"
    b"Server: Intelbras-ONVIF-Camera\r\n"
    b"Connection: close\r\n"
    b"Content-Length: 0\r\n"
    b"\r\n"
)


def relay(src, dst):
    try:
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


def handle(conn, addr):
    conn.settimeout(5.0)
    try:
        first = b""
        while len(first) < 2048:
            chunk = conn.recv(512)
            if not chunk:
                break
            first += chunk
            # enough to classify: look at the first token
            if b"\n" in first:
                break
    except OSError:
        try:
            conn.close()
        except OSError:
            pass
        return

    if not first:
        try:
            conn.close()
        except OSError:
            pass
        return

    # Classify: if first token is a known RTSP method -> forward to MediaMTX.
    is_rtsp = False
    try:
        token = first.split(b" ", 1)[0].decode("ascii").strip().upper()
        is_rtsp = token in RTSP_METHODS
    except Exception:
        is_rtsp = False

    if is_rtsp:
        # Forward (including the bytes already read) to upstream RTSP server.
        up = socket.create_connection((UPSTREAM_HOST, UPSTREAM_PORT), timeout=8.0)
        # The connect timeout must not become an RTSP session timeout.
        conn.settimeout(None)
        up.settimeout(None)
        up.sendall(first)
        t1 = threading.Thread(target=relay, args=(conn, up), daemon=True)
        t2 = threading.Thread(target=relay, args=(up, conn), daemon=True)
        t1.start()
        t2.start()
        t1.join()
        t2.join()
    else:
        # HTTP probe (Intelbras verification) -> answer 200.
        try:
            conn.sendall(HTTP_200)
        except OSError:
            pass
        try:
            conn.close()
        except OSError:
            pass


def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("0.0.0.0", LISTEN_PORT))
    srv.listen(128)
    print("proxy on :%d -> %s:%d" % (LISTEN_PORT, UPSTREAM_HOST, UPSTREAM_PORT), flush=True)
    while True:
        try:
            conn, addr = srv.accept()
        except OSError:
            break
        threading.Thread(target=handle, args=(conn, addr), daemon=True).start()


if __name__ == "__main__":
    main()
