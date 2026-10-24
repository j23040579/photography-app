"""Write CI OAuth settings to an ignored build file without logging values."""
import json
import os
from pathlib import Path

names = ("DRIVE_CLIENT_ID", "DRIVE_CLIENT_SECRET")
missing = [name for name in names if not os.environ.get(name)]
if missing:
    raise SystemExit("Add GitHub Actions repository secrets: " + ", ".join(missing))
output = Path(".dart_tool/drive_build.json")
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps({name: os.environ[name] for name in names}), encoding="utf-8")
output.chmod(0o600)
