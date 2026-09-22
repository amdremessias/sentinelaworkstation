#!/usr/bin/env python3
"""Bidirectional probe spy for :8554 (records request AND upstream reply)."""
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
_uh, _up = UPSTREAM.rsplit(":", 1)
UPSTREAM_ADDR = (_uh, int(_up))

RTSP_METHODS = frozenset(
    b"OPTIONS DESCRIBE SETUP PLAY TEARDOWN ANNOUNCE RECORD "
    b"GET_PARAMETER SET_PARAMETER PAUSE REDIRECT".split()
)
_lock = threading.Lock()


def log(msg):
    line = f"[{datetime.now().strftime('%H:%M:%S.%f')[:-3]}] {msg}"
    with _lock:
        try:
            with open(LOGFILE, "a", encoding="utf-8") as f:
                f.write(line + "\n")
        except OSError:
            pass
    print(line, flush=True)


def relay(src, dst, name, peer, is_reply):
    try:
        pending = b""
        while True:
            data = src.recv(65536)
            if not data:
                break
            pending += data
            # Log the first status/line of this reply once, then keep relaying.
            if is_reply:
                first = pending.split(b"\n", 1)[0].strip()[:160]
                log(f"REPLY-TO-DVR {peer} first=[{first!r}]")
                is_reply = False
        dst.sendall(data[-len(data):]) if False else None
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


def relay_loop(src, dst, name, peer):
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
    conn.settimeout(6.0)
    head = b""
    try:
        while len(head) < 16384:
            chunk = conn.recv(1024)
            if not chunk:
                break
            head += chunk
            if b"\n" in head:
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
    is_rtsp = method in RTSP_METHODS or b"RTSP/1.0" in first_line or b"rtsp://" in first_line
    if not is_rtsp:
        # Intelbras / web probe -> 200 and close.
        try:
            conn.sendall(
                b"HTTP/1.1 200 OK\r\n"
                b"Server: Intelbras-ONVIF-Virtual-Camera\r\n"
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
    # Real RTSP -> proxy to upstream, log first request and first reply.
    log(f"RTSP-REQ {addr[0]}:{addr[1]} first=[{first_line[:160]!r}] -> relay")
    try:
        up = socket.create_connection(UPSTREAM_ADDR, timeout=8.0)
        up.sendall(head)
    except OSError:
        try:
            conn.close()
        except OSError:
            pass
        return
    log(f"RELAY-START {addr[0]}:{addr[1]} upstream={UPSTREAM}")
    t1 = threading.Thread(target=relay_loop, args=(conn, up), daemon=True)
    t2 = threading.Thread(target=relay_loop, args=(up, conn), daemon=True)
    t1.start()
    t2.start()
    t1.join()
    t2.join()


def main():
    host, port = LISTEN.rsplit(":", 1)
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((host, int(port)))
    srv.listen(128)
    log(f"DIAL-SPY-UP listen={LISTEN} upstream={UPSTREAM}")
    while True:
        try:
            conn, addr = srv.accept()
        except OSError:
            break
        threading.Thread(target=handle, args=(conn, addr), daemon=True).start()


if __name__ == "__main__":
    main()
