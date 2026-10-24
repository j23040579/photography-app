#!/usr/bin/env python3
"""Restore missing Gradle wrapper files using the installed Flutter SDK.

The real checkout is never passed to `flutter create`. Existing wrapper and
application files are preserved; generated files come from a temporary project.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile

WRAPPER_FILES = (
    Path('gradlew'),
    Path('gradlew.bat'),
    Path('gradle/wrapper/gradle-wrapper.jar'),
    Path('gradle/wrapper/gradle-wrapper.properties'),
)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flutter', default='flutter', help='Flutter executable path')
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    android = root / 'android'
    if not (android / 'app').is_dir():
        raise SystemExit('Expected Android platform source in android/app; refusing to create or replace it.')
    missing = [path for path in WRAPPER_FILES if not (android / path).is_file()]
    if not missing:
        print('Android Gradle wrapper files already exist.')
        return
    flutter = shutil.which(args.flutter)
    if flutter is None:
        raise SystemExit('Flutter is not on PATH. Install Flutter 3.47.8, then retry.')
    with tempfile.TemporaryDirectory(prefix='photograph-wrapper-') as temporary:
        generated = Path(temporary) / 'photograph'
        subprocess.run(
            [flutter, 'create', '--platforms=android', '--org=com.photograph',
             '--project-name=photograph', '--no-pub', '--empty', str(generated)],
            check=True,
        )
        for relative in missing:
            source = generated / 'android' / relative
            if not source.is_file():
                raise SystemExit(f'Flutter did not generate {relative}; no replacement was invented.')
        for relative in missing:
            destination = android / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            # Exclusive creation preserves a file another process may have made.
            try:
                with destination.open('xb') as output, (generated / 'android' / relative).open('rb') as source:
                    shutil.copyfileobj(source, output)
            except FileExistsError:
                print(f'Preserved existing android/{relative}')
                continue
            if relative == Path('gradlew'):
                destination.chmod(destination.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
            print(f'Added android/{relative}')


if __name__ == '__main__':
    main()
