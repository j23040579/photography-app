"""Validate CI OAuth settings without logging values, then write build defines."""
import hashlib
import json
import os
from pathlib import Path
import re


def normalize_secret(raw, client_id):
    value = raw.strip()
    try:
        if value.startswith('{'):
            value = json.loads(value)
        elif value.startswith('"'):
            try:
                value = json.loads(value.rstrip(','))
            except json.JSONDecodeError:
                # Accept a copied JSON field line, including its trailing comma.
                value = json.loads('{' + value.rstrip(',') + '}')
        elif value.startswith("'") and value.endswith("'"):
            value = value[1:-1]
        if isinstance(value, dict):
            containers = [value[key] for key in ('installed', 'web') if key in value]
            if len(containers) > 1:
                raise ValueError('ambiguous credential document')
            if containers:
                value = containers[0]
            if not isinstance(value, dict):
                raise ValueError('invalid credential document')
            recorded_id = value.get('client_id', value.get('DRIVE_CLIENT_ID'))
            if recorded_id is not None and recorded_id.strip() != client_id:
                raise ValueError('client mismatch')
            value = value.get('client_secret', value.get('DRIVE_CLIENT_SECRET'))
        if not isinstance(value, str) or not re.fullmatch(r'[A-Za-z0-9_.+=/-]+', value.strip()):
            raise ValueError('invalid secret value')
        return value.strip()
    except (ValueError, TypeError, AttributeError):
        raise ValueError(
            'DRIVE_CLIENT_SECRET must contain the secret value, a quoted value, '
            'or a Google credential JSON document for the same OAuth client. '
            'Check that both repository secrets belong to the same Desktop app client.'
        ) from None


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
    values["DRIVE_CLIENT_SECRET"] = normalize_secret(values["DRIVE_CLIENT_SECRET"], values["DRIVE_CLIENT_ID"])
    return values


def main():
    try:
        values = build_settings(os.environ)
    except ValueError as error:
        print("::error title=Google OAuth configuration::" + str(error))
        raise SystemExit(1) from None
    normalized = [name for name in values if os.environ.get(name, "") != values[name]]
    if normalized:
        print("::notice title=OAuth configuration normalization::Normalized private settings: " + ", ".join(normalized))
    # A fingerprint lets us compare builds with the supplied client without
    # publishing the actual configuration or the client secret.
    fingerprint = hashlib.sha256(values["DRIVE_CLIENT_ID"].encode()).hexdigest()[:12]
    print("::notice title=Google OAuth Client ID::Client ID fingerprint (SHA-256/12): " + fingerprint)
    output = Path(".dart_tool/drive_build.json")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(values), encoding="utf-8")
    output.chmod(0o600)


if __name__ == "__main__":
    main()
