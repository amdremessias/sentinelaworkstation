"""ONVIF device bridge for HomelabScreenCamera.

Exposes the MediaMTX RTSP stream (/desktop) as a virtual ONVIF camera so
that an ONVIF DVR/NVR can add it by IP (or via WS-Discovery) and pull the
stream with the credentials of the ONVIF account.

HTTP endpoints:
  POST /onvif/device_service   -- ONVIF device service (SOAP 1.2)
  POST /onvif/media_service    -- ONVIF media 1.0 service (SOAP 1.2)
  POST /onvif/media2_service   -- ONVIF media 2.0 service (SOAP 1.2)
  GET  /snapshot               -- JPEG snapshot taken from the RTSP stream
  GET  /health                 -- liveness probe

UDP listener:
  0.0.0.0:3702                 -- WS-Discovery (Probe / Resolve), multicast +
                                  unicast, so DVRs can auto-discover the camera.

The ONVIF user (ONVIF_USER / ONVIF_PASSWORD) must also exist in
mediamtx.yml with read permission on the path: several DVRs authenticate
the RTSP session using the ONVIF credentials instead of the ones embedded
in the URL returned by GetStreamUri.
"""

import asyncio
import base64
import hashlib
import os
import secrets
import shutil
import socket
import threading
import uuid
from datetime import datetime, timezone

from aiohttp import web
from lxml import etree

# ----------------------------------------------------------------------------
# configuration
# ----------------------------------------------------------------------------
DEVICE_IP = os.getenv("DEVICE_IP", "192.168.5.54")
HTTP_PORT = int(os.getenv("HTTP_PORT", "8000"))
RTSP_URL = os.getenv(
    "RTSP_URL",
    "rtsp://ovifadm:change-onvif-password@192.168.5.54:8554/desktop",
)
ONVIF_USER = os.getenv("ONVIF_USER", "ovifadm")
ONVIF_PASSWORD = os.getenv("ONVIF_PASSWORD", "change-onvif-password")
SNAPSHOT_TIMEOUT = float(os.getenv("SNAPSHOT_TIMEOUT", "10"))

SOAP = "http://www.w3.org/2003/05/soap-envelope"
TD = "http://www.onvif.org/ver10/device/wsdl"
MEDIA = "http://www.onvif.org/ver10/media/wsdl"
MEDIA2 = "http://www.onvif.org/ver20/media/wsdl"
TT = "http://www.onvif.org/ver10/schema"
TER = "http://www.onvif.org/ver10/error"
WSA = "http://schemas.xmlsoap.org/ws/2004/08/addressing"
WSDD = "http://schemas.xmlsoap.org/ws/2005/04/discovery"
DN = "http://www.onvif.org/ver10/network/wsdl"
# Response namespace map: tr2 lets Media 2.0 (ver20) requests get a
# namespace-correct response instead of a guessed prefix. "ter" is the
# ONVIF error namespace used inside SOAP fault Subcode/Detail.
NSMAP = {"s": SOAP, "tds": TD, "trt": MEDIA, "tr2": MEDIA2, "tt": TT, "ter": TER}

DEVICE_UUID = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"{socket.gethostname()}-{DEVICE_IP}"))
SCOPES = " ".join(
    [
        f"onvif://www.onvif.org/name/{socket.gethostname()}",
        "onvif://www.onvif.org/hardware/VirtualScreenCamera",
        "onvif://www.onvif.org/type/video_encoder",
        "onvif://www.onvif.org/location/homelab",
    ]
)
FFMPEG = shutil.which("ffmpeg") or os.getenv("FFMPEG")


def hw_address():
    try:
        b = uuid.getnode().to_bytes(6, "big")
        return ":".join(f"{x:02x}" for x in b)
    except Exception:
        return "00:00:00:00:00:00"


# ----------------------------------------------------------------------------
# SOAP plumbing
# ----------------------------------------------------------------------------
def response(element):
    env = etree.Element(etree.QName(SOAP, "Envelope"), nsmap=NSMAP)
    etree.SubElement(env, etree.QName(SOAP, "Body")).append(element)
    return web.Response(
        body=etree.tostring(env, xml_declaration=True, encoding="UTF-8"),
        content_type="application/soap+xml",
    )


def fault(message, subcode="ter:InvalidArgVal"):
    # SOAP 1.2 fault in the shape strict ONVIF clients (DVRs, ODM) expect:
    # Code/Value (s:Sender), Code/Subcode/Value with an ONVIF ter: code,
    # Reason/Text, and a Detail element. A bare Fault without Subcode/Detail
    # is what older bridges served and several DVRs flag it as "invalid SOAP
    # fault" instead of rendering the message.
    f = etree.Element(etree.QName(SOAP, "Fault"), nsmap=NSMAP)
    code = etree.SubElement(f, etree.QName(SOAP, "Code"))
    etree.SubElement(code, etree.QName(SOAP, "Value")).text = "s:Sender"
    sub = etree.SubElement(code, etree.QName(SOAP, "Subcode"))
    etree.SubElement(sub, etree.QName(SOAP, "Value")).text = subcode
    reason = etree.SubElement(f, etree.QName(SOAP, "Reason"))
    etree.SubElement(reason, etree.QName(SOAP, "Text")).text = message
    detail = etree.SubElement(f, etree.QName(SOAP, "Detail"))
    etree.SubElement(detail, etree.QName(TER, "Text")).text = message
    return response(f)


