#!/usr/bin/env python3
"""Update the text and phone screenshots of one Google Play store listing.

Based on bird_tracker's play_screenshots.py: one Play Developer API "edit" —
open, set the short and full description of one language, replace its phone
screenshots with the given images in file name order, commit. The title, the
feature graphic, the icon and every other language stay as they are.

    play_listing.py <package name> --texts store-listing.json --images <dir>
                    [--language sr] [--key sa.json] [--send-for-review] [--dry-run]

--texts is the JSON from marketing/store-listing.json; its "google_play"
section holds {"<language>": {"shortDescription": ..., "fullDescription": ...}}.
By default the edit is committed WITHOUT sending it for review (needs Managed
publishing on in Play Console — otherwise Play refuses and nothing changes): the changes
wait in Play Console (Publishing overview) and go out together with the next
release you send for review there. --send-for-review sends them right away —
a listing change goes live on approval, independently of any release.

Credentials are a service account JSON key (PLAY_SERVICE_ACCOUNT_JSON or --key)
that Play Console granted "Manage store presence" for the app.

Needs: pip3 install google-api-python-client google-auth
"""

import argparse
import json
import os
import sys

from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
from googleapiclient.http import MediaFileUpload

SCOPES = ["https://www.googleapis.com/auth/androidpublisher"]
MAX_IMAGES = 8
EXTENSIONS = (".png", ".jpg", ".jpeg")
MIME = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg"}
LIMITS = {"shortDescription": 80, "fullDescription": 4000}


def fail(message):
    print(f"play_listing: {message}", file=sys.stderr)
    sys.exit(1)


def api_message(error):
    """The human-readable part of a Play API error, if the body carries one."""
    try:
        return json.loads(error.content)["error"]["message"]
    except (ValueError, KeyError, TypeError):
        return str(error)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("package", help="applicationId, e.g. rs.antonijevic.invoice2ips")
    parser.add_argument("--texts", required=True, help="store-listing.json")
    parser.add_argument("--images", required=True, help="phone screenshots, uploaded in file name order")
    parser.add_argument("--language", default="sr", help="listing language (default: sr)")
    parser.add_argument("--key", default=os.environ.get("PLAY_SERVICE_ACCOUNT_JSON"),
                        help="service account JSON key (default: $PLAY_SERVICE_ACCOUNT_JSON)")
    parser.add_argument("--send-for-review", action="store_true",
                        help="send the changes for review now instead of leaving them pending")
    parser.add_argument("--dry-run", action="store_true", help="read only, print the plan")
    args = parser.parse_args()

    if not args.key or not os.path.isfile(args.key):
        fail("no service account key: set PLAY_SERVICE_ACCOUNT_JSON or pass --key")
    with open(args.texts, encoding="utf-8") as f:
        texts = json.load(f).get("google_play", {}).get(args.language)
    if not texts:
        fail(f"{args.texts} has no google_play.{args.language} texts")
    for field, limit in LIMITS.items():
        if not texts.get(field):
            fail(f"{field} for {args.language} is empty")
        if len(texts[field]) > limit:
            fail(f"{field} for {args.language} is {len(texts[field])} characters (max {limit})")
    files = sorted(os.path.join(args.images, name) for name in os.listdir(args.images)
                   if name.lower().endswith(EXTENSIONS))
    if not files or len(files) > MAX_IMAGES:
        fail(f"{len(files)} images in {args.images} — Play takes 1 to {MAX_IMAGES}")

    credentials = service_account.Credentials.from_service_account_file(args.key, scopes=SCOPES)
    edits = build("androidpublisher", "v3", credentials=credentials, cache_discovery=False).edits()
    package, language = args.package, args.language
    dry = "(dry run) " if args.dry_run else ""

    try:
        edit_id = edits.insert(packageName=package, body={}).execute()["id"]
        listings = {item["language"]: item for item in
                    edits.listings().list(packageName=package, editId=edit_id).execute()
                    .get("listings", [])}
        if language not in listings:
            fail(f"{package} has no '{language}' listing (it has: {', '.join(listings) or 'none'})")
        listing = listings[language]
        current = edits.images().list(packageName=package, editId=edit_id, language=language,
                                      imageType="phoneScreenshots").execute().get("images", [])

        print(f"==> {package} / {language} (title stays: {listing.get('title')})")
        for field in LIMITS:
            same = listing.get(field, "").strip() == texts[field].strip()
            print(f"    {dry}{field}: {'unchanged' if same else 'update'} ({len(texts[field])} chars)")
        print(f"    {dry}phoneScreenshots: replace {len(current)} with {len(files)}:")
        for path in files:
            print(f"      {os.path.basename(path)} ({os.path.getsize(path) / 1e3:.0f} kB)")

        if args.dry_run:
            edits.delete(packageName=package, editId=edit_id).execute()
            print("✓ dry run: nothing was changed")
            return

        edits.listings().patch(packageName=package, editId=edit_id, language=language, body={
            "shortDescription": texts["shortDescription"],
            "fullDescription": texts["fullDescription"],
        }).execute()
        print("    texts updated")
        if current:
            edits.images().deleteall(packageName=package, editId=edit_id, language=language,
                                     imageType="phoneScreenshots").execute()
        for path in files:
            media = MediaFileUpload(path, mimetype=MIME[os.path.splitext(path)[1].lower()])
            edits.images().upload(packageName=package, editId=edit_id, language=language,
                                  imageType="phoneScreenshots", media_body=media).execute()
            print(f"    uploaded {os.path.basename(path)}")

        if args.send_for_review:
            edits.commit(packageName=package, editId=edit_id).execute()
            print("    committed and sent for review")
        else:
            try:
                edits.commit(packageName=package, editId=edit_id,
                             changesNotSentForReview=True).execute()
            except HttpError as error:
                if "sent for review automatically" not in api_message(error):
                    raise
                fail("Play sends this app's changes for review automatically (Managed publishing"
                     " is off), so they can't wait — nothing was changed. Turn on Managed"
                     " publishing in Play Console, or run again with --send-for-review.")
            print("    committed WITHOUT review: the changes wait in Play Console → Publishing"
                  " overview and go out with the next changes you send for review")
    except HttpError as error:
        fail(f"Play API {error.resp.status}: {api_message(error)}")

    print(f"✓ {language} listing of {package}: texts and {len(files)} phone screenshots")


if __name__ == "__main__":
    main()
