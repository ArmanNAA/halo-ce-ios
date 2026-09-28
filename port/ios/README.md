# Build and install Halo: CE on iPhone and iPad

This directory builds a native ARM64 iOS app around the existing game's ILP32
runtime. It uses SDL3, OpenGL ES 3, UIKit touch controls, and the user's original
Xbox map files. The game files are separate from the application and are never
included in source control.

The Home Screen name is **Halo: CE**. The portable ILP32 runtime lives in
`port/runtime`; UIKit, Darwin, touch, audio, and the native loader live here.
The Android app, Gradle/NDK targets, Java activities, and Android host services
have been removed from this branch.

The icon adapts the user's supplied
Master Chief artwork into an opaque square; iOS applies its rounded icon mask.
The source is `Icon-Artwork.png`, with device sizes in
`Assets.xcassets/AppIcon.appiconset`. See [icon notes](ICON.md) for the prompt.

## Build

Use an Apple Silicon Mac with Xcode, its iOS SDK, Python 3, CMake, Ninja, LLVM
and LLD. The validated toolchain is Xcode 27 and Homebrew LLVM/LLD 23.1.2.
The deployment target is iOS 16, but older OS versions have not been validated.
Install dependencies using `brew install cmake ninja llvm lld sdl3 pkgconf`.
Open Xcode once to accept its license and install the iOS platform. Ensure
`xcode-select -p` points into full Xcode, not only Command Line Tools.
For signed device builds, add your Apple account in Xcode Settings > Accounts.
Your provisioning profile must cover the device and chosen bundle identifier.
See [Apple's device setup guide](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices).

From the repository root:

```sh
# Native ARM64 simulator app (no signing).
python3 tools/ios_build.py --simulator

# Device app, signed with your Apple development team.
python3 tools/ios_build.py --team YOUR_TEAM_ID --bundle-id com.yourname.haloce

# Unsigned device IPA (no Apple account needed to build).
python3 tools/ios_build.py --unsigned --ipa dist/Halo-CE-iOS-unsigned.ipa
```

The script fetches pinned Khronos headers, SDL release-3.4.16 and musl 1.2.5,
compiles the guest, embeds it into signed application text, and builds the host.
Specify `--llvm` and `--lld` for non-default toolchain locations.
Game assertions remain enabled. An Xcode `Release` host configuration does not
disable the game's assertions. PGO and LTO are disabled for this initial port.

Outputs:

- `build/ios/app-device/Release-iphoneos/HaloCE.app`
- `build/ios/app-simulator/Release-iphonesimulator/HaloCE.app`
- `build/ios/app-unsigned/Release-iphoneos/HaloCE.app`
- `dist/Halo-CE-iOS-unsigned.ipa` and its `.sha256` checksum when requested

The default bundle identifier is `org.haloce.ios`. Set `--bundle-id` to one
covered by your signing profile. `--ipa PATH` can also package a signed build;
only unsigned builds are suitable for this project's public release workflow.
Code signing and provisioning must succeed
before installation. No jailbreak, JIT entitlement, or writable executable
memory is used.

## Install and add game data

The cache validator accepts these exact Xbox v5 cache builds on iOS:

- PAL: `01.01.14.2342`
- NTSC-US: `01.10.12.2276` (experimental compatibility)

Extract the maps from your own XISO without modifying headers:

```sh
python3 tools/ios_extract_assets.py '/path/to/Halo.xiso.iso' --output assets
```

The destination files must not already exist. Extraction writes
`assets/asset-manifest.json` with original build IDs, sizes and SHA-256 hashes.
It does not patch maps or convert other Halo releases.

For source builds, list devices with `xcrun devicectl list devices`. Enable
Developer Mode when iOS requests it, pair/trust the Mac, and keep the device
unlocked during installation and copying. Replace `DEVICE_UDID` and the
example bundle identifier below with your device and the ID used for signing.

For downloaded IPAs, first sign and install through your preferred signing
tool with your own Apple account. The unsigned IPA cannot be opened directly
on iOS. Its signing/refresh requirements depend on your account and tool;
third-party signing tools have not been validated as part of this port.

Install the signed source build and copy maps **before first launch**:

```sh
xcrun devicectl device install app --device DEVICE_UDID \
  build/ios/app-device/Release-iphoneos/HaloCE.app
xcrun devicectl device copy to --device DEVICE_UDID \
  --domain-type appDataContainer --domain-identifier com.yourname.haloce \
  --source assets/maps --destination Documents/maps
xcrun devicectl device process launch --device DEVICE_UDID \
  com.yourname.haloce
```

Alternatively, use Finder's Files tab to transfer a folder named `maps` to
Halo: CE, or Files > On My iPhone/iPad > Halo: CE once its container is visible.
The app exposes its Documents folder in Files/Finder. Keep `maps` directly
inside Documents. Saved games and profiles go in `Documents/save`;
`config.toml`, `debug.txt` and `ios-runtime.log` are also available there.
A development signature has the expiration date of its provisioning profile.

## Controls

The left stick moves and the right stick aims. The four arrows navigate menus.
A selects/jumps; B returns/melees; X reloads/uses; Y changes weapons. Separate
buttons provide fire, grenade, crouch, zoom, flashlight, grenade selection,
and pause. Hold buttons for held actions. “Hide controls” leaves a small toggle
so a connected hardware controller can be used with an unobstructed picture.
The first hardware controller shares player one with the on-screen controls.
Developer console messages, frame counters, profiling text and the menu's build label are omitted
from the game picture. Diagnostic log files remain available in Documents.

Landscape is requested on both device families. An iPad held in portrait may
letterbox the landscape app; rotate the device for a larger picture.
Internet invite hosting and clipboard joining default to off on iOS. Local/network multiplayer is
not yet validated. Bink intro videos remain unsupported by the upstream port.

## How the port works

The game relies on 32-bit pointers in its data structures. Apple's current
ARM64 iOS binaries require their first 4 GB of address space to remain unmapped,
so the game's 32-bit pointers are represented as offsets into an aligned
native arena. This is native compiled code, not an Android emulator.

`tools/ios_asm_convert.py` lifts compiled guest memory accesses and indirect
branches into an aligned 4 GB arena using reserved registers x15 and x27.
Guest pointer values and structure layouts stay 32-bit. PC-relative addresses
are normalized back to guest offsets. A small signed assembly entry switches
to an arena stack; host bridges translate pointers at the ABI boundary.

Guest code is embedded in the app's signed `__TEXT` and aliased into the arena
read/execute with `vm_remap`. Guest data is separately writable. The host
translates Linux/musl calls to Darwin and handles Apple's 16 KB pages. Explicit
Xbox 4 KB read-only regions protect only complete native pages, preserving
writable neighboring buffers. Texture dirty tracking works at 16 KB granularity
and serializes protection changes against concurrent streaming writers.

The generated bridge resolves all guest imports before entering the game.
The portable runtime and assembly conversion tools were derived from the
upstream ARM64 port, with the iOS host and address model implemented here.
SDL/UIKit calls stay on the UI thread; guest workers and audio callbacks run on
arena stacks with the same translation convention.
The audio worker stages mixed PCM for the SDL callback to submit on its own
thread. This avoids taking SDL's stream lock from a worker while the callback
holds that lock and waits for the worker.

## Regression checks

```sh
brew install sdl3 pkgconf  # Native macOS SDL library for the audio regression.
python3 tools/ios_test.py
```

This executes the translated guest on signed native pages and checks 32-bit
structure layout, global/stack access, function pointers, atomic operations,
and zero-extension of addresses. A separate stress test covers concurrent
texture page tracking, fresh zeroed mappings, and the map inflater's writable
4 KB tail beside a read-only buffer.
The SDL regression checks 100 callbacks and 134,144 exact PCM samples,
including reused guest stack buffers and a request larger than 64 KB.

These tests do not replace a device campaign test. See [the validation record](VALIDATION.md)
for observed device/simulator behavior and remaining limitations.

## Simulator

Build with `--simulator`, then select and boot an ARM64 iPhone or iPad simulator
in Xcode. With exactly one simulator booted:

```sh
xcrun simctl install booted build/ios/app-simulator/Release-iphonesimulator/HaloCE.app
HALO_SIM_DATA=$(xcrun simctl get_app_container booted org.haloce.ios data)
cp -R assets/maps "$HALO_SIM_DATA/Documents/maps"
xcrun simctl launch booted org.haloce.ios
```

Use an explicit simulator ID instead of `booted` when more than one is running.
The copy command assumes `Documents/maps` does not yet exist; avoid nesting a
second `maps` directory. Simulator graphics are slow; validate performance on
a physical device.

## Troubleshooting

- **Signing fails:** check the Apple account in Xcode, team ID, unique bundle
  identifier, device registration, and profile expiration. The script permits
  Xcode provisioning updates; it never supplies somebody else's certificate.
- **App fails to launch:** confirm it was signed for your device, trust the
  developer if requested, and enable Developer Mode. An unsigned IPA will not launch.
- **Menu never appears or maps fail validation:** check `Documents/maps/ui.map`,
  confirm exact original Xbox build IDs above, and inspect `ios-runtime.log`
  and `debug.txt`. A directory named `Documents/maps/maps` is incorrect.
- **Changing your bundle ID:** iOS treats this as a separate app/container.
  Keep the same ID when updating and back up `Documents/save` before uninstalling.
- **Audio issues:** share device/OS and output route along with the runtime
  log. The regression suite checks PCM handoff; it does not test every route.