def created_ok(value, skew=900):
    # A generous 15-minute skew: some DVR clocks drift quite a bit.
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return abs((datetime.now(timezone.utc) - dt).total_seconds()) <= skew
    except ValueError:
        return False


def authenticated(root):
    user = root.find(".//{*}Username")
    pwd = root.find(".//{*}Password")
    if user is None or pwd is None or user.text != ONVIF_USER:
        return False
    # Some clients (rare) send the password in plaintext.
    if "PasswordText" in (pwd.get("Type") or ""):
        return secrets.compare_digest(pwd.text or "", ONVIF_PASSWORD)
    nonce = root.find(".//{*}Nonce")
    created = root.find(".//{*}Created")
    if any(x is None for x in (nonce, created)) or not created_ok(created.text):
        return False
    try:
        raw = base64.b64decode(nonce.text) + created.text.encode() + ONVIF_PASSWORD.encode()
        expected = base64.b64encode(hashlib.sha1(raw).digest()).decode()
        return secrets.compare_digest(expected, pwd.text)
    except Exception:
        return False


# ----------------------------------------------------------------------------
# device service operations
# ----------------------------------------------------------------------------
def date_time(ns):
    now = datetime.now(timezone.utc)
    r = etree.Element(etree.QName(ns, "GetSystemDateAndTimeResponse"), nsmap=NSMAP)
    s = etree.SubElement(r, etree.QName(TT, "SystemDateAndTime"))
    etree.SubElement(s, etree.QName(TT, "DateTimeType")).text = "NTP"
    etree.SubElement(s, etree.QName(TT, "DaylightSavings")).text = "false"
    z = etree.SubElement(s, etree.QName(TT, "TimeZone"))
    etree.SubElement(z, etree.QName(TT, "TZ")).text = "BRT3"
    u = etree.SubElement(s, etree.QName(TT, "UTCDateTime"))
    d = etree.SubElement(u, etree.QName(TT, "Date"))
    t = etree.SubElement(u, etree.QName(TT, "Time"))
    for tag, val in (("Year", now.year), ("Month", now.month), ("Day", now.day)):
        etree.SubElement(d, etree.QName(TT, tag)).text = str(val)
    for tag, val in (("Hour", now.hour), ("Minute", now.minute), ("Second", now.second)):
        etree.SubElement(t, etree.QName(TT, tag)).text = str(val)
    return response(r)


def device_info(ns):
    r = etree.Element(etree.QName(ns, "GetDeviceInformationResponse"), nsmap=NSMAP)
    for k, v in {
        "Manufacturer": "Homelab",
        "Model": "VirtualScreenCamera",
        "FirmwareVersion": "0.1-beta",
        "SerialNumber": "VSC-001",
        "HardwareId": "VSC",
    }.items():
        etree.SubElement(r, etree.QName(TD, k)).text = v
    return response(r)


def capabilities(ns):
    r = etree.Element(etree.QName(ns, "GetCapabilitiesResponse"), nsmap=NSMAP)
    c = etree.SubElement(r, etree.QName(TD, "Capabilities"))
    d = etree.SubElement(c, etree.QName(TT, "Device"))
    d.set("XAddr", f"http://{DEVICE_IP}:{HTTP_PORT}/onvif/device_service")
    m = etree.SubElement(c, etree.QName(TT, "Media"))
    m.set("XAddr", f"http://{DEVICE_IP}:{HTTP_PORT}/onvif/media_service")
    # StreamingCapabilities: Intelbras/Dahua DVRs refuse to add the camera
    # unless the device advertises TCP RTSP streaming. The DVR channel is
    # configured with Transport=TCP, so these flags are mandatory.
    sc = etree.SubElement(m, etree.QName(TT, "StreamingCapabilities"))
    sc.set("RTPMulticast", "true")
    sc.set("RTP_TCP", "true")
    sc.set("RTP_RTSP_TCP", "true")
    sc.set("NonAggregateRCSPull", "false")
    # ProfileCapabilities: helps DVRs that decide profile support count.
    pc = etree.SubElement(c, etree.QName(TT, "ProfileCapabilities"))
    etree.SubElement(pc, etree.QName(TT, "MaximumNumberOfProfiles")).text = "1"
    ev = etree.SubElement(c, etree.QName(TT, "Events"))
    ev.set("XAddr", f"http://{DEVICE_IP}:{HTTP_PORT}/onvif/events_service")
    ev.set("WSSubscriptionPullSupport", "true")
    ev.set("WSPullPointSupport", "false")
    ev.set("WSPausableSubscriptionManagerInterfaceSupport", "false")
    return response(r)


