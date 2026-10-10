# OpenLauncher

A home screen for Android TV and Google TV, written in Flutter.

It shows your apps and the TV's own inputs as cards in one grid, and is
customised from a web page served by the TV.

This is an early project, developed against a TCL Google TV. It is installed
by sideloading and is not on the Play Store.

## What it does

- Lists installed apps with their TV banners and launches them with the remote.
- Shows the TV's inputs (HDMI ports, tuner) as cards next to the apps. Devices
  without inputs, such as streaming boxes, just don't get these cards.
- Serves a config page on the local network where you can reorder cards, hide
  them, give them custom pictures, and set a wallpaper.
- Wallpaper can be a picture (PNG, JPEG, animated GIF or WebP) or a looping
  video (MP4, WebM, MKV).
- Can take over the remote's Home button using an accessibility service.

## Requirements

- Android 8.0 or later (API 26) on a TV device.
- Flutter 3.47 or later to build.
- ADB access to the TV to install.

## Build and install

```bash
flutter pub get
flutter build apk --release --target-platform android-arm
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Use `--target-platform android-arm64` if your device is 64-bit.

After installing, open OpenLauncher from the TV's app list.

## Using it

### Customising

Open **Settings** at the top right of the home screen and choose **Customise
from your phone**. Scan the QR code, or type the address it shows, on a phone or
computer connected to the same network.

The page has no login. Anyone on your network can open it.

The page is only reachable while OpenLauncher is on screen.

### Home button

Google TV does not let you choose a different home app, so OpenLauncher uses an
accessibility service to catch the Home button and to replace the stock home
screen when it appears.

In **Settings**, choose **Set up automatically**. This needs USB debugging to
be turned on in the TV's developer options. The TV will ask you to allow a
debugging connection; that connection is OpenLauncher talking to the TV's own
ADB service to grant itself the permission it needs.

To undo it, turn off **Home button opens OpenLauncher** in the same screen.

## Known limitations

- On TCL TVs the Home button service is not started at boot. Open OpenLauncher
  once after a restart and it reconnects itself, or use an app that launches it
  at startup. Expect a delay of around half a minute after boot in that case.
- While the Home button is taken over, long-pressing Home does not open the
  Google TV dashboard.
- The wallpaper is dimmed by a fixed amount.
- Reordering on a phone uses arrow buttons; drag and drop only works with a
  mouse.
- Tested on one TCL TV and the Android TV emulator. Other devices may behave
  differently, particularly for inputs and the Home button.

## Project layout

```
lib/
  core/        cards, config, wallpaper model (no UI, no platform code)
  platform/    interface to the device, with a fake for tests
  features/    TV screens: home grid, settings, wallpaper
  server/      web config API and file uploads
assets/web/    the config page (one HTML file)
pigeons/       definition of the Dart <-> Kotlin bridge
android/       Kotlin: app list, inputs, Home button service, setup
test/          unit and widget tests
```

The TV screens and the web server are both clients of `core/`. Config is only
changed through `ConfigController`, so a change from either side reaches the
other.

## Development

```bash
flutter analyze
flutter test
```

After editing `pigeons/launcher_api.dart`, regenerate the bridge:

```bash
dart run pigeon --input pigeons/launcher_api.dart
```

Debug builds are very slow on the 32-bit x86 Android TV emulator and can be
killed for not responding. Use a release build there.
