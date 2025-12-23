# Build Guide (Device)

## Summary of Findings
- This repo generates `Telegram/Telegram.xcodeproj` via Bazel; no Xcode project exists until you run `Make.py`.
- The fork originally used relative submodule URLs for `tgcalls` and `rlottie`. They must resolve to accessible repos.
- Several build-time dependencies are git submodules; missing submodules cause Bazel failures.
- Xcode command line tools must point to full Xcode, not CommandLineTools.
- The dav1d build uses Xcode SDK paths; ensure `xcode-select` points at your Xcode.
- The generated Xcode project contains scripts that copy Bazel outputs; if the project is regenerated, those scripts may need reapplication to keep framework outputs writable.

## Prereqs
- Xcode 26.x installed.
- Xcode account signed in, device trusted and unlocked.

## Configure
1) Generate a random identifier:
```
openssl rand -hex 8
```
2) Fill `build-system/template_minimal_development_configuration.json`:
```
bundle_id: org.<hex>.Telegram
api_id: <your api_id>
api_hash: <your api_hash>
team_id: <your team id>
```

## Submodules
If you cloned a fork, ensure submodule URLs resolve:
- `submodules/rlottie/rlottie` -> `https://github.com/TelegramMessenger/rlottie.git`
- `submodules/TgVoipWebrtc/tgcalls` -> `https://github.com/TelegramMessenger/tgcalls.git`

Then sync and fetch submodules:
```
git submodule sync --recursive
git submodule update --init --recursive
```

If you want a minimal fetch:
```
git submodule update --init \
  submodules/rlottie/rlottie \
  submodules/TgVoipWebrtc/tgcalls \
  submodules/LottieCpp/lottiecpp \
  third-party/webrtc/webrtc \
  third-party/td/td \
  third-party/libvpx/libvpx \
  third-party/dav1d/dav1d
```

## Select Xcode
Make sure command line tools point to Xcode (not CommandLineTools):
```
xcode-select -p
sudo xcode-select -s /Applications/Xcode-26.2.0.app/Contents/Developer
```

## Generate the Xcode Project
```
DEVELOPER_DIR="/Applications/Xcode-26.2.0.app/Contents/Developer" \
python3 build-system/Make/Make.py \
  --cacheDir="$HOME/telegram-bazel-cache" \
  --overrideXcodeVersion \
  generateProject \
  --configurationPath=build-system/template_minimal_development_configuration.json \
  --xcodeManagedCodesigning
```

Use `--overrideXcodeVersion` if the repo's required version does not match your installed Xcode.

## Device Build (iPhone 6s)
Find the device UDID:
```
DEVELOPER_DIR="/Applications/Xcode-26.2.0.app/Contents/Developer" \
xcrun xctrace list devices
```

Build:
```
DEVELOPER_DIR="/Applications/Xcode-26.2.0.app/Contents/Developer" \
xcodebuild build \
  -project Telegram/Telegram.xcodeproj \
  -scheme Telegram \
  -configuration Debug \
  -destination "platform=iOS,id=<DEVICE_UDID>" \
  -allowProvisioningUpdates 2>&1 | xcsift -f toon
```

If you do not have `xcsift`, drop the pipe and run `xcodebuild` directly.

## Regeneration Notes
Re-running `generateProject` overwrites `Telegram/Telegram.xcodeproj`.
If you see permission errors writing framework `Info.plist` or swiftmodule files, reapply the local tweaks to:
- `Telegram/Telegram.xcodeproj/rules_xcodeproj/bazel/copy_outputs.sh`
- `Telegram/Telegram.xcodeproj/rules_xcodeproj/bazel/generate_bazel_dependencies.sh`

## Troubleshooting
- "no provisioning profile found": open Xcode, select the `Telegram` target, enable Automatic signing, choose your Team.
- "CMake compiler not found / iPhoneOS SDK missing": run `xcode-select` to point at Xcode.
- "missing input file ... third-party/...": re-run `git submodule update --init`.
