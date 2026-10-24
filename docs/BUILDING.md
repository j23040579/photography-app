# Building and installing Photograph

The project targets Android and Windows from one Flutter codebase. It stores albums and media on the device. Windows application builds require Windows with Visual Studio's **Desktop development with C++** workload; a Linux Flutter SDK cannot produce a Windows executable.

## Automated builds

The workflow in `.github/workflows/build.yml` uses Flutter **3.44.0**. It runs static analysis and the existing unit/widget tests before building either platform. The resolved dependency set is saved in `pubspec.lock`; CI enforces it with `flutter pub get --enforce-lockfile`.

After the repository is pushed to GitHub:

1. Open **Actions → Build Android and Windows**.
2. Select a successful push run, or choose **Run workflow**.
3. Download `photograph-android` or `photograph-windows-x64` from the run's artifacts.

The Android artifact contains `photograph-android.apk`. The Windows artifact contains `photograph-windows-x64.zip`, which includes the executable, DLLs, and data directory. Both artifacts include SHA-256 checksums. An artifact only exists after its corresponding job finishes successfully; merely adding the workflow does not build or publish an executable.

## Android installation

Transfer the APK to an Android device and open it. Android may ask you to allow installation from the browser or file manager you used. Permit that source for this installation. No Google Play account is required for direct APK installation.

The initial build uses Flutter's development signing key, including for release-mode APKs. This produces an installable development build, but it is not a production signing setup. Before public distribution, create and securely retain a private release keystore and configure Android release signing. Never commit the keystore or its passwords. Repeated CI runs can generate different development keys; installing an update signed by a different key requires uninstalling the existing app, which removes its local data. Use a stable release key before distributing updates.

Test importing a photo/video, camera capture, local data persistence after restart, and notifications on a physical Android device. Automated Dart tests do not verify operating-system permissions, camera hardware, or notification delivery.

## Windows installation

Extract `photograph-windows-x64.zip` to a folder and run the application `.exe` inside. Keep all supplied DLLs and the `data` folder beside the executable; copying only the `.exe` is insufficient. The package targets 64-bit Windows. Some machines may need Microsoft's Visual C++ 2015–2022 x64 Redistributable.

This is a portable application bundle rather than a signed installer. Windows may show its usual warning for an unsigned executable. Code signing and a Windows installer can be added separately when distributing publicly.

Verify media import, persistence after restart, and any available reminder/camera integration on the target Windows machine. Desktop camera and notification capabilities depend on the platform implementation and packaging; consult the application's current status messages rather than assuming Android behavior applies unchanged.

## Local development and builds

Install the pinned Flutter SDK and run `flutter doctor -v`. Set up the Android SDK and accept its licenses for Android, or install the Windows C++ toolchain for Windows. Then, from the repository root:

```sh
flutter pub get
flutter analyze --fatal-infos
flutter test
```

Build Android on a supported development host:

```sh
python3 tool/bootstrap_android.py
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`. The bootstrap helper only restores absent Gradle wrapper files from a temporary project made with the installed Flutter SDK; it preserves the app manifest, Gradle settings, and Dart code. It needs a working SDK and network access for any SDK-managed downloads. On Windows, use `python` in place of `python3` if needed.

Build Windows **on a Windows host**:

```sh
flutter config --enable-windows-desktop
flutter build windows --release
```

Output: the complete `build/windows/x64/runner/Release/` directory. Distribute that directory together, typically as a ZIP.

Run on an attached Android device or a Windows development machine with:

```sh
flutter devices
flutter run -d DEVICE_ID
```

No backend API key is required for the app's offline suggestion workflow. Hardware-dependent tests and an actual successful platform build remain necessary before claiming that a particular APK or Windows bundle is ready to distribute.

## This cloud workspace

The retained SDK is `/workspace/flutter-prebuilt` (Flutter 3.44.0), with Java compiler `/workspace/jdk21`, Android SDK `/workspace/android-sdk` (platforms 35 and 36), pub cache `/workspace/pub-cache`, and Gradle cache `/workspace/gradle-cache`. The JDK archive SHA-256 was verified against the publisher's checksum. Use the system Java trust store for this session's proxy CA, keeping certificate verification enabled:

```sh
export PATH=/workspace/flutter-prebuilt/bin:/workspace/jdk21/bin:$PATH
export JAVA_HOME=/workspace/jdk21
export JAVA_TOOL_OPTIONS=-Djavax.net.ssl.trustStore=/etc/ssl/certs/java/cacerts
export PUB_CACHE=/workspace/pub-cache
export XDG_CONFIG_HOME=/workspace/tool-config
export FLUTTER_SUPPRESS_ANALYTICS=true
export ANDROID_HOME=/workspace/android-sdk
export ANDROID_USER_HOME=/workspace/android-user
export GRADLE_USER_HOME=/workspace/gradle-cache
```

These are session tooling paths, not requirements on an ordinary developer's PC. Dart analysis and Android tooling also need write access to their local configuration folders under the user's home directory.
