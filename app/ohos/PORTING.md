# HarmonyOS port status

This port is experimental. The unsigned debug HAP builds, but is not yet
validated as a usable application. It declares phone and PC (2in1) targets.

## Build

Use Flutter 3.41.10-ohos-1.0.1, the HarmonyOS SDK, and Rust with the
`aarch64-unknown-linux-ohos` target. Add the Flutter-OH and DevEco command-line tools to `PATH`, set `DEVECO_SDK_HOME` to your SDK directory, and run from the repository root:

```sh
bash support/scripts/build_harmony.sh
```

The script builds a Rust shared library and builds a debug HAP in a
temporary path without spaces (Hvigor truncates the current checkout path),
and copies it to `app/build/harmony/`. If the ignored file
`app/build/harmony/signing-profile.local.json5` exists, the script uses that
local DevEco signing configuration; otherwise it produces an unsigned HAP.
The script does not create signing credentials. Debug profiles permit only
their registered devices. Do not commit keys or profiles. The script currently
builds ARM64 only.

## Implemented and checked

- Rust cross-compiles to OHOS ARM64. The HAP archive contains the Rust and
  Flutter shared libraries. Rust core host unit tests pass.
- Device type is queried through an OHOS method channel. Path provider,
  preferences and file selector implementations are included and registered.
- File selection copies to the application cache without passing the file's
  contents through a Flutter platform channel. This has not been device-tested.
- By default received files stay in application storage. On PC, settings can
  select a user folder, persist its read/write URI grant, and activate it before
  each incoming session. A write probe checks the converted path when selected;
  if activation fails the incoming request is declined. Incoming file names are
  created exclusively and the same open descriptor is used by Rust for writing.
  Retries use a new numbered name and retain the previous partial file. The URI
  grant and descriptor behavior require real-device validation. The persisted
  folder grant is activated at startup as well as before incoming sessions.
- Received files can be opened through the system file viewer or exported
  from transfer progress and history via the system document save picker.
  Opening failures offer the save flow; system viewer and grants still require
  device validation. Finished OHOS receive sessions remain open even
  with quick-save or auto-finish, so files remain accessible when history is
  disabled. PC settings can remember a preferred folder as the save picker
  starting location; each export still requires user confirmation. Dismissing
  the picker leaves the original file in place; failures are shown to the user.
- Fullscreen, split and floating window modes are declared. Navigation adapts
  to the available width and height, and unsupported desktop plugins are not
  initialized on OHOS. Native window behavior still requires device testing.
- OHOS has a distinct light/dark visual theme. PC shortcuts include Ctrl+1/2/3
  to switch tabs, Ctrl+, for settings and Ctrl+V for the clipboard.
- Clipboard text, PixelMap images, files and folders use the native system
  PasteButton for temporary access. File and folder URIs are copied into an
  app-private persistent staging area; multiple entries are handled separately.
  Folder hierarchy is retained, and folders containing empty directories are
  packaged as ZIPs for extraction on the receiver. Ctrl+V opens the same dialog.
  Staging cleanup preserves active selections, sends and recovery records. On
  restart, unreferenced staged imports are cleaned after the app starts. Only
  empty old clipboard directories are removed from the mixed-use cache; old
  ZIPs and nonempty directories remain. Legacy ZIP paths are also used by
  folder picking and drag-and-drop; a recovery record identifies a source path
  but does not prove the current file is an app-owned disposable copy. Such
  files are neither migrated nor deleted automatically. An unreadable recovery record
  pauses cleanup until the user clears it. These paths need device validation.
- Interrupted send records can restore unchanged source files for a new send
  from the beginning. Interrupted ordinary receive files are not automatically
  deleted; users can inspect the recorded paths. This is not byte-level resume.
- Share Kit integration accepts shared files and text into the send selection,
  including cold-start buffering, and exposes the system share panel for
  received files. Sharing only prepares content; sending still requires the
  user's selection of a target. Both directions require device validation.
- Notification permission can be requested in settings. Incoming requests
  while the app is not resumed attempt a local notification when enabled;
  tapping it opens the app. Delivery does not keep the service alive in the
  background and depends on OS permission and process lifecycle.
- Network changes are observed through the system connection API; after a short
  debounce the app refreshes local addresses and restarts discovery. This does
  not resume interrupted transfers and still requires device testing.
- On PC, selecting a send folder copies it to an isolated application cache
  through the system picker and URI copy API before import. Empty folders use
  the same ZIP handling as folder drops. Authorization, source size limits,
  symlinks and actual picker/copy behavior require device testing.
- On supported PC freeform windows, window pinning can be enabled in settings
  and restored at startup. Pinning requires WINDOW_TOPMOST permission.
- PC settings can opt into a system status-bar icon and minimize the main
  window on title-bar close. The icon supports left-click restore and a system
  context menu; if registration fails the setting is not enabled. Registration
  changes are serialized and pending restore waits for the foreground window.
  Closing during a transfer warns if the background task or its first progress
  update is not confirmed. The icon, restoration, notification delivery, and
  background lifecycle must be verified on real devices.
- Startup settings report the system's auto-start status from API 21 and
  explain that users must change it in system settings. Third-party apps do not
  directly change this setting via the public self-status API. The system can
  terminate the app independently of its status-bar icon.
- PC file drops use Flutter-OH drag callbacks. Dropped folders use the system
  data-loading API and are imported from isolated cache directories with their
  hierarchy preserved. If a folder contains an empty directory, the app creates
  a ZIP so standard LocalSend receivers can restore the full hierarchy after
  extraction. Links are not followed. Drag delivery, folder URI grants,
  conflicts and large-file behavior still require PC tests.
- The forked Flutter enum is handled without using OHOS-only identifiers in
  common Dart code. The Dart Rust bridge is pinned to match generated bindings.

## Remaining work before claiming phone or PC support

- Sign and install on both device types, verify startup and plugin registration,
  and test discovery and bidirectional transfers with other LocalSend devices.
- Validate private and selected external receive destinations and the export
  flow on both device types, including large files, cancellation and write failures.
- Verify PC resizing, keyboard and mouse interactions, and lifecycle behavior.
  Some platform plugins are not yet supported.
  The user-selected external receive folder and export save picker still need
  real-device permission, restart, conflict and failure testing.
- Validate Share Kit discovery, file grants, cold/warm start, notification
  permission, notification delivery, tap sharing and background execution on
  phone and PC. The integrated APIs are not proof of interoperability or
  continued execution under system lifecycle and permission limits.
- `FILE_ACCESS_PERSIST` is declared for local debugging; an application-market
  release requires the platform restricted-permission application process.
- Validate network permissions, multicast, large files, cancellation, storage
  exhaustion, retries, background behavior and TLS on real devices.
- Check the system-reported device model and bundle version on both devices.

## Vendored dependencies

- `packages/harmony_plugins/path_provider_ohos`: OpenHarmony Flutter packages,
  commit `d4e49daa0acbd0bc419d58b1da27d64d44fab54b`.
- `packages/harmony_plugins/shared_preferences_ohos`: same repository, commit
  `143d83e7669a359a1ab1ee6558c4a2e4f7f4c53f`.
- `packages/harmony_plugins/file_selector_ohos`: same repository, commit
  `05111855c6772411f39d10aac43c8a276251c1d3`; locally changed to use cached
  paths instead of loading entire selected files into memory.
- `packages/flex_color_picker_ohos`: pub.dev 3.8.0 with fallback cases for
  the extra Flutter-OH target platform.
- `packages/vendor/webrtc-util`: crates.io 0.12.0 with `nix` features narrowed
  to socket and network APIs; the upstream default includes unavailable OHOS
  APIs. License files are preserved in each package.
