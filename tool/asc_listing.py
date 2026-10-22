#!/usr/bin/env python3
"""Put store texts and screenshots on the App Store version being prepared.

The listing counterpart of asc_submit.py, run before it: the version X.Y.Z is
found or created the same way (the one still editable is reused and renamed),
then every given localization gets its description, keywords and promotional
text, and every given screenshot set is replaced with the images of a
directory, in file name order. No build is attached and nothing is submitted —
tool/promote.sh (asc_submit.py) later submits this same version.

    asc_listing.py <bundle id> <X.Y.Z> --texts store-listing.json
                   --shots en-US:APP_IPHONE_67=marketing/screenshots/out/ios/en
                   [--shots ...] [--dry-run]

--texts is marketing/store-listing.json; its "app_store" section holds
{"<locale>": {"description": ..., "keywords": ..., "promotionalText": ...}}.
--shots LOCALE:DISPLAY_TYPE=DIR is repeatable; APP_IPHONE_67 takes the 6.9"
iPhone shots (1320x2868), APP_IPAD_PRO_3GEN_129 the 13" iPad ones (2064x2752).

Credentials from the app's ios/deploy.env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH
(the key needs the App Manager or Admin role).

Needs: pip3 install pyjwt cryptography requests
"""

import argparse
import hashlib
import json
import os
import sys
import time

import requests

from asc_submit import EDITABLE, Api

LIMITS = {"description": 4000, "keywords": 100, "promotionalText": 170}
EXTENSIONS = (".png", ".jpg", ".jpeg")
MAX_SHOTS = 10


def fail(message):
    print(f"asc_listing: {message}", file=sys.stderr)
    sys.exit(1)


def parse_shots(specs):
    shots = []
    for spec in specs or []:
        try:
            target, directory = spec.split("=", 1)
            locale, display_type = target.split(":", 1)
        except ValueError:
            fail(f"--shots {spec}: expected LOCALE:DISPLAY_TYPE=DIR")
        files = sorted(os.path.join(directory, n) for n in os.listdir(directory)
                       if n.lower().endswith(EXTENSIONS)) if os.path.isdir(directory) else []
        if not files or len(files) > MAX_SHOTS:
            fail(f"{directory}: {len(files)} images (App Store takes 1 to {MAX_SHOTS} per set)")
        shots.append((locale, display_type, files))
    return shots


def upload_screenshot(api, set_id, path):
    """Reserve, upload the parts, commit with the MD5; returns the screenshot id."""
    with open(path, "rb") as f:
        data = f.read()
    shot = api.post("/appScreenshots", {
        "type": "appScreenshots",
        "attributes": {"fileName": os.path.basename(path), "fileSize": len(data)},
        "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}},
    })
    for op in shot["attributes"]["uploadOperations"]:
        headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
        part = data[op["offset"]:op["offset"] + op["length"]]
        response = requests.request(op["method"], op["url"], headers=headers, data=part, timeout=120)
        if response.status_code >= 400:
            fail(f"upload of {path} → {response.status_code}: {response.text[:300]}")
    api.patch(f"/appScreenshots/{shot['id']}", {
        "type": "appScreenshots", "id": shot["id"],
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()},
    })
    return shot["id"]


