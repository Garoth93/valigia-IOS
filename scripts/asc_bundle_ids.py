#!/usr/bin/env python3
"""App ID diagnostics for testflight.yml.

For each bundle id: prints the enabled capabilities and the existing
provisioning profiles with their App Groups / iCloud containers. With
--delete-stale, deletes the profiles that miss the expected App Group
(e.g. generated before the group was assigned on developer.apple.com):
Xcode's automatic signing then creates fresh ones.

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH.
Usage: asc_bundle_ids.py [--delete-stale] --group <app group> <bundle id>...
"""
import base64
import plistlib
import sys
import urllib.parse

from asc_revoke_certs import call


def profile_entitlements(p):
    raw = base64.b64decode(p["attributes"].get("profileContent") or "")
    start, end = raw.find(b"<?xml"), raw.rfind(b"</plist>")
    if start < 0 or end < 0:
        return {}
    return plistlib.loads(raw[start:end + len(b"</plist>")]).get("Entitlements", {})


def main(args):
    delete = "--delete-stale" in args
    group = args[args.index("--group") + 1] if "--group" in args else None
    ids = [a for i, a in enumerate(args) if not a.startswith("--") and (i == 0 or args[i - 1] != "--group")]
    for ident in ids:
        q = urllib.parse.urlencode({"filter[identifier]": ident, "include": "bundleIdCapabilities", "limit": 20})
        r = call("GET", f"/bundleIds?{q}")
        match = [b for b in r.get("data", []) if b["attributes"]["identifier"] == ident]
        if not match:
            print(f"::warning::App ID {ident} non registrato (lo crea la firma automatica)")
            continue
        caps = sorted({i["attributes"]["capabilityType"] for i in r.get("included", []) if i["type"] == "bundleIdCapabilities"})
        print(f"{ident}: capability {', '.join(caps) or 'nessuna'}")
        profiles = call("GET", f"/bundleIds/{match[0]['id']}/profiles?limit=50").get("data", [])
        for p in profiles:
            a = p["attributes"]
            ent = profile_entitlements(p)
            groups = ent.get("com.apple.security.application-groups", [])
            icloud = ent.get("com.apple.developer.icloud-container-identifiers", [])
            print(f"  profilo «{a.get('name')}» ({a.get('profileType')}, {a.get('profileState')}, creato {a.get('createdDate')}): "
                  f"gruppi {groups or '—'}, iCloud {icloud or '—'}")
            if delete and group and group not in groups:
                try:
                    call("DELETE", f"/profiles/{p['id']}")
                    print(f"  → eliminato (senza {group}): Xcode ne crea uno nuovo")
                except Exception as e:  # noqa: BLE001
                    print(f"::warning::Non riesco a eliminare «{a.get('name')}»: {e}")


if __name__ == "__main__":
    main(sys.argv[1:])
