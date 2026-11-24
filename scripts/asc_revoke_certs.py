#!/usr/bin/env python3
"""Revokes signing certificates by serial number through the App Store
Connect API (used by testflight.yml to remove the development certificate
that automatic signing creates on each throw-away CI runner).

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH.  Arg: PEM file with the
certificates exported from the runner keychain.
"""
import json
import os
import sys
import time
import urllib.request

import jwt  # pyjwt[crypto]
from cryptography import x509

API = "https://api.appstoreconnect.apple.com/v1"


def token():
    key = open(os.environ["ASC_KEY_PATH"]).read()
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
        key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )


def call(method, path):
    req = urllib.request.Request(API + path, method=method, headers={"Authorization": f"Bearer {token()}"})
    with urllib.request.urlopen(req, timeout=30) as r:
        body = r.read()
        return json.loads(body) if body else {}


def main(pem_path):
    data = open(pem_path, "rb").read()
    wanted = set()
    for block in data.split(b"-----END CERTIFICATE-----"):
        if b"BEGIN CERTIFICATE" in block:
            cert = x509.load_pem_x509_certificate(block + b"-----END CERTIFICATE-----\n")
            wanted.add(format(cert.serial_number, "X"))
    if not wanted:
        return
    certs = call("GET", "/certificates?limit=200&filter[certificateType]=DEVELOPMENT,IOS_DEVELOPMENT").get("data", [])
    for c in certs:
        serial = (c["attributes"].get("serialNumber") or "").upper().lstrip("0")
        if serial in wanted:
            call("DELETE", f"/certificates/{c['id']}")
            print(f"Revocato {c['attributes'].get('name')} ({serial})")


if __name__ == "__main__":
    main(sys.argv[1])
