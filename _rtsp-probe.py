import socket
import time

HOST = "127.0.0.1"
PORT = 8554
PATH = "/desktop"
USER = "ovifadm"
PASS = "change-onvif-password"


def raw_req(method, cseq, extra=""):
    req = (f"{method} rtsp://{USER}:{PASS}@{HOST}:{PORT}{PATH} RTSP/1.0\r\n"
           f"CSeq: {cseq}\r\n{extra}User-Agent: dvr-probe/1.0\r\n\r\n")
    s = socket.create_connection((HOST, PORT), timeout=6)
    s.settimeout(1.0)
    s.sendall(req.encode())
    data = b""
    deadline = time.time() + 4
    while time.time() < deadline:
        try:
            chunk = s.recv(65536)
            if not chunk:
                break
            data += chunk
        except socket.timeout:
            pass
    s.close()
    return data


print("### OPTIONS")
print(raw_req("OPTIONS", 1).decode("utf-8", "replace"))
print()
print("### DESCRIBE (SDP completo entregue ao DVR)")
print(raw_req("DESCRIBE", 2, "Accept: application/sdp\r\n").decode("utf-8", "replace"))