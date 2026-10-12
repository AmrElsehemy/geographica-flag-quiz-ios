#!/usr/bin/env python3
"""Checks a release build is safe to upload, before spending 10 minutes archiving it.

    ADS_MODE=test|production [ADMOB_APP_ID=... ADMOB_REWARDED_UNIT_ID=...] Scripts/preflight-release.py

Exits non-zero (and says why) if anything would get the build rejected or ship test settings to the
App Store. Needs only the Python standard library.
"""
import os
import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SAMPLE_APP_ID = "ca-app-pub-3940256099942544~1458002511"
SAMPLE_UNIT_PREFIX = "ca-app-pub-3940256099942544/"

errors: list[str] = []
notes: list[str] = []


def fail(message: str) -> None:
    errors.append(message)


# --- ad configuration -------------------------------------------------------------------------
mode = os.environ.get("ADS_MODE", "production")
app_id = os.environ.get("ADMOB_APP_ID", "").strip()
unit_id = os.environ.get("ADMOB_REWARDED_UNIT_ID", "").strip()

if mode not in ("test", "production"):
    fail(f"ADS_MODE must be 'test' or 'production', got {mode!r}")
elif mode == "test":
    notes.append("ads mode: TEST (Google sample ads; fine for TestFlight, never for the App Store)")
else:
    if not re.fullmatch(r"ca-app-pub-\d+~\d+", app_id):
        fail("production build: ADMOB_APP_ID must be your real AdMob app id (ca-app-pub-XXXX~YYYY)")
    elif app_id == SAMPLE_APP_ID:
        fail("production build: ADMOB_APP_ID is Google's SAMPLE app id")
    if not re.fullmatch(r"ca-app-pub-\d+/\d+", unit_id):
        fail("production build: ADMOB_REWARDED_UNIT_ID must be your real rewarded ad unit id (ca-app-pub-XXXX/YYYY)")
    elif unit_id.startswith(SAMPLE_UNIT_PREFIX):
        fail("production build: ADMOB_REWARDED_UNIT_ID is Google's SAMPLE unit")
    notes.append("ads mode: PRODUCTION")

# --- project settings -------------------------------------------------------------------------
project = (ROOT / "project.yml").read_text()


def setting(name: str) -> str | None:
    match = re.search(rf"^\s*{re.escape(name)}:\s*\"?([^\"\n#]+?)\"?\s*(?:#.*)?$", project, re.M)
    return match.group(1).strip() if match else None


bundle_id = setting("PRODUCT_BUNDLE_IDENTIFIER")
if not bundle_id or bundle_id.startswith("com.example"):
    fail(f"bundle id looks unset or placeholder: {bundle_id!r}")
version = setting("MARKETING_VERSION")
if not version or not re.fullmatch(r"\d+(\.\d+){1,2}", version):
    fail(f"MARKETING_VERSION must look like 1.0 or 1.0.0, got {version!r}")
if "ITSAppUsesNonExemptEncryption" not in project:
    fail("ITSAppUsesNonExemptEncryption is missing from project.yml (export-compliance prompt on every build)")
if "com.apple.developer.game-center" not in project:
    fail("the Game Center entitlement is missing from project.yml")
notes.append(f"bundle id {bundle_id}, version {version}")

# --- required files ---------------------------------------------------------------------------
privacy = ROOT / "App" / "PrivacyInfo.xcprivacy"
if not privacy.exists():
    fail("App/PrivacyInfo.xcprivacy is missing (required for apps that use UserDefaults and similar APIs)")

icon = ROOT / "App" / "Assets.xcassets" / "AppIcon.appiconset" / "icon-1024.png"
if not icon.exists():
    fail("the 1024 px app icon is missing")
else:
    data = icon.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        fail("the app icon is not a PNG")
    else:
        width, height = struct.unpack(">II", data[16:24])
        color_type = data[25]
        if (width, height) != (1024, 1024):
            fail(f"the app icon must be 1024x1024, is {width}x{height}")
        if color_type in (4, 6):
            fail("the app icon has an alpha channel; the App Store rejects that")

# --- result -----------------------------------------------------------------------------------
for note in notes:
    print("ok  ", note)
if errors:
    print()
    for error in errors:
        print("FAIL", error)
    sys.exit(1)
print("preflight passed")
