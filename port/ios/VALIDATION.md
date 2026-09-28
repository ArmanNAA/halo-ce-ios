# iOS validation

Initial validation: 2026-09-28. These observations apply to the initial iOS
runtime based on upstream `16514a13`. Automated build results for later commits
are visible in [GitHub Actions](https://github.com/NicholasDominici/halo-ce-ios/actions/workflows/ios.yml).

## Observed coverage

| Surface | Result |
| --- | --- |
| iPhone 17 Pro Max, A19 Pro | Installed and launched; player confirmed gameplay and audible sound |
| Original NTSC-US Xbox maps, `01.10.12.2276` | Menu and first campaign map (`a10`) loaded; source maps unmodified |
| ARM64 iPhone simulator, iOS 27 | Menu, landscape layout, touch controls, icon, and removal of debug overlays checked |
| ARM64 iPad Pro 13-inch (M5) simulator, iOS 26 | Menu and `a10` opening scene rendered; software rendering slow |
| Existing saved data after an app update | Player profile and campaign save remained present |
| Physical iPad | Not tested |

The final name/icon/overlay update was installed on the phone and visually
checked in the simulator. Physical gameplay and sound were confirmed on the
preceding runtime build. A simulator result does not establish physical iPad
compatibility, and a deployment target does not establish older-device coverage.

## Local toolchain

Apple Silicon Mac; Xcode 27 with iOS 27 SDK; Homebrew LLVM/LLD 23.1.2;
SDL 3.4.16; musl 1.2.5. iOS deployment target 16.0. PGO and LTO are disabled;
game assertions stay enabled. All guest imports resolved at startup.
The app executes signed native code without JIT or writable executable pages.

## Reproduce automated checks

```sh
brew install cmake ninja llvm lld sdl3 pkgconf
python3 tools/ios_test.py
python3 tools/ios_build.py --unsigned --ipa dist/Halo-CE-iOS-unsigned.ipa
python3 tools/ios_build.py --simulator
```

The regression suite passes locally and covers:

1. ILP32 layout, global and stack memory, indirect calls, atomics, and pointer
   zero-extension while running the translated guest from native signed pages.
2. Concurrent texture page tracking, fresh zeroed mappings, and preservation
   of a writable 4 KB tail beside read-only data on Apple's 16 KB pages.
3. 100 real SDL callbacks and 134,144 exact PCM samples, including reused guest
   buffers and growth beyond 64 KB. The original cross-thread SDL stream
   submission deadlocked this test; the iOS handoff submits on the callback thread.

4. Fifteen XISO importer tests under AddressSanitizer/UndefinedBehaviorSanitizer:
   exact byte copies, PAL/NTSC headers, whole-disc offsets, invalid/truncated
   images, missing maps, unsafe/duplicate names, directory cycles, mixed builds,
   cancellation/retry, existing destination preservation, and seeded corruption.

## In-app XISO import (build 4)

The iPhone and iPad simulators imported a real NTSC-US XISO directly from the
app's Documents folder, then reached the Halo menu with active audio output.
All 24 extracted maps matched the original maps byte for byte (SHA-256), the save
sentinel remained intact, and temporary import directories were removed.
A local XCUITest also selected the real XISO through the native Files picker
and verified that game controls appeared after import. Another selected an
invalid image, checked the error, then selected the real image and reached the
game without restarting the app. A simulated interruption between backing up
and replacing maps recovered the originals on relaunch; valid maps skipped
extraction on subsequent launches. The iOS Xcode target explicitly enables ARC, and the importer rejects compilation
without it so asynchronous error strings remain valid.

The importer itself has not yet been exercised on a physical device or with
an iCloud-hosted image. Parser cancellation is covered automatically; UI
cancellation and cloud-provider download behavior still need device testing.

CI runs these probes and compiles device and simulator apps without game data.
It does **not** play the game or validate a personal provisioning profile.
Its packaged IPA is unsigned and must be signed before installation.
The Android cleanup relocates the retained portable runtime, removes Android
services/build targets, and uses a bare-metal ELF assembler target before
embedding the compiled code into the iOS app.

## Still unverified

Physical iPad gameplay, older iPhones/iOS versions, a complete campaign,
physical controllers, network multiplayer, audio route changes/headphones,
and prolonged background/resume behavior. PAL maps are accepted by the cache
validator but have not been played on iOS. Bink intro videos are unsupported.