def services(ns):
    r = etree.Element(etree.QName(ns, "GetServicesResponse"), nsmap=NSMAP)
    for service_ns, xaddr in (
        (TD, f"http://{DEVICE_IP}:{HTTP_PORT}/onvif/device_service"),
        (MEDIA, f"http://{DEVICE_IP}:{HTTP_PORT}/onvif/media_service"),
        (MEDIA2, f"http://{DEVICE_IP}:{HTTP_PORT}/onvif/media2_service"),
    ):
        s = etree.SubElement(r, etree.QName(TD, "Service"))
        etree.SubElement(s, etree.QName(TD, "Namespace")).text = service_ns
        etree.SubElement(s, etree.QName(TD, "XAddr")).text = xaddr
        v = etree.SubElement(s, etree.QName(TD, "Version"))
        etree.SubElement(v, etree.QName(TT, "Major")).text = "2"
        etree.SubElement(v, etree.QName(TT, "Minor")).text = "0"
    return response(r)


def network_interfaces(ns):
    r = etree.Element(etree.QName(ns, "GetNetworkInterfacesResponse"), nsmap=NSMAP)
    n = etree.SubElement(r, etree.QName(TT, "NetworkInterfaces"))
    n.set("token", "eth0")
    etree.SubElement(n, etree.QName(TT, "Enabled")).text = "true"
    info = etree.SubElement(n, etree.QName(TT, "Info"))
    etree.SubElement(info, etree.QName(TT, "Name")).text = "ethernet0"
    etree.SubElement(info, etree.QName(TT, "HwAddress")).text = hw_address()
    etree.SubElement(info, etree.QName(TT, "MTU")).text = "1500"
    ipv4 = etree.SubElement(n, etree.QName(TT, "IPv4"))
    etree.SubElement(ipv4, etree.QName(TT, "Enabled")).text = "true"
    etree.SubElement(ipv4, etree.QName(TT, "DHCP")).text = "false"
    manual = etree.SubElement(ipv4, etree.QName(TT, "Manual"))
    etree.SubElement(manual, etree.QName(TT, "Address")).text = DEVICE_IP
    etree.SubElement(manual, etree.QName(TT, "PrefixLength")).text = "24"
    return response(r)


def network_protocols(ns):
    r = etree.Element(etree.QName(ns, "GetNetworkProtocolsResponse"), nsmap=NSMAP)
    # HTTPS is reported disabled (nothing listens on 443 here) so DVRs do not
    # try to probe TLS on the camera. ONVIF is added because some DVRs gate
    # the "works as a camera" decision on seeing the ONVIF protocol enabled.
    for name, port, enabled in (
        ("HTTP", HTTP_PORT, True),
        ("HTTPS", 443, False),
        ("RTSP", 8554, True),
        ("ONVIF", HTTP_PORT, True),
    ):
        p = etree.SubElement(r, etree.QName(TT, "NetworkProtocols"))
        p.set("token", f"proto_{name.lower()}")
        etree.SubElement(p, etree.QName(TT, "Name")).text = name
        etree.SubElement(p, etree.QName(TT, "Enabled")).text = "true" if enabled else "false"
        etree.SubElement(p, etree.QName(TT, "Port")).text = str(port)
    return response(r)


def network_default_gateway(ns):
    r = etree.Element(etree.QName(ns, "GetNetworkDefaultGatewayResponse"), nsmap=NSMAP)
    g = etree.SubElement(r, etree.QName(TT, "NetworkGateway"))
    etree.SubElement(g, etree.QName(TT, "IPv4Address")).text = "192.168.5.1"
    return response(r)


def dns(ns):
    r = etree.Element(etree.QName(ns, "GetDNSResponse"), nsmap=NSMAP)
    d = etree.SubElement(r, etree.QName(TT, "DNS"))
    etree.SubElement(d, etree.QName(TT, "FromDHCP")).text = "false"
    m = etree.SubElement(d, etree.QName(TT, "DNSManual"))
    etree.SubElement(m, etree.QName(TT, "Type")).text = "IPv4"
    etree.SubElement(m, etree.QName(TT, "IPv4Address")).text = "8.8.8.8"
    return response(r)


def ntp(ns):
    r = etree.Element(etree.QName(ns, "GetNTPResponse"), nsmap=NSMAP)
    n = etree.SubElement(r, etree.QName(TT, "NTP"))
    etree.SubElement(n, etree.QName(TT, "FromDHCP")).text = "true"
    m = etree.SubElement(n, etree.QName(TT, "NTPManual"))
    etree.SubElement(m, etree.QName(TT, "Type")).text = "DNS"
    etree.SubElement(m, etree.QName(TT, "DNSname")).text = "pool.ntp.org"
    return response(r)


def set_ok(action, ns):
    # Empty-but-schema-valid response for the Set* operations. DVRs save the
    # configuration (network, users, time...) after a successful response;
    # the virtual camera simply accepts and keeps its own state.
    r = etree.Element(etree.QName(ns, f"{action}Response"), nsmap=NSMAP)
    return response(r)


def hostname(ns):
    r = etree.Element(etree.QName(ns, "GetHostnameResponse"), nsmap=NSMAP)
    h = etree.SubElement(r, etree.QName(TT, "Hostname"))
    h.set("token", "hostname")
    etree.SubElement(h, etree.QName(TT, "Name")).text = socket.gethostname()
    return response(r)


def users(ns):
    r = etree.Element(etree.QName(ns, "GetUsersResponse"), nsmap=NSMAP)
    u = etree.SubElement(r, etree.QName(TT, "User"))
    u.set("token", ONVIF_USER)
    etree.SubElement(u, etree.QName(TT, "Username")).text = ONVIF_USER
    etree.SubElement(u, etree.QName(TT, "UserLevel")).text = "Administrator"
    return response(r)


