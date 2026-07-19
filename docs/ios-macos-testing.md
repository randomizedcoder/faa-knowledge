# Testing the app on iPhone / iPad (macOS)

The FAA Quiz Flutter app (`app/`) is developed on Linux with Nix for **Android + web**. iOS is
**code-supported** — the `ios/` project is scaffolded and the layout is platform-independent (it's
covered by the widget tests at iPhone/iPad sizes, incl. notch safe-areas) — but Apple only lets you
**build and run iOS on macOS with Xcode**. There is no way to do it from the Linux/Nix box.

This doc is the runbook for the Mac: run on the iOS Simulator, deploy to a real iPhone/iPad, and (later)
distribute to pilots via TestFlight.

> **Don't try to Nix the iOS build.** On macOS, use a normal Flutter + Xcode install (below). Nix-darwin
> for the Flutter/Xcode/CocoaPods toolchain is painful and unsupported here. The Nix flake in this repo is
> for the Linux Android/web workflow only.

## Project facts (as of this writing)

| | |
|---|---|
| Flutter channel/version | stable **3.41.x** (match the Linux box; `flutter --version`) |
| iOS bundle identifier | `ca.seddon.faaquiz.faaQuiz` (`app/ios/Runner.xcodeproj`) |
| Display name | **FAA Quiz** (`CFBundleDisplayName`) |
| Min iOS deployment target | **13.0** |
| Signing team | **not set** — you configure this in Xcode on the Mac |
| Plugins needing CocoaPods | `shared_preferences` (→ `shared_preferences_foundation`). `auto_size_text` is pure Dart. |
| Bundled font | Lora (`app/assets/fonts/Lora.ttf`) — verify it renders on iOS |
| Questions data | `app/assets/questions.json` (committed; no generation step needed to run) |

---

## 1. One-time Mac setup

```bash
# 1. Xcode (from the App Store), then its command-line tools + license:
xcode-select --install                 # if not already installed
sudo xcodebuild -runFirstLaunch
sudo xcodebuild -license accept

# 2. CocoaPods (Ruby gem; Homebrew alternative: `brew install cocoapods`):
sudo gem install cocoapods

# 3. Flutter (match the repo's stable channel; e.g. via the tarball or `brew install --cask flutter`):
#    https://docs.flutter.dev/get-started/install/macos
flutter channel stable
flutter upgrade                         # aim for 3.41.x to match the Linux toolchain
flutter config --enable-ios

# 4. Verify — the "iOS toolchain" and "Xcode" rows must be green:
flutter doctor -v
```

`flutter doctor` will tell you if CocoaPods, a simulator, or Xcode components are missing — fix anything
it flags before continuing.

## 2. Get the app

```bash
git clone git@github.com:randomizedcoder/faa-knowledge.git
cd faa-knowledge/app
flutter pub get
```

## 3. Run on the iOS Simulator (iPhone + iPad)

```bash
open -a Simulator                       # launch the Simulator app
# In the Simulator: File ▸ Open Simulator ▸ iOS ▸ pick an iPhone (e.g. iPhone 15)
#                   and repeat for an iPad (e.g. iPad Air / iPad Pro 11")

flutter devices                         # the booted simulator(s) should list
cd app
flutter run                             # runs on the booted simulator (first build runs `pod install`)
# or target one explicitly:
flutter run -d "iPhone 15"
flutter run -d "iPad Pro (11-inch)"
```

Hot reload with **`r`**, hot restart **`R`**, quit **`q`** — same as the Android flow.

**What to eyeball on iOS specifically** (the tests cover layout math, not these):
- **Safe areas / notch / Dynamic Island** — top of the quiz header and the bottom nav row must clear the
  notch and the home indicator. Check a notched iPhone (15/Pro) *and* an iPad.
- **Landscape** on iPad — content should be a centered column (the `MaxWidth` wrapper), not edge-to-edge.
- **The Lora serif font** renders (not a fallback), and the pastel nav-button colours look right.
- All four answer options are visible without scrolling on the smallest iPhone (SE).

## 4. Run on a real iPhone / iPad (USB)

Good for feel/performance and for the pilots' actual devices.

1. Plug the device in, unlock it, tap **Trust This Computer**.
2. Open the Xcode workspace and set a signing team:
   ```bash
   open app/ios/Runner.xcworkspace
   ```
   In Xcode: select the **Runner** target ▸ **Signing & Capabilities** ▸ tick **Automatically manage
   signing** ▸ choose your **Team** (a free Apple ID works for on-device testing; see note below). If the
   bundle id `ca.seddon.faaquiz.faaQuiz` is taken under your account, append a suffix (e.g.
   `ca.seddon.faaquiz.faaQuiz.dev`).
3. Run:
   ```bash
   cd app
   flutter run -d <your-device-name>    # `flutter devices` to get the name
   # release-mode (no debugger, closer to shipping build):
   flutter run --release -d <your-device-name>
   ```
4. First launch on the device: **Settings ▸ General ▸ VPN & Device Management ▸ trust your developer
   certificate**.

> **Free vs paid Apple ID:** a free Apple ID signs apps that run on your own devices but the provisioning
> expires after ~7 days (re-run `flutter run` to refresh). A paid **Apple Developer Program** membership
> ($99/yr) is required for a stable signing certificate and for TestFlight (below).

## 5. Distribute to pilots via TestFlight (paid Apple Developer account)

This is how real pilots test on their own iPhones/iPads without cables.

**One-time:**
1. Enroll in the **Apple Developer Program** ($99/yr).
2. In **App Store Connect** (appstoreconnect.apple.com) create a new **App** record using the bundle id
   `ca.seddon.faaquiz.faaQuiz` (or your chosen id — it must match the Xcode target).
3. In Xcode ▸ Runner ▸ Signing & Capabilities, select your paid **Team** (automatic signing).

**Each release:**
```bash
cd app
flutter build ipa                       # builds build/ios/archive + build/ios/ipa/*.ipa
```
Then upload one of two ways:
- **Xcode Organizer**: open `build/ios/archive/Runner.xcarchive` ▸ **Distribute App** ▸ **App Store
  Connect** ▸ **Upload**; or
- **Transporter** app (Mac App Store): drag in the `.ipa` from `build/ios/ipa/`.

In App Store Connect ▸ **TestFlight**: add **internal testers** (up to 100, no review) or an **external
testers** group (needs a short Beta App Review). Testers install the **TestFlight** app and accept the
invite — done. Bump `version:`/build number in `app/pubspec.yaml` for each new upload
(`flutter build ipa --build-name=1.0.0 --build-number=2`).

---

## Troubleshooting

- **`flutter doctor` says CocoaPods missing** → `sudo gem install cocoapods` (or `brew install
  cocoapods`), then `flutter doctor` again.
- **Pod install fails / stale pods** → `cd app/ios && pod repo update && pod install`, or nuke and
  regenerate: `rm -rf app/ios/Pods app/ios/Podfile.lock && cd app && flutter pub get && flutter run`.
- **"Signing for Runner requires a development team"** → set the Team in Xcode (step 4.2). Automatic
  signing needs *some* team selected, even for the simulator? No — the **Simulator doesn't need signing**;
  only real devices and archives do.
- **"Unable to find a destination" / no simulator** → boot one from the Simulator app first, or
  `xcrun simctl list devices` to see what's installed; install more via Xcode ▸ Settings ▸ Components.
- **Deployment-target errors** → the project targets iOS 13.0; make sure the selected device/simulator is
  iOS 13+ (all modern ones are).
- **App name/icon** → display name is set (`CFBundleDisplayName = FAA Quiz`); the launcher icon is the
  default Flutter icon unless replaced (`app/ios/Runner/Assets.xcassets/AppIcon.appiconset`).

## How this fits the rest of the workflow

| Platform | Where | How |
|---|---|---|
| Android (phone + tablet) | Linux + Nix | `nix run .#run-android` (+ `AVD_DEVICE=pixel_tablet` for tablet) |
| Web | Linux or Mac | `nix run .#run-web` (Linux) / `flutter run -d chrome` |
| iOS (iPhone + iPad) | **macOS + Xcode** | this doc |

The Dart/Flutter UI code is shared across all of them; only the build/run toolchain differs. Layout is
verified for iPhone/iPad **sizes** by the widget tests on Linux (`app/test/render_matrix_test.dart`), but
iOS-specific rendering (fonts, notch insets, Cupertino behaviour) can only be confirmed on a Mac/device
using this runbook.