def wait_processed(api, shot_ids):
    """Apple processes the images after upload; fail on the first one it rejects."""
    pending = set(shot_ids)
    for _ in range(120):  # do 10 minuta — Apple zna da obrađuje i po nekoliko minuta
        for shot_id in list(pending):
            state = api.get(f"/appScreenshots/{shot_id}")["data"]["attributes"]["assetDeliveryState"]
            if state["state"] == "COMPLETE":
                pending.discard(shot_id)
            elif state["state"] == "FAILED":
                errors = "; ".join(e.get("description", "") for e in state.get("errors") or [])
                fail(f"Apple rejected screenshot {shot_id}: {errors}")
        if not pending:
            return
        time.sleep(5)
    fail(f"{len(pending)} screenshot(s) still processing — check App Store Connect")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("bundle_id", help="e.g. rs.antonijevic.invoice2ips")
    parser.add_argument("version", help="App Store version string, X.Y.Z")
    parser.add_argument("--texts", help="store-listing.json")
    parser.add_argument("--shots", action="append", metavar="LOCALE:TYPE=DIR")
    parser.add_argument("--dry-run", action="store_true", help="read only, print the plan")
    args = parser.parse_args()

    for var in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH"):
        if not os.environ.get(var):
            fail(f"{var} is not set (source the app's ios/deploy.env)")
    texts = {}
    if args.texts:
        with open(args.texts, encoding="utf-8") as f:
            texts = json.load(f).get("app_store", {})
        for locale, fields in texts.items():
            for field, limit in LIMITS.items():
                if len(fields.get(field) or "") > limit:
                    fail(f"{field} for {locale} is {len(fields[field])} characters (max {limit})")
    shots = parse_shots(args.shots)
    if not texts and not shots:
        fail("nothing to do: pass --texts and/or --shots")

    api = Api(os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"], os.environ["ASC_KEY_PATH"])
    dry = "(dry run) " if args.dry_run else ""
    apps = api.get("/apps", **{"filter[bundleId]": args.bundle_id})["data"]
    if not apps:
        fail(f"no app with bundle id {args.bundle_id} in App Store Connect")
    app = apps[0]
    print(f"==> {app['attributes']['name']} ({args.bundle_id})")

    versions = api.get(f"/apps/{app['id']}/appStoreVersions", **{"filter[platform]": "IOS", "limit": 20})["data"]
    same = next((v for v in versions if v["attributes"]["versionString"] == args.version), None)
    if same and same["attributes"]["appStoreState"] not in EDITABLE:
        fail(f"version {args.version} is already {same['attributes']['appStoreState']} — it can't be edited")
    version = same or next((v for v in versions if v["attributes"]["appStoreState"] in EDITABLE), None)
    if version is None:
        print(f"    {dry}create version {args.version} (copies texts and screenshots of the live one)")
        if args.dry_run:
            print("✓ dry run: nothing was changed (localizations are listed once the version exists)")
            return
        version = api.post("/appStoreVersions", {
            "type": "appStoreVersions",
            "attributes": {"platform": "IOS", "versionString": args.version, "releaseType": "AFTER_APPROVAL"},
            "relationships": {"app": {"data": {"type": "apps", "id": app["id"]}}},
        })
    else:
        old = version["attributes"]["versionString"]
        print(f"    {dry}use version {args.version} ({version['attributes']['appStoreState']}"
              f"{'' if old == args.version else f', renamed from {old}'})")
        if old != args.version and not args.dry_run:
            api.patch(f"/appStoreVersions/{version['id']}", {
                "type": "appStoreVersions", "id": version["id"],
                "attributes": {"versionString": args.version},
            })

    localizations = {loc["attributes"]["locale"]: loc for loc in
                     api.get(f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations")["data"]}
    for locale in set(texts) | {s[0] for s in shots}:
        if locale not in localizations:
            fail(f"version {args.version} has no {locale} localization (it has: {', '.join(localizations)})")

    for locale, fields in texts.items():
        loc = localizations[locale]
        changed = {k: v for k, v in fields.items() if k in LIMITS and (loc["attributes"].get(k) or "") != v}
        print(f"    {dry}texts [{locale}]: {', '.join(changed) or 'unchanged'}")
        if changed and not args.dry_run:
            api.patch(f"/appStoreVersionLocalizations/{loc['id']}", {
                "type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": changed,
            })

    for locale, display_type, files in shots:
        loc = localizations[locale]
        sets = api.get(f"/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")["data"]
        shot_set = next((s for s in sets if s["attributes"]["screenshotDisplayType"] == display_type), None)
        current = api.get(f"/appScreenshotSets/{shot_set['id']}/appScreenshots")["data"] if shot_set else []
        print(f"    {dry}screenshots [{locale} {display_type}]: replace {len(current)} with {len(files)}")
        if args.dry_run:
            continue
        if shot_set is None:
            shot_set = api.post("/appScreenshotSets", {
                "type": "appScreenshotSets",
                "attributes": {"screenshotDisplayType": display_type},
                "relationships": {"appStoreVersionLocalization": {
                    "data": {"type": "appStoreVersionLocalizations", "id": loc["id"]}}},
            })
        for shot in current:
            api.call("DELETE", f"/appScreenshots/{shot['id']}")
        ids = []
        for path in files:
            ids.append(upload_screenshot(api, shot_set["id"], path))
            print(f"      uploaded {os.path.basename(path)}")
        wait_processed(api, ids)
        api.patch(f"/appScreenshotSets/{shot_set['id']}/relationships/appScreenshots",
                  [{"type": "appScreenshots", "id": i} for i in ids])

    print("✓ dry run: nothing was changed" if args.dry_run else
          f"✓ version {args.version}: texts and screenshots set — nothing was submitted")


if __name__ == "__main__":
    main()