def scopes(ns):
    r = etree.Element(etree.QName(ns, "GetScopesResponse"), nsmap=NSMAP)
    for item in SCOPES.split(" "):
        sc = etree.SubElement(r, etree.QName(TT, "Scopes"))
        etree.SubElement(sc, etree.QName(TT, "ScopeItem")).text = item
        etree.SubElement(sc, etree.QName(TT, "Configurable")).text = "false"
    return response(r)


# ----------------------------------------------------------------------------
# media service operations
# ----------------------------------------------------------------------------
def _encoder2_common(el):
    """Fill a tr2:VideoEncoder / tr2:Configurations element (types
    tt:VideoEncoder2Configuration) with schema-correct content. Encoding,
    Resolution, RateControl, Multicast and Quality are the only children of
    this type; GovLength and Profile are ATTRIBUTES (not children), and no
    Name/UseCount/SessionTimeout/H264 child elements exist here."""
    el.set("Profile", "baseline")
    el.set("GovLength", "50")
    etree.SubElement(el, etree.QName(TT, "Encoding")).text = "H264"
    res = etree.SubElement(el, etree.QName(TT, "Resolution"))
    etree.SubElement(res, etree.QName(TT, "Width")).text = "1920"
    etree.SubElement(res, etree.QName(TT, "Height")).text = "1080"
    rc = etree.SubElement(el, etree.QName(TT, "RateControl"))
    etree.SubElement(rc, etree.QName(TT, "FrameRateLimit")).text = "25"
    etree.SubElement(rc, etree.QName(TT, "BitrateLimit")).text = "3000"
    mc = etree.SubElement(el, etree.QName(TT, "Multicast"))
    a = etree.SubElement(mc, etree.QName(TT, "Address"))
    etree.SubElement(a, etree.QName(TT, "Type")).text = "DottedDecimal"
    etree.SubElement(a, etree.QName(TT, "IPv4Address")).text = "0.0.0.0"
    etree.SubElement(mc, etree.QName(TT, "Port")).text = "0"
    etree.SubElement(mc, etree.QName(TT, "TTL")).text = "0"
    etree.SubElement(mc, etree.QName(TT, "AutoStart")).text = "false"
    etree.SubElement(el, etree.QName(TT, "Quality")).text = "50"


def profiles(ns):
    r = etree.Element(etree.QName(ns, "GetProfilesResponse"), nsmap=NSMAP)
    if ns == MEDIA2:
        # Media 2.0 (ver20): tr2:Profiles > tt:Name + tr2:Configurations >
        # tr2:VideoSource / tr2:VideoEncoder (tt:VideoEncoder2Configuration).
        # The Intelbras DVR queries /onvif/media2_service, so this shape must
        # match the ver20 schema exactly or the DVR sees no profile and never
        # proceeds to GetStreamUri.
        p = etree.SubElement(r, etree.QName(MEDIA2, "Profiles"))
        p.set("token", "profile_1")
        p.set("fixed", "true")
        etree.SubElement(p, etree.QName(TT, "Name")).text = "Desktop H264"
        cfg = etree.SubElement(p, etree.QName(MEDIA2, "Configurations"))
        vs = etree.SubElement(cfg, etree.QName(MEDIA2, "VideoSource"))
        vs.set("token", "video_source_1")
        etree.SubElement(vs, etree.QName(TT, "Name")).text = "Desktop Capture"
        etree.SubElement(vs, etree.QName(TT, "UseCount")).text = "1"
        etree.SubElement(vs, etree.QName(TT, "SourceToken")).text = "video_source_1"
        bounds = etree.SubElement(vs, etree.QName(TT, "Bounds"))
        bounds.set("x", "0"); bounds.set("y", "0")
        bounds.set("width", "1920"); bounds.set("height", "1080")
        ve = etree.SubElement(cfg, etree.QName(MEDIA2, "VideoEncoder"))
        ve.set("token", "encoder_1")
        _encoder2_common(ve)
        return response(r)

    # Media 1.0 (ver10) path: tt:Profiles with the classic profile content.
    p = etree.SubElement(r, etree.QName(TT, "Profiles"))
    p.set("token", "profile_1")
    p.set("fixed", "true")
    etree.SubElement(p, etree.QName(TT, "Name")).text = "Desktop H264"

    src = etree.SubElement(p, etree.QName(TT, "VideoSourceConfiguration"))
    src.set("token", "video_source_1")
    etree.SubElement(src, etree.QName(TT, "Name")).text = "Desktop Capture"
    etree.SubElement(src, etree.QName(TT, "SourceToken")).text = "video_source_1"
    bounds = etree.SubElement(src, etree.QName(TT, "Bounds"))
    bounds.set("x", "0"); bounds.set("y", "0")
    bounds.set("width", "1920"); bounds.set("height", "1080")

    e = etree.SubElement(p, etree.QName(TT, "VideoEncoderConfiguration"))
    e.set("token", "encoder_1")
    etree.SubElement(e, etree.QName(TT, "Name")).text = "H264"
    etree.SubElement(e, etree.QName(TT, "UseCount")).text = "1"
    etree.SubElement(e, etree.QName(TT, "Encoding")).text = "H264"
    res = etree.SubElement(e, etree.QName(TT, "Resolution"))
    etree.SubElement(res, etree.QName(TT, "Width")).text = "1920"
    etree.SubElement(res, etree.QName(TT, "Height")).text = "1080"
    etree.SubElement(e, etree.QName(TT, "Quality")).text = "50"
    etree.SubElement(e, etree.QName(TT, "FramerateLimit")).text = "25"
    etree.SubElement(e, etree.QName(TT, "EncodingInterval")).text = "1"
    h = etree.SubElement(e, etree.QName(TT, "H264"))
    etree.SubElement(h, etree.QName(TT, "GovLength")).text = "50"
    etree.SubElement(h, etree.QName(TT, "H264Profile")).text = "baseline"
    mc = etree.SubElement(e, etree.QName(TT, "Multicast"))
    a = etree.SubElement(mc, etree.QName(TT, "Address"))
    etree.SubElement(a, etree.QName(TT, "Type")).text = "DottedDecimal"
    etree.SubElement(a, etree.QName(TT, "IPv4Address")).text = "0.0.0.0"
    etree.SubElement(mc, etree.QName(TT, "Port")).text = "0"
    etree.SubElement(mc, etree.QName(TT, "TTL")).text = "0"
    etree.SubElement(mc, etree.QName(TT, "AutoStart")).text = "false"
    etree.SubElement(e, etree.QName(TT, "SessionTimeout")).text = "PT6S"
    return response(r)


def encoder_configs(ns):
    # Configurations wrapper follows the request namespace: tr2 for Media 2.0,
    # tt otherwise (same pattern as profiles/encoder_options).
    wrapper = etree.QName(MEDIA2, "Configurations") if ns == MEDIA2 else etree.QName(TT, "Configurations")
    r = etree.Element(etree.QName(ns, "GetVideoEncoderConfigurationsResponse"), nsmap=NSMAP)
    c = etree.SubElement(r, wrapper)
    c.set("token", "encoder_1")
    if ns == MEDIA2:
        # tt:VideoEncoder2Configuration: only Encoding/Resolution/RateControl/
        # Multicast/Quality children; GovLength+Profile as attributes. The
        # Intelbras DVR re-reads this in a tight loop while the channel is
        # selected; an off-schema shape (e.g. FramerateLimit as a direct
        # child) makes it treat the encoder config as invalid.
        _encoder2_common(c)
    else:
        # Media 1.0 classic tt:VideoEncoderConfiguration shape.
        etree.SubElement(c, etree.QName(TT, "Name")).text = "H264"
        etree.SubElement(c, etree.QName(TT, "UseCount")).text = "1"
        etree.SubElement(c, etree.QName(TT, "Encoding")).text = "H264"
        res = etree.SubElement(c, etree.QName(TT, "Resolution"))
        etree.SubElement(res, etree.QName(TT, "Width")).text = "1920"
        etree.SubElement(res, etree.QName(TT, "Height")).text = "1080"
        etree.SubElement(c, etree.QName(TT, "Quality")).text = "50"
        etree.SubElement(c, etree.QName(TT, "FramerateLimit")).text = "25"
        etree.SubElement(c, etree.QName(TT, "EncodingInterval")).text = "1"
        h = etree.SubElement(c, etree.QName(TT, "H264"))
        etree.SubElement(h, etree.QName(TT, "GovLength")).text = "50"
        etree.SubElement(h, etree.QName(TT, "H264Profile")).text = "baseline"
        mc = etree.SubElement(c, etree.QName(TT, "Multicast"))
        a = etree.SubElement(mc, etree.QName(TT, "Address"))
        etree.SubElement(a, etree.QName(TT, "Type")).text = "DottedDecimal"
        etree.SubElement(a, etree.QName(TT, "IPv4Address")).text = "0.0.0.0"
        etree.SubElement(mc, etree.QName(TT, "Port")).text = "0"
        etree.SubElement(mc, etree.QName(TT, "TTL")).text = "0"
        etree.SubElement(mc, etree.QName(TT, "AutoStart")).text = "false"
        etree.SubElement(c, etree.QName(TT, "SessionTimeout")).text = "PT6S"
    return response(r)


def video_sources(ns):
    r = etree.Element(etree.QName(ns, "GetVideoSourcesResponse"), nsmap=NSMAP)
    v = etree.SubElement(r, etree.QName(TT, "VideoSources"))
    v.set("token", "video_source_1")
    etree.SubElement(v, etree.QName(TT, "Framerate")).text = "25"
    res = etree.SubElement(v, etree.QName(TT, "Resolution"))
    etree.SubElement(res, etree.QName(TT, "Width")).text = "1920"
    etree.SubElement(res, etree.QName(TT, "Height")).text = "1080"
    etree.SubElement(v, etree.QName(TT, "Imaging")).text = ""
    return response(r)


def encoder_options(ns):
    # GetVideoEncoderConfigurationOptions (Media 2.0: tr2:Options of type
    # tt:VideoEncoder2ConfigurationOptions). The Intelbras DVR calls this when
    # opening the channel's encoder/bitrate settings; an ActionNotSupported
    # fault there makes the dialog fail, so hand back real options.
    wrapper = etree.QName(MEDIA2, "Options") if ns == MEDIA2 else etree.QName(TT, "Options")
    r = etree.Element(etree.QName(ns, "GetVideoEncoderConfigurationOptionsResponse"), nsmap=NSMAP)
    o = etree.SubElement(r, wrapper)
    # tt:VideoEncoder2ConfigurationOptions: GovLength/FrameRates/Profiles are
    # attributes on the Options element (IntList / FloatList / StringAttrList).
    o.set("GovLengthRange", "15 50")
    o.set("FrameRatesSupported", "15 25")
    o.set("ProfilesSupported", "baseline")
    etree.SubElement(o, etree.QName(TT, "Encoding")).text = "H264"
    q = etree.SubElement(o, etree.QName(TT, "QualityRange"))
    etree.SubElement(q, etree.QName(TT, "Min")).text = "1"
    etree.SubElement(q, etree.QName(TT, "Max")).text = "100"
    res = etree.SubElement(o, etree.QName(TT, "ResolutionsAvailable"))
    etree.SubElement(res, etree.QName(TT, "Width")).text = "1920"
    etree.SubElement(res, etree.QName(TT, "Height")).text = "1080"
    b = etree.SubElement(o, etree.QName(TT, "BitrateRange"))
    etree.SubElement(b, etree.QName(TT, "Min")).text = "64"
    etree.SubElement(b, etree.QName(TT, "Max")).text = "8192"
    return response(r)


def osds(ns):
    # GetOSDs: the virtual camera has no OSD overlays configured. Empty list.
    r = etree.Element(etree.QName(ns, "GetOSDsResponse"), nsmap=NSMAP)
    return response(r)


def osd_options(ns):
    # GetOSDOptions > tr2:OSDOptions (tt:OSDConfigurationOptions). Zero OSDs
    # supported keeps the DVR's OSD dialog harmless.
    wrapper = etree.QName(MEDIA2, "OSDOptions") if ns == MEDIA2 else etree.QName(TT, "OSDOptions")
    r = etree.Element(etree.QName(ns, "GetOSDOptionsResponse"), nsmap=NSMAP)
    o = etree.SubElement(r, wrapper)
    m = etree.SubElement(o, etree.QName(TT, "MaximumNumberOfOSDs"))
    m.set("Total", "0")
    m.set("Image", "0")
    m.set("PlainText", "0")
    etree.SubElement(o, etree.QName(TT, "Type")).text = "Text"
    etree.SubElement(o, etree.QName(TT, "PositionOption")).text = "CUSTOM"
    return response(r)


def mask_options(ns):
    # GetMaskOptions > tr2:Options (tr2:MaskOptions). No privacy masks.
    wrapper = etree.QName(MEDIA2, "Options") if ns == MEDIA2 else etree.QName(TT, "Options")
    r = etree.Element(etree.QName(ns, "GetMaskOptionsResponse"), nsmap=NSMAP)
    o = etree.SubElement(r, wrapper)
    etree.SubElement(o, etree.QName(MEDIA2, "MaxMasks")).text = "0"
    etree.SubElement(o, etree.QName(MEDIA2, "MaxPoints")).text = "4"
    etree.SubElement(o, etree.QName(MEDIA2, "Types")).text = "Custom"
    return response(r)


def analytics_configs(ns):
    # GetAnalyticsConfigurations: no analytics. Empty list.
    r = etree.Element(etree.QName(ns, "GetAnalyticsConfigurationsResponse"), nsmap=NSMAP)
    return response(r)


def stream_uri(ns):
    # Always hand the DVR the /desktop path; the ONVIF account credentials
    # are embedded so DVRs that honor URL credentials work out of the box.
    # Media 1.0 (ver10) wraps the URI in tt:MediaUri; Media 2.0 (ver20) puts
    # a bare tr2:Uri child on the response. The Intelbras DVR uses
    # /onvif/media2_service, so keep the response shape namespace-aligned.
    r = etree.Element(etree.QName(ns, "GetStreamUriResponse"), nsmap=NSMAP)
    if ns == MEDIA2:
        etree.SubElement(r, etree.QName(MEDIA2, "Uri")).text = RTSP_URL
    else:
        u = etree.SubElement(r, etree.QName(TT, "MediaUri"))
        etree.SubElement(u, etree.QName(TT, "Uri")).text = RTSP_URL
        etree.SubElement(u, etree.QName(TT, "InvalidAfterConnect")).text = "false"
        etree.SubElement(u, etree.QName(TT, "InvalidAfterReboot")).text = "false"
        etree.SubElement(u, etree.QName(TT, "Timeout")).text = "PT0S"
    return response(r)


def snapshot_uri(ns):
    r = etree.Element(etree.QName(ns, "GetSnapshotUriResponse"), nsmap=NSMAP)
    if ns == MEDIA2:
        etree.SubElement(r, etree.QName(MEDIA2, "Uri")).text = (
            f"http://{DEVICE_IP}:{HTTP_PORT}/snapshot"
        )
    else:
        u = etree.SubElement(r, etree.QName(TT, "MediaUri"))
        etree.SubElement(u, etree.QName(TT, "Uri")).text = (
            f"http://{DEVICE_IP}:{HTTP_PORT}/snapshot"
        )
        etree.SubElement(u, etree.QName(TT, "InvalidAfterConnect")).text = "false"
        etree.SubElement(u, etree.QName(TT, "InvalidAfterReboot")).text = "false"
        etree.SubElement(u, etree.QName(TT, "Timeout")).text = "PT10S"
    return response(r)


# ----------------------------------------------------------------------------
# WS-Discovery (UDP 3702): lets DVRs find the camera automatically
# ----------------------------------------------------------------------------
class DiscoveryProtocol(asyncio.DatagramProtocol):
    def connection_made(self, transport):
        self.transport = transport

    def datagram_received(self, data, addr):
        try:
            root = etree.fromstring(data)
        except Exception:
            return
        action_el = root.find(".//{*}Action")
        if action_el is None:
            return
        action = action_el.text or ""
        kind = None
        if action.endswith("/Probe"):
            kind = "Probe"
        elif action.endswith("/Resolve"):
            kind = "Resolve"
        if kind is None:
            return
        # Answer in the same addressing namespace the requester used.
        wsa_ns = etree.QName(action_el).namespace or WSA
        msg_id = root.find(".//{*}MessageID")
        relates = (msg_id.text or f"urn:uuid:{uuid.uuid4()}") if msg_id is not None else f"urn:uuid:{uuid.uuid4()}"
        reply = root.find(".//{*}ReplyTo/{*}Address")
        to = reply.text if reply is not None and reply.text else "http://schemas.xmlsoap.org/ws/2004/08/addressing/role/anonymous"
        try:
            payload = discovery_answer(kind, relates, to, wsa_ns)
            self.transport.sendto(payload, addr)
        except Exception:
            pass


def discovery_answer(kind, relates_to, to, wsa_ns):
    env = etree.Element(
        etree.QName(SOAP, "Envelope"),
        nsmap={"e": SOAP, "w": wsa_ns, "d": WSDD, "dn": DN, "tds": TD},
    )
    h = etree.SubElement(env, etree.QName(SOAP, "Header"))
    etree.SubElement(h, etree.QName(wsa_ns, "MessageID")).text = f"urn:uuid:{uuid.uuid4()}"
    etree.SubElement(h, etree.QName(wsa_ns, "RelatesTo")).text = relates_to
    etree.SubElement(h, etree.QName(wsa_ns, "To")).text = to
    etree.SubElement(h, etree.QName(wsa_ns, "Action")).text = (
        f"http://schemas.xmlsoap.org/ws/2005/04/discovery/{kind}Matches"
    )
    b = etree.SubElement(env, etree.QName(SOAP, "Body"))
    matches = etree.SubElement(b, etree.QName(WSDD, f"{kind}Matches"))
    match = etree.SubElement(matches, etree.QName(WSDD, f"{kind}Match"))
    epr = etree.SubElement(match, etree.QName(wsa_ns, "EndpointReference"))
    etree.SubElement(epr, etree.QName(wsa_ns, "Address")).text = f"urn:uuid:{DEVICE_UUID}"
    etree.SubElement(match, etree.QName(WSDD, "Types")).text = "dn:NetworkVideoTransmitter tds:Device"
    etree.SubElement(match, etree.QName(WSDD, "Scopes")).text = SCOPES
    etree.SubElement(match, etree.QName(WSDD, "XAddrs")).text = (
        f"http://{DEVICE_IP}:{HTTP_PORT}/onvif/device_service"
    )
    etree.SubElement(match, etree.QName(WSDD, "MetadataVersion")).text = "1"
    return etree.tostring(env, xml_declaration=True, encoding="UTF-8")


def run_ws_discovery():
    # aiohttp's default event loop on Windows is ProactorEventLoop, which does
    # not support UDP datagram endpoints, so WS-Discovery runs on its own
    # SelectorEventLoop in a dedicated thread.
    try:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)

        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        if hasattr(socket, "SO_BROADCAST"):
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        # Bind to the device IP instead of 0.0.0.0: a Windows service
        # (Function Discovery) holds the wildcard on 3702 and would swallow
        # unicast probes. This specific-IP socket receives unicast AND
        # multicast probes with exactly one copy each.
        sock.bind((DEVICE_IP, 3702))
        mreq = socket.inet_aton("239.255.255.250") + socket.inet_aton(DEVICE_IP)
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
        sock.setblocking(False)

        loop.run_until_complete(loop.create_datagram_endpoint(DiscoveryProtocol, sock=sock))
        print(f"[ws-discovery] listening on 239.255.255.250:3702 (interface {DEVICE_IP})", flush=True)
        loop.run_forever()
    except Exception as exc:
        print(f"[ws-discovery] disabled: {exc}", flush=True)


# ----------------------------------------------------------------------------
# HTTP helpers
# ----------------------------------------------------------------------------
async def snapshot(request):
    if not FFMPEG:
        return web.Response(status=503, text="ffmpeg not found")
    proc = await asyncio.create_subprocess_exec(
        FFMPEG,
        "-hide_banner",
        "-loglevel", "error",
        "-rtsp_transport", "tcp",
        "-i", RTSP_URL,
        "-frames:v", "1",
        "-q:v", "3",
        "-f", "mjpeg",
        "pipe:1",
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    try:
        out, err = await asyncio.wait_for(proc.communicate(), timeout=SNAPSHOT_TIMEOUT)
    except asyncio.TimeoutError:
        try:
            proc.kill()
        except Exception:
            pass
        return web.Response(status=504, text="snapshot timeout")
    if proc.returncode != 0:
        return web.Response(status=503, text=err.decode(errors="replace") or "snapshot failed")
    return web.Response(body=out, content_type="image/jpeg")


# ----------------------------------------------------------------------------
# ONVIF SOAP dispatcher
# ----------------------------------------------------------------------------
OPS = {
    "GetSystemDateAndTime": date_time,
    "GetDeviceInformation": device_info,
    "GetCapabilities": capabilities,
    "GetServices": services,
    "GetNetworkInterfaces": network_interfaces,
    "GetNetworkProtocols": network_protocols,
    "GetNetworkDefaultGateway": network_default_gateway,
    "GetDNS": dns,
    "GetNTP": ntp,
    "GetHostname": hostname,
    "GetUsers": users,
    "GetScopes": scopes,
    "GetProfiles": profiles,
    "GetVideoSources": video_sources,
    "GetVideoEncoderConfigurations": encoder_configs,
    "GetVideoEncoderConfigurationOptions": encoder_options,
    "GetOSDs": osds,
    "GetOSDOptions": osd_options,
    "GetMaskOptions": mask_options,
    "GetAnalyticsConfigurations": analytics_configs,
    "GetStreamUri": stream_uri,
    "GetSnapshotUri": snapshot_uri,
}
# Set* operations that the DVR's "network configuration" interface and the
# account/time settings call. All of them accept the values and return the
# empty schema-valid ...Response element (see set_ok). Without these the DVR
# receives a SOAP fault instead and reports "Falha SOAP invÃ¡lida".
SET_OPS = {
    "SetNetworkInterfaces",
    "SetNetworkProtocols",
    "SetNetworkDefaultGateway",
    "SetDNS",
    "SetNTP",
    "SetHostname",
    "SetSystemDateAndTime",
    "SetUser",
    "SetSystemFactoryDefault",
    "SetSynchronizationPoint",
    "SetVideoEncoderConfiguration",
    "SetOSD",
    "CreateOSD",
    "SetMask",
    "CreateMask",
    "SetAnalyticsEngineControl",
}
for _op in SET_OPS:
    OPS[_op] = (lambda a: lambda ns: set_ok(a, ns))(_op)
# ONVIF allows these without authentication; DVRs commonly probe them
# anonymously before asking for credentials. GetCapabilities is cited in the
# ONVIF spec as not requiring auth and Intelbras/Dahua firmware probes it
# anonymously first -- answering NotAuthorized there stalls the whole add.
ANONYMOUS = {"GetSystemDateAndTime", "GetDeviceInformation", "GetCapabilities", "GetScopes"}


async def soap(request):
    raw = await request.read()
    try:
        root = etree.fromstring(raw)
    except etree.XMLSyntaxError:
        print(f"[soap] {request.remote} INVALID_XML", flush=True)
        return fault("invalid XML")
    action_el = next(
        (
            x
            for x in root.iter()
            if x.tag.startswith("{") and etree.QName(x).localname.startswith(("Get", "Set"))
        ),
        None,
    )
    action = etree.QName(action_el).localname if action_el is not None else ""
    anonymous = action in ANONYMOUS
    ok = anonymous or authenticated(root)
    print(
        f"[soap] {request.remote} {action or '?'} anon={anonymous} auth={ok}",
        flush=True,
    )
    try:
        # Verbose: dump what the DVR actually sends, for Intelbras quirks.
        with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "_bridge-dump.log"), "a", encoding="utf-8") as f:
            f.write("=" * 80 + "\n")
            f.write(
                f"[{datetime.now(timezone.utc).isoformat(timespec='seconds')}] "
                f"{request.remote} {request.path} action={action} anon={anonymous} auth={ok}\n"
            )
            f.write(etree.tostring(root, pretty_print=True).decode("utf-8", "replace"))
            f.write("\n")
    except Exception:
        pass
    if not ok:
        return fault("ONVIF authentication failed", subcode="ter:NotAuthorized")
    handler = OPS.get(action)
    if handler is None:
        return fault(
            f"unsupported operation: {action}", subcode="ter:ActionNotSupported"
        )
    ns = etree.QName(action_el).namespace
    return handler(ns)


# ----------------------------------------------------------------------------
# app
# ----------------------------------------------------------------------------
app = web.Application()
app.router.add_post("/onvif/device_service", soap)
app.router.add_post("/onvif/media_service", soap)
app.router.add_post("/onvif/media2_service", soap)
app.router.add_get("/snapshot", snapshot)
app.router.add_get("/health", lambda r: web.json_response({"status": "ok"}))

if __name__ == "__main__":
    threading.Thread(target=run_ws_discovery, daemon=True).start()
    # Bind 0.0.0.0 so the bridge answers on the LAN IP AND on loopback
    # (the stack scripts probe /health via 127.0.0.1 as well).
    web.run_app(app, host=os.getenv("BIND_IP", "0.0.0.0"), port=HTTP_PORT)