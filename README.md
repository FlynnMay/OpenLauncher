# OpenLauncher

A home screen for Android TV and Google TV that you lay out yourself, from a
browser.

It shows your apps and the TV's inputs as cards, arranged the way you like,
with folders, sidebars, a clock, the weather and what is playing. The TV
serves an editor on your network: open it on a phone or computer and the
changes appear on the TV as you make them.

**Early access.** This is version 0.x. Expect rough edges, and changes that
break things between releases. It is developed against one TCL Google TV;
other devices may behave differently. It is installed by sideloading and is
not on the Play Store.

## What it does

On the TV:

- Lists installed apps with their TV banners, and the TV's inputs (HDMI
  ports, tuner) as cards beside them.
- Panes hold cards and other panes. You set each one's place and size, how
  things are arranged inside, and whether it scrolls.
- Folders and sidebars are panes that open over the home screen.
- Components: text, pictures, icons, meters and buttons, plus a clock, the
  weather (from Open-Meteo), now playing, and widgets from installed apps.
- Prefabs: a component you saved to reuse, with variables that each use can
  set. The app card, the clock and the others are prefabs you can edit.
- Actions on a press, a hold or on focus: open an app, switch input, control
  playback, show or hide a pane, set a variable.
- A menu on holding OK, with Open, App info, Force stop, Uninstall and
  Remove, which you can change.
- Styling for anything: fills and gradients, borders, corners, padding, text.
- Icon packs. The Material Symbols set is built in.
- Wallpaper as pictures or looping video, one or several in turn.
- Other apps' notifications, shown in a corner of the screen.
- Takes over the remote's Home button.
- Updates itself from this repository's releases.

From a phone or computer:

- The editor is the launcher itself running in the browser, showing what the
  TV shows, with editing on top. It also has undo and redo, a tree of
  everything on screen, and managers for uploaded files and packs.
- It can be used like the TV: pressing a card opens that app on the TV.

## Requirements

- A TV or box running Android 8.0 or later (API 26), 32- or 64-bit ARM.
- A way to sideload an APK, such as ADB.
- USB debugging turned on, for the one-step setup and for updates.

## Install

1. Download `openlauncher-<version>.apk` from
   [Releases](https://github.com/FlynnMay/OpenLauncher/releases).
2. Install it on the TV:

   ```bash
   adb connect <tv-address>:5555
   adb install openlauncher-<version>.apk
   ```

3. Open OpenLauncher from the TV's app list.
4. Open **Settings** on its home screen and choose **Set up automatically**.

### Setup and the Home button

Google TV does not let you choose a different home app. OpenLauncher uses an
accessibility service to catch the Home button and to replace the stock home
screen when it appears.

**Set up automatically** needs USB debugging to be on in the TV's developer
options. The TV asks you to allow a debugging connection: tick "Always
allow". That connection is OpenLauncher talking to the TV's own ADB service
to grant itself what it needs.

The same setup lets OpenLauncher show notifications and what is playing,
show widgets from other apps, force stop apps, and install its own updates.

To undo it, turn off **Home button opens OpenLauncher** in Settings.

## Updates

OpenLauncher checks this repository for a newer release shortly after it
starts and once a day.

| Setting | What happens |
|---|---|
| Notify (default) | A notice appears on the TV. Install from **Settings → Updates**. |
| Install | The update installs itself once the launcher is on screen and the remote has been left alone for five minutes. |
| Off | Nothing is checked. **Settings → Updates** still checks when pressed. |

The setting is in the editor, under **Updates**, where you can also check and
install from the browser.

Updates are installed through the TV's debugging service, so **Set up
automatically** has to have been run. The download is checked against the
size and hash the release states, and only a newer copy of OpenLauncher
signed with the same key is installed. The launcher restarts when it is done.

Without setup, install a new release the way you installed the first one;
`adb install -r` keeps your layout.

## Customising

Open **Settings** on the home screen and choose **Customise from your
phone**. Scan the QR code, or type the address it shows, on a device
connected to the same network.

The page shows your TV screen as it is and follows changes made on either
side. A switch at the top chooses between **Edit** and **Use**.

In Edit, drag things from the list onto the screen, drag them to move them,
and select one to change its settings. With nothing selected, the panel holds
the launcher's own settings: wallpapers, the screen, values, prefabs, the
hold-OK menu, notifications and updates.

In Use, the page behaves like the TV: tap, or use the arrow keys and Enter.

## Security

**The editor has no login.** Anyone on your network can open it, change your
layout, and open, force stop or uninstall apps on the TV through it. Use it
on a network you trust.

The page is only reachable while OpenLauncher is on screen.

## Known limitations

- On TCL TVs the Home button service is not started at boot. Open
  OpenLauncher once after a restart and it reconnects itself, or use an app
  that launches it at startup.
- While the Home button is taken over, long-pressing Home does not open the
  Google TV dashboard.
- The layout can only be edited from the editor, not on the TV.
- Notifications are only shown while OpenLauncher is on screen.
- Widgets from other apps are shown but cannot be selected with the remote,
  and ones that need their own setup screen are not supported.
- A layout saved by a newer release is not read by an older one.

## Building from source

Needs Flutter 3.47 or later and the Android SDK.

```bash
flutter pub get
tool/build_for_release.sh
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

`tool/build_for_release.sh` zips the built-in packs, builds the editor for
the web, then builds one APK for 32- and 64-bit ARM. `tool/build_for_dev.sh`
does the same as a debug build for 32-bit ARM.

### Signing

A build is signed with the key described in `android/key.properties`, which
is not kept in git:

```properties
storeFile=/absolute/path/to/your.jks
storePassword=...
keyAlias=...
keyPassword=...
```

Without that file the Android debug key is used. Android only installs an
update signed with the same key as what is installed, so a build of your own
cannot replace an official release, or the other way round, without
uninstalling first.

### Releasing

1. Set the version in `pubspec.yaml` and in
   `lib/core/config/app_version.dart`. A test holds them equal.
2. Commit, then tag it and push the tag:

   ```bash
   git tag v0.2.0
   git push origin v0.2.0
   ```

`.github/workflows/release.yml` then runs the checks, builds, signs with the
key in the repository's secrets (`KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`,
`KEY_ALIAS`, `KEY_PASSWORD`) and publishes the release with its APK. Installed
launchers find it from there.

Versions are plain `X.Y.Z`. Publish releases as normal releases: one marked
as a pre-release is not seen by the launcher.

## Development

```bash
flutter analyze
flutter test
```

```
lib/
  core/        the model, with no UI: components, prefabs, entities, actions,
               operations, variables, style, layout, config, packs, updates
  platform/    interface to the device, with a fake for tests
  features/    what the TV draws: home, components, notifications, settings,
               wallpaper
  server/      the web API, uploads, and serving the editor
  editor/      the editor: the launcher as a web app, plus editing
packs/         the built-in packs, as folders
tool/          build scripts
pigeons/       definition of the Dart <-> Kotlin bridge
android/       Kotlin: apps, inputs, Home button service, setup, updates,
               notifications and media, app widgets
test/          unit and widget tests
```

The editor is a second entry point, `lib/editor/main.dart`. It runs the same
home screen as the TV with the device swapped for the TV's web API, so
anything under `features/` has to work in a browser as well.

Imports of the project's own files are written `package:openlauncher/...`.
The areas of `core/` each have a barrel file; code outside the folder imports
that.

After editing `pigeons/launcher_api.dart`, regenerate the bridge:

```bash
dart run pigeon --input pigeons/launcher_api.dart
```

The saved config carries a format version (`v`) and the release that wrote it
(`app`). To change the saved format, add a step to
`lib/core/config/migrations/migrations.dart` and raise `saveVersion`.

Debug builds are very slow on the 32-bit x86 Android TV emulator. Use a
release build there.

## Licence

No licence has been chosen yet, so for now all rights are reserved.
