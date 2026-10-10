# OpenLauncher

A home screen for Android TV and Google TV, written in Flutter.

It shows your apps and the TV's own inputs as cards, arranged the way you
like, and is customised from a web page served by the TV.

This is an early project, developed against a TCL Google TV. It is installed
by sideloading and is not on the Play Store.

## What it does

- Lists installed apps with their TV banners and launches them with the remote.
- Shows the TV's inputs (HDMI ports, tuner) as cards next to the apps. Devices
  without inputs, such as streaming boxes, just don't get these cards.
- Serves a config page on the local network where you arrange everything
  below, hide cards, give them custom pictures, and set a wallpaper.
- Panes: backgrounds that hold cards, widgets and other panes. You set each
  one's place and size. Inside, items go in order, on cells you choose, or
  anywhere at any size. The screen itself is one big pane, edge to edge, so
  things can also sit outside every pane.
- Panes and cards can have their own background (a colour or a gradient,
  with transparency) and border colour.
- Folders and panels: a card that opens a popup holding other cards. You choose
  where the popup opens and how big it is.
- Moving with the remote prefers cards in the pane you are in, then what is
  straight ahead. The config page can draw where each direction leads.
- Sidebars: a pane on any edge of the screen that opens over the home screen
  when you move onto it.
- Settings is a card like any other. If you remove it, a Settings button
  appears at the top right of the TV screen instead.
- Widgets: clock, weather (from Open-Meteo), now playing, and widgets from
  installed apps.
- Quick actions: hold OK on a card for Open, App info, Force stop, Uninstall
  and Remove. You choose which appear and in what order.
- Shows notifications from other apps in a corner of the screen.
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

The Layout tab shows your TV screen. Drag things where you want them (on a
phone, hold an item for a moment first). Tap an item to resize it, by number
or by dragging its edges, change its colours, or remove it; "Select several"
does the same to many at once. Tap a pane for its settings, or "Screen ⚙" for the
whole screen's; "+ Apps…" there adds apps, including ones you removed.

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

The same setup lets OpenLauncher see notifications and what is playing, show
widgets from other apps, and force stop apps from the quick actions. Without
it those features stay empty, and Force stop opens the TV's own app screen.

## Known limitations

- On TCL TVs the Home button service is not started at boot. Open OpenLauncher
  once after a restart and it reconnects itself, or use an app that launches it
  at startup. Expect a delay of around half a minute after boot in that case.
- While the Home button is taken over, long-pressing Home does not open the
  Google TV dashboard.
- The wallpaper is dimmed by a fixed amount.
- Notifications are only shown while OpenLauncher is on screen.
- Widgets from other apps are shown but cannot be selected with the remote,
  and ones that need their own setup screen are not supported.
- Popups are opened from a card; they cannot yet be tied to a remote button.
- Tested on one TCL TV and the Android TV emulator. Other devices may behave
  differently, particularly for inputs and the Home button.

## Project layout

```
lib/
  core/        cards, layout, config, wallpaper, widget data (no UI)
  platform/    interface to the device, with a fake for tests
  features/    TV screens: home, widgets, notifications, settings, wallpaper
  server/      web config API and file uploads
  editor/      the config page: the launcher itself as a web app, plus editing
tool/          build_editor.sh, which builds the config page into the app
pigeons/       definition of the Dart <-> Kotlin bridge
android/       Kotlin: app list, inputs, Home button service, setup,
               notifications and media, app widgets
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

Imports of the project's own files are written `package:openlauncher/...`,
never as relative paths (a lint enforces it). The areas of `core/` each have a
barrel file, such as `core/layout/layout.dart`; code outside the folder imports
that, and a new file in the folder is added to it.

After editing `pigeons/launcher_api.dart`, regenerate the bridge:

```bash
dart run pigeon --input pigeons/launcher_api.dart
```

Debug builds are very slow on the 32-bit x86 Android TV emulator and can be
killed for not responding. Use a release build there.
