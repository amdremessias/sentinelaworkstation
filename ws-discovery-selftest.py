#!/usr/bin/env python3
"""ws-discovery-selftest.py - sends a WS-Discovery Probe and waits for the
bridge's ProbeMatches answer (multicast to 239.255.255.250:3702)."""
import socket
import sys
import uuid
import xml.etree.ElementTree as ET

WSDD = "http://schemas.xmlsoap.org/ws/2005/04/discovery"
WSA = "http://schemas.xmlsoap.org/ws/2004/08/addressing"
MG = ("239.255.255.250", 3702)

probe = (
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<e:Envelope xmlns:e="http://www.w3.org/2003/05/soap-envelope" '
    'xmlns:w="%s" xmlns:d="%s">'
    '<e:Header>'
    '<w:MessageID>urn:uuid:%s</w:MessageID>'
    '<w:To>urn:schemas-xmlsoap-org:ws:2005:04:discovery</w:To>'
    '<w:Action>http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</w:Action>'
    '</e:Header>'
    '<e:Body><d:Probe><d:Types>dn:NetworkVideoTransmitter</d:Types></d:Probe></e:Body>'
    '</e:Envelope>'
) % (WSA, WSDD, uuid.uuid4())

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
results = []
for target in (("192.168.5.54", 3702), MG):
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind(("", 0))
        sock.settimeout(4.0)
        sock.sendto(probe.encode("utf-8"), target)
        data, addr = sock.recvfrom(65536)
        sock.close()
        root = ET.fromstring(data)
        action = root.find(".//{%s}Action" % WSA)
        types = root.find(".//{%s}Types" % WSDD)
        xaddrs = root.find(".//{%s}XAddrs" % WSDD)
        print("ProbeMatches de %s (%s):" % (addr, target))
        print("  Action :", (action.text if action is not None else "?"))
        print("  Types  :", (types.text if types is not None else "?"))
        print("  XAddrs :", (xaddrs.text if xaddrs is not None else "?"))
        results.append(True)
    except socket.timeout:
        print("timeout (sem resposta) para %s" % (target,))
        results.append(False)
    except Exception as e:
        print("ERRO para %s: %r" % (target, e))
        results.append(False)
    finally:
        try:
            sock.close()
        except Exception:
            pass

if any(results):
    print("RESULTADO: WS-Discovery respondendo")
    sys.exit(0)
print("RESULTADO: WS-Discovery sem resposta")
sys.exit(1)