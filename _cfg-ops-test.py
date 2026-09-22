#!/usr/bin/env python3
"""_cfg-ops-test.py - verifies the config-only ONVIF ops the Intelbras DVR
calls after adding the virtual camera (encoder options, OSD, masks, analytics,
synchronization point). All must return HTTP 200 with parseable XML."""
import base64
import hashlib
import os
import secrets
import urllib.request
from datetime import datetime, timezone
from xml.etree import ElementTree as ET

MEDIA2 = "http://192.168.5.54:8000/onvif/media2_service"
USER = os.getenv("ONVIF_USER", "ovifadm")
PASS = os.getenv("ONVIF_PASSWORD", "change-onvif-password")

SOAP = "http://www.w3.org/2003/05/soap-envelope"
TD = "http://www.onvif.org/ver10/device/wsdl"
TT = "http://www.onvif.org/ver10/schema"
TR2 = "http://www.onvif.org/ver20/media/wsdl"


def password_digest(nonce_b64, created, password):
    return base64.b64encode(
        hashlib.sha1(base64.b64decode(nonce_b64) + created.encode() + password.encode()).digest()
    ).decode()


def call(action, body):
    created = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    nonce = base64.b64encode(secrets.token_bytes(16)).decode()
    digest = password_digest(nonce, created, PASS)
    security = (
        '<s:Header><Security xmlns="http://docs.oasis-open.org/wss/2004/01/'
        'oasis-200401-wss-wssecurity-secext-1.0.xsd" '
        'xmlns:u="http://docs.oasis-open.org/wss/2004/01/'
        'oasis-200401-wss-wssecurity-utility-1.0.xsd">'
        '<u:Timestamp><u:Created>%s</u:Created></u:Timestamp>'
        '<UsernameToken><Username>%s</Username>'
        '<Password Type="http://docs.oasis-open.org/wss/2004/01/'
        'oasis-200401-wss-username-token-profile-1.0#PasswordDigest">%s</Password>'
        '<Nonce EncodingType="http://docs.oasis-open.org/wss/2004/01/'
        'oasis-200401-wss-soap-message-security-1.0#Base64Binary">%s</Nonce>'
        '<u:Created>%s</u:Created></UsernameToken></Security></s:Header>'
    ) % (created, USER, digest, nonce, created)
    xml = (
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<s:Envelope xmlns:s="%s" xmlns:tds="%s" xmlns:tt="%s" xmlns:tr2="%s">%s'
        '<s:Body>%s</s:Body></s:Envelope>'
    ) % (SOAP, TD, TT, TR2, security, body)
    req = urllib.request.Request(
        MEDIA2,
        data=xml.encode("utf-8"),
        headers={"Content-Type": 'application/soap+xml; charset=utf-8; action="%s/%s"' % (TR2, action)},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            return resp.status, resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")


def check(name, action, body, expect_tag):
    s, x = call(action, body)
    ok_status = s == 200
    try:
        root = ET.fromstring(x)
        parsed = True
        found = expect_tag is None or root.find(".//{%s}%s" % (TR2, expect_tag)) is not None
    except ET.ParseError:
        parsed = False
        found = False
    fault = root is not None and root.find(".//{%s}Fault" % SOAP) is not None if parsed else True
    if ok_status and parsed and found and not fault:
        print("PASS  %s" % name)
    else:
        print("FAIL  %s  (status=%s parsed=%s found=%s fault=%s)" % (name, s, parsed, found, fault))
        if parsed:
            print(ET.tostring(root, encoding="unicode")[:400])


check("GetVideoEncoderConfigurationOptions", "GetVideoEncoderConfigurationOptions",
      "<tr2:GetVideoEncoderConfigurationOptions></tr2:GetVideoEncoderConfigurationOptions>", "Options")
check("GetVideoEncoderConfigurations", "GetVideoEncoderConfigurations",
      "<tr2:GetVideoEncoderConfigurations></tr2:GetVideoEncoderConfigurations>", "Configurations")
check("GetOSDs", "GetOSDs",
      "<tr2:GetOSDs></tr2:GetOSDs>", None)
check("GetOSDOptions", "GetOSDOptions",
      "<tr2:GetOSDOptions></tr2:GetOSDOptions>", "OSDOptions")
check("GetMaskOptions", "GetMaskOptions",
      "<tr2:GetMaskOptions></tr2:GetMaskOptions>", "Options")
check("GetAnalyticsConfigurations", "GetAnalyticsConfigurations",
      "<tr2:GetAnalyticsConfigurations></tr2:GetAnalyticsConfigurations>", None)
check("SetSynchronizationPoint", "SetSynchronizationPoint",
      "<tr2:SetSynchronizationPoint></tr2:SetSynchronizationPoint>", None)
print("fim")