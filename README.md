# photo graph

A Flutter photo journal for Android and Windows. Create an album, choose an occasion, get photo ideas, and keep the moments with photos, videos, comments, notes, and a rating.

## What it does

- Restaurant, party, travel, outdoors, everyday, and celebration albums.
- Five category-specific photo ideas per album. Edit, shuffle, like, complete, or attach a photo to each idea.
- Capture still photos with the Android camera or a Windows webcam; import existing photos and videos with system file pickers.
- View photos with zoom and play local videos. MP4/H.264 is recommended; other video formats depend on device codecs.
- Album star ratings and notes; private comments/captions on individual memories.
- A first-launch walkthrough with advice to plan albums one day ahead. Replay the walkthrough from the field guide.
- Native one-shot reminders at a chosen local date/time, for the album or a specific photo idea. One active reminder per album; setting another replaces it. Notifications require OS permission and can be delayed by battery/Focus settings. The reminder text is a snapshot of the idea when scheduled.
- A responsive cream, burgundy, and sage interface using #6D0808, #2D0000, #757D6F, and #EEEAD7.

## Offline machine learning

The app uses an on-device **online logistic preference model**, implemented in Dart. A like is positive feedback; a shuffle is negative feedback. Gradient updates learn weights for category, subject, and composition style. Scores plus randomized exploration rank the candidates. Model weights and novelty history persist with the journal, and work without any network request or model download.

This is a lightweight machine-learning recommender, **not a neural text generator or TensorFlow Lite model**. The model ranks 128 curated subject/composition combinations per category (768 total). A category's ideas do not repeat until its pool is exhausted, after which they cycle. User edits are unrestricted. Cold-start suggestions are randomized until the user gives feedback. See [the engine](lib/domain/suggestion_engine.dart) and its tests for the algorithm.

## Privacy and storage

“Add” imports an app-owned copy into the local application support directory. There is no cloud upload, account, public feed, cross-device sync, or server. Comments are private journal captions. Original imported files are never deleted by the app. A rotating local JSON backup protects the previous saved journal generation, with media cleanup deferred while that backup references it. This backup is on the same device, not disaster recovery. Uninstalling the app or losing the device can lose the journal; keep your original media separately.

Camera permission is requested for capture. Android's system picker grants access only to selected files; no broad storage permission is needed. Reminders use the OS scheduler, not a Dart timer that requires the app to stay open.

## Development and executables

See [BUILDING.md](docs/BUILDING.md) for the pinned Flutter SDK, validation commands, platform requirements, CI artifact downloads, and release signing. Android builds produce an APK; Windows builds produce a ZIP containing `photograph.exe` and the runtime files it needs. A Windows build host is required to compile the Windows executable.

```sh
flutter pub get
flutter analyze --fatal-infos
flutter test
python3 tool/bootstrap_android.py
flutter build apk --release
# On a Windows build host:
flutter build windows --release
```

This checkout starts without remote history. The CI workflow runs after the project is committed and pushed to GitHub; adding the workflow file alone does not run or publish a build.
