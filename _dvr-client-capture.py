"""Replica exact DVR client (TCP interleaved mode=play) through the helper
and dumps the first NALs / timing / marker-bit usage the DVR would see."""
import socket
import struct
import time

HOST = "127.0.0.1"
PORT = 8554
PATH = "/desktop"


def recv_until_headers(sock):
    buf = b""
    while b"\r\n\r\n" not in buf:
        chunk = sock.recv(65536)
        if not chunk:
            break
        buf += chunk
    return buf


def recv_response(sock, cseq):
    buf = recv_until_headers(sock)
    line = buf.split(b"\r\n", 1)[0].decode("utf-8", "replace")
    print(f"{'':>8}full-buf-start: {buf[:60]!r}")
    return line, buf


s = socket.create_connection((HOST, PORT), timeout=8)
s.settimeout(4.0)


def req(method, target, cseq, extra=""):
    r = f"{method} {target} RTSP/1.0\r\nCSeq: {cseq}\r\n{extra}User-Agent: dvr-preview/1.0\r\n\r\n"
    s.sendall(r.encode())
    line, _buf = recv_response(s, cseq)
    print(f"{method}: {line}")
    return line, _buf


base = f"rtsp://ovifadm:change-onvif-password@{HOST}:{PORT}{PATH}"
req("OPTIONS", base, 1)
req("DESCRIBE", base, 2, "Accept: application/sdp\r\n")
sess = None
set_line, set_buf = req("SETUP", base + "/trackID=0", 3,
                        "Transport: RTP/AVP/TCP;unicast;interleaved=0-1;mode=play\r\n")
# parse Session from SETUP response buffer
import re as _re
m = _re.search(rb"Session:\s*([^\r\n]+)", set_buf)
if m:
    session_id = m.group(1).decode().split(";")[0]
    print("Session:", session_id)
req("PLAY", base + "/", 4, f"Session: {session_id}\r\nRange: npt=0.000000-\r\n")

# Collect interleaved RTP for ~5 seconds
nal_types = []
first_ts = None
last_ts = None
marker_count = 0
pkt_count = 0
deadline = time.time() + 5
raw = b""
while time.time() < deadline:
    try:
        chunk = s.recv(65536)
    except socket.timeout:
        continue
    if not chunk:
        break
    raw += chunk
    # parse $<channel:1><len:2> frames
    while len(raw) >= 4 and raw[0:1] == b"$":
        chan = raw[1]
        (plen,) = struct.unpack(">H", raw[2:4])
        if len(raw) < 4 + plen:
            break
        pkt = raw[4:4 + plen]
        raw = raw[4 + plen:]
        if chan != 0:
            continue
        pkt_count += 1
        if len(pkt) < 12:
            continue
        v = pkt[0] >> 6
        mbit = (pkt[1] >> 7) & 1
        ts = struct.unpack(">I", pkt[4:8])[0]
        if first_ts is None:
            first_ts = ts
        last_ts = ts
        if mbit:
            marker_count += 1
        payload = pkt[12:]
        i = 0
        while i < len(payload):
            b0 = payload[i]
            if b0 == 0 and i + 1 < len(payload) and payload[i + 1] == 0 and i + 2 < len(payload) and (payload[i + 2] & 0x03) in (0, 3):
                # start code
                sc = 1
                if payload[i + 2] & 0x03 == 0:
                    sc = 1
                else:
                    sc = 0
                j = i + 3
                while j < len(payload) and payload[j] == 0:
                    j += 1
                skip = j - i
                if payload[i + 2] & 0x03 == 0 and skip > 3:
                    pass
            break
        # RTP H264 payload: first byte = F|NRI|type (or STAP-A/FU-A)
        if payload:
            t = payload[0] & 0x1F
            if 1 <= t <= 23:
                nal_types.append(t)
            elif t == 28 and len(payload) > 1:  # FU-A
                fu_start = payload[1] & 0x80
                real = payload[1] & 0x1F
                if fu_start:
                    nal_types.append(("FU_START", real))
                else:
                    nal_types.append(("FU_CONT", real))
            elif t == 24:  # STAP-A: aggregate of NALs
                i = 1
                while i + 1 < len(payload):
                    nalu_len = (payload[i] << 8) | payload[i + 1]
                    i += 2
                    if i + nalu_len > len(payload):
                        break
                    sub = payload[i:i + nalu_len]
                    nal_types.append(("STAP", sub[0] & 0x1F))
                    i += nalu_len

counts = {}
for t in nal_types:
    counts[t] = counts.get(t, 0) + 1
print()
print("RTP packets:", pkt_count, "| marker-bits (AU end):", marker_count)
print("timestamp span:", last_ts - first_ts if first_ts and last_ts else "n/a",
      "->", round((last_ts - first_ts) / 90000, 2), "s de video")
print("NAL counts:", counts)
buckets = {}
for n in nal_types:
    key = str(n)
    buckets[key] = buckets.get(key, 0) + 1
print("NAL por tipo:", buckets)
filt = [n if isinstance(n, int) else n[1] for n in nal_types]
ids = [n for n in nal_types if isinstance(n, tuple) and n[0] == "FU_START" and n[1] == 5]
if not ids:
    ids = [n for n in nal_types if isinstance(n, int) and n == 5]
print("IDR frames no periodo:", len(ids))
print("primeiros 15 eventos:", " ".join(str(n) for n in nal_types[:15]))
s.close()