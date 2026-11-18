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
- Everything on screen is a node, and nodes hold other nodes. A node gets its
  behaviour from modules you switch on: a layout (flow, grid, row, column or
  free), scrolling, a place and size, styling, focus, triggers, variables and
  docking. A section is a node with a layout and a heading.
- Visual nodes: text, pictures, icons and meters, plus a clock, the weather
  (from Open-Meteo), now playing, and widgets from installed apps.
- Screens: you can make several and choose which one the launcher starts on,
  or have it start on the last one you used.
- Folders and sidebars dock: they open over the home screen.
- Prefabs: a node you saved to reuse, with variables that each use can set.
  The app card, the clock and the others are prefabs you can edit, and you
  can go back to the original.
- Templates: text, pictures and many settings can read values, such as
  `{{source.label}}`, and a node can be shown or hidden by an expression.
- Actions on a press, a hold or on focus: open an app, switch input, control
  playback, show or hide a folder or sidebar, set a variable, or call a web
  address.
- A menu on holding OK, with Open, App info, Uninstall and Remove, which you
  can change.
- Styling for anything: fills and gradients, borders, corners, padding, text.
- Packs: folders of apps, inputs, prefabs, screens, fonts and icons that add
  to the launcher (see [Packs](#packs)). The Material Symbols icons and the
  launcher's own apps, inputs and prefabs are packs.
- Wallpaper as pictures or looping video, one or several in turn.
- Other apps' notifications, shown in a corner of the screen.
- Takes over the remote's Home button.
- Updates itself from this repository's releases.

From a phone or computer:

- The editor is the launcher itself running in the browser, showing what the
  TV shows, with editing on top. It also has undo and redo (kept across a
  restart of the TV), a tree of everything on screen, and managers for
  uploaded files and packs.
- Three modes: **Edit** changes the layout, **Test** works like the TV with the
  keyboard as the remote, and **Remote** is a remote for the TV: pressing a
  card opens that app on the TV.
- The editor never changes anything itself. Each change is sent to the TV as
  a command, which applies it, saves it and tells every open editor.

## Requirements

- A TV or box running Android 8.0 or later (API 26), 32- or 64-bit ARM.
- A way to sideload an APK, such as ADB.

## Install

1. Download `openlauncher-<version>.apk` from
   [Releases](https://github.com/FlynnMay/OpenLauncher/releases).
2. Install it on the TV:

   ```bash
   adb connect <tv-address>:5555
   adb install openlauncher-<version>.apk
   ```

3. Open OpenLauncher from the TV's app list.
4. Open **Settings** on its home screen and allow what you want under
   **Permissions**.

### Permissions

OpenLauncher asks for nothing by itself. Each permission is a row in
**Settings → Permissions**: it says whether it is allowed, and pressing it
opens the TV's own screen for it, where you turn OpenLauncher on.

| Permission | What it is for | The TV's screen |
|---|---|---|
| Home button | The remote's Home button opens OpenLauncher. | Accessibility |
| Notifications | Notifications from other apps, and what is playing. | Notification access |

Google TV does not let you choose a different home app. OpenLauncher uses an
accessibility service to catch the Home button and to replace the stock home
screen when it appears. To undo it, turn the service off on the same screen.

Widgets from other apps need the TV's say too. Where the TV has a question
for it, it is asked the first time a widget is placed.

#### When the TV has no screen for it

Some TVs leave these screens out, or do not list sideloaded apps on them.
Each can be allowed from a computer instead, with USB debugging on:

```bash
# Home button: lets OpenLauncher switch its own service on and off. Then
# press Home button in Settings.
adb shell pm grant com.maypoint.openlauncher android.permission.WRITE_SECURE_SETTINGS

# Notifications
adb shell cmd notification allow_listener com.maypoint.openlauncher/com.maypoint.openlauncher.NotificationService

# Widgets from other apps
adb shell appwidget grantbind --package com.maypoint.openlauncher --user 0
```

On Android 13 and later, a TV may grey out these switches for an app
installed from a file until you choose **Allow restricted settings** on the
app's info screen. Installing with `adb install` avoids that.

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

Updates are installed by the TV's own installer. Depending on the Android
version it installs straight away or asks you first, and the first time it
may ask you to allow OpenLauncher to install apps. The download is checked
against the size and hash the release states, and only a newer copy of
OpenLauncher signed with the same key is installed. The launcher opens again
when it is done.

Updating from 0.1.0, which installed through the TV's debugging service,
works where its automatic setup had been run. Otherwise install the new
release the way you installed the first one; `adb install -r` keeps your
layout.

## Customising

Open **Settings** on the home screen and choose **Customise from your
phone**. Scan the QR code, or type the address it shows, on a device
connected to the same network. The page asks for the **pairing code** the TV
is showing; enter it once and that browser stays paired.

The page shows your TV screen as it is and follows changes made on either
side. A switch at the top chooses between **Edit**, **Test** and **Remote**.

In Edit, drag things from the list onto the screen, drag them to move them,
and select one to change its settings. With nothing selected, the panel holds
the launcher's own settings: wallpapers, screens and the startup screen,
values, prefabs, packs, the hold-OK menu, notifications and updates.

In Test, the page behaves like the TV: click, or use the arrow keys and
Enter. In Remote, it drives the TV.

## Packs

A pack is a folder, or a `.zip` of one, that adds things to the launcher
without changing the app. It can hold:

- nodes for apps, inputs and values (the clock, the weather),
- prefabs and screens,
- sources, which fetch data from the TV or from a web address, and generators,
  which turn a source into one node per item,
- settings the user fills in, including secrets such as a token, and the
  sign in a source uses,
- fonts, icon sets and pictures.

The launcher's own apps, inputs, clock, weather and menu prefabs are in the
built in **System** pack, and the Material Symbols icons are in the
**Material** pack. They differ from a pack you add only in that they cannot
be deleted; edits you make are kept apart and can be reverted.

Packs are managed in the editor under **Packs**: install a `.zip`, fill in a
pack's settings, see why a pack failed to load, and remove one. The weather
card picks its own place, and falls back to the System pack's setting when
left empty.

Pack files are JSON (comments are allowed) and each names a schema in
`schemas/` in its `$schema` line, for autocomplete and checking in an editor.

## Security

The editor needs a pairing code. The code exists only while **Customise from
your phone** is open on the TV, changes each time, and pairing locks for a
growing time after five wrong tries. A paired browser keeps a cookie (for up
to 400 days), and the TV's API needs it; paired browsers are listed in the
editor under **Devices**, where one can be removed. Requests whose `Host` is
not the TV's own address are refused.

The connection is plain HTTP, so anyone who can watch your network traffic
could read it or take the cookie. Use it on a network you trust.

The page is only reachable while OpenLauncher is on screen.

## Known limitations

- Some TVs (TCL among them) do not start the Home button service at boot.
  With the `WRITE_SECURE_SETTINGS` grant above, OpenLauncher reconnects it
  when opened after a restart; without it, switch the service off and on in
  the TV's settings.
- An app cannot force stop another. **App info** in the menu opens the TV's
  screen that can.
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
  core/        the app's logic, with no UI: actions, operations and their
               services, variables, layout, screens, overlays, commands, config,
               packs, sources, access, updates
  platform/    interface to the device, with a fake for tests
  features/    what the TV draws: home, modules, notifications, settings,
               wallpaper, remote
  server/      the web API, pairing and sessions, uploads, and serving the
               editor
  editor/      the editor: the launcher as a web app, plus editing
packages/
  openlauncher_domain/
               pure Dart shared by the TV and the editor: nodes and modules,
               fields, variables and templates, styles, pack file reading, the
               layout rules, and the editing commands (slices) both sides run
packs/         the built in packs, as folders: material (icons) and system
               (the apps, inputs and prefabs the launcher starts with)
schemas/       JSON Schemas for pack files, made by tool/build_schemas.dart;
               a pack file names one in `$schema` for autocomplete and checks
tool/          build scripts
pigeons/       definition of the Dart <-> Kotlin bridge
android/       Kotlin: apps, inputs, Home button service, permissions, updates,
               notifications and media, app widgets
test/          unit and widget tests
```

The editor is a second entry point, `lib/editor/main.dart`. It runs the same
home screen as the TV with the device swapped for the TV's web API, so
anything under `features/` has to work in a browser as well. It talks to the
TV only through that API: an edit is a command made of an address and
operations, and the TV and the editor run the same code from
`openlauncher_domain` to apply it. A test holds that boundary.

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
