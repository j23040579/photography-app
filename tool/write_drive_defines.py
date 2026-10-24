"""Validate CI OAuth settings without logging values, then write build defines."""
import hashlib
import json
import os
from pathlib import Path
import re


def build_settings(environ):
    names = ("DRIVE_CLIENT_ID", "DRIVE_CLIENT_SECRET")
    values = {name: environ.get(name, "").strip() for name in names}
    missing = [name for name in names if not values[name]]
    if missing:
        raise ValueError("Add GitHub Actions repository secrets: " + ", ".join(missing))
    if not re.fullmatch(r"[0-9]+(?:-[A-Za-z0-9_-]+)?\.apps\.googleusercontent\.com", values["DRIVE_CLIENT_ID"]):
        raise ValueError(
            "DRIVE_CLIENT_ID must contain only the OAuth Client ID ending in "
            ".apps.googleusercontent.com. Copy it from Google Auth Platform > "
            "Clients > your Desktop app client. Do not paste JSON, a project "
            "ID, a client secret, quotes, or DRIVE_CLIENT_ID= into this secret."
        )
    if values["DRIVE_CLIENT_SECRET"].startswith(('{', '"', "'")):
        raise ValueError("DRIVE_CLIENT_SECRET must contain only its value, without JSON or quotes.")
    return values


def main():
    try:
        values = build_settings(os.environ)
    except ValueError as error:
        raise SystemExit(str(error)) from None
    trimmed = [name for name in values if os.environ.get(name, "") != values[name]]
    if trimmed:
        print("Trimmed pasted edge whitespace: " + ", ".join(trimmed))
    # A fingerprint lets us compare builds with the supplied client without
    # publishing the actual configuration or the client secret.
    fingerprint = hashlib.sha256(values["DRIVE_CLIENT_ID"].encode()).hexdigest()[:12]
    print("OAuth Client ID fingerprint (SHA-256/12): " + fingerprint)
    output = Path(".dart_tool/drive_build.json")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(values), encoding="utf-8")
    output.chmod(0o600)


if __name__ == "__main__":
    main()
