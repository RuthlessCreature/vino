# Build Result: vino_iPhone 1.0.0

## Summary

| Area | Status | Result |
|---|---|---|
| Static icon catalog | PASS | `Contents.json` is valid and references 9 existing PNG files. |
| PNG metadata | PASS | All referenced icons are square, expected dimensions, and `hasAlpha: no`. |
| Build settings | PASS | Debug and Release settings preserve `AppIcon`, iPhone-only targeting, disabled Mac/Catalyst/XR support, and version `1.0.0`. |
| Debug simulator build | PASS | Required clean build exited 0. |
| Release generic iOS build | PASS | Generic iOS Release build with signing disabled exited 0; no signing blocker. |
| Built products | PASS | Debug and Release app bundles resolve expected plist identity/version and contain compiled `Assets.car`. |
| QA status | BLOCKED | Simulator and physical iPhone visual QA were not run by Dev Self-Check. |

## Commands Run

| Check | Command | Working directory | Exit code | Status |
|---|---|---|---:|---|
| Static JSON/file existence | `node` script parsing `vino_iPhone/AppHost/Assets.xcassets/AppIcon.appiconset/Contents.json` and checking referenced files | `/Users/cengcheng/Documents/GitHub/vino` | 0 | PASS |
| PNG metadata | `sips -g pixelWidth -g pixelHeight -g hasAlpha <referenced-icon-file>` for each referenced icon | `/Users/cengcheng/Documents/GitHub/vino` | 0 | PASS |
| Build settings | `xcodebuild -project vino_iPhone.xcodeproj -scheme vino_iPhone -configuration Debug -showBuildSettings -json` and Release equivalent | `/Users/cengcheng/Documents/GitHub/vino/vino_iPhone` | 0 | PASS |
| Clean Debug simulator build | `xcodebuild -project vino_iPhone.xcodeproj -scheme vino_iPhone -sdk iphonesimulator -configuration Debug clean build CODE_SIGNING_ALLOWED=NO` | `/Users/cengcheng/Documents/GitHub/vino/vino_iPhone` | 0 | PASS |
| Release generic iOS build | `xcodebuild -project vino_iPhone.xcodeproj -scheme vino_iPhone -sdk iphoneos -configuration Release -destination 'generic/platform=iOS' clean build CODE_SIGNING_ALLOWED=NO` | `/Users/cengcheng/Documents/GitHub/vino/vino_iPhone` | 0 | PASS |
| Restore Debug product for metadata inspection | `xcodebuild -project vino_iPhone.xcodeproj -scheme vino_iPhone -sdk iphonesimulator -configuration Debug build CODE_SIGNING_ALLOWED=NO` | `/Users/cengcheng/Documents/GitHub/vino/vino_iPhone` | 0 | PASS |
| Built plist inspection | `/usr/libexec/PlistBuddy -c 'Print :<key>' <built-app>/Info.plist` for required keys | `/Users/cengcheng/Documents/GitHub/vino` | 0 after retry | PASS |
| Compiled asset inspection | `xcrun assetutil --info <built-app>/Assets.car` | `/Users/cengcheng/Documents/GitHub/vino` | 0 after retry | PASS |

## Static Catalog Result

| Field | Value | Status |
|---|---|---|
| `Contents.json` | Exists and valid JSON | PASS |
| `info.version` | `1` | PASS |
| Image entries | `9` | PASS |
| Referenced files | `9` | PASS |
| Missing referenced files | `0` | PASS |

## Build Settings Result

| Configuration | `ASSETCATALOG_COMPILER_APPICON_NAME` | `MARKETING_VERSION` | `TARGETED_DEVICE_FAMILY` | `SUPPORTED_PLATFORMS` | `INFOPLIST_FILE` | Mac/Catalyst/XR flags | Status |
|---|---|---|---|---|---|---|---|
| Debug | `AppIcon` | `1.0.0` | `1` | `iphoneos iphonesimulator` | `AppHost/Info.plist` | `SUPPORTS_MACCATALYST=NO`; `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD=NO`; `SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD=NO` | PASS |
| Release | `AppIcon` | `1.0.0` | `1` | `iphoneos iphonesimulator` | `AppHost/Info.plist` | `SUPPORTS_MACCATALYST=NO`; `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD=NO`; `SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD=NO` | PASS |

## Build Output

| Build | Product | Result | Notes |
|---|---|---|---|
| Debug simulator clean build | `/Users/cengcheng/Library/Developer/Xcode/DerivedData/vino_iPhone-ckagsusjkllkwigqqnrlwkenruxt/Build/Products/Debug-iphonesimulator/灵眼GX.app` | PASS | Required command exited 0 with `** BUILD SUCCEEDED **`. |
| Release generic iOS clean build | `/Users/cengcheng/Library/Developer/Xcode/DerivedData/vino_iPhone-ckagsusjkllkwigqqnrlwkenruxt/Build/Products/Release-iphoneos/灵眼GX.app` | PASS | Required generic iOS command exited 0 with `** BUILD SUCCEEDED **`; no code-signing blocker with `CODE_SIGNING_ALLOWED=NO`. |
| Debug simulator restore build | `/Users/cengcheng/Library/Developer/Xcode/DerivedData/vino_iPhone-ckagsusjkllkwigqqnrlwkenruxt/Build/Products/Debug-iphonesimulator/灵眼GX.app` | PASS | Run after Release clean so both Debug and Release products existed for metadata inspection. |

## Build Log Notes

| Log | Evidence | Status |
|---|---|---|
| Debug clean build | `CompileAssetCatalog` ran for `AppHost/Assets.xcassets`; `actool` used `--app-icon AppIcon`, `--target-device iphone`, `--platform iphonesimulator`; output included `AppIcon60x60@2x.png`; build succeeded. | PASS |
| Release generic iOS build | `CompileAssetCatalog` ran for `AppHost/Assets.xcassets`; `actool` used `--app-icon AppIcon`, `--target-device iphone`, `--platform iphoneos`; output included `AppIcon60x60@2x.png`; build succeeded. | PASS |
| Compiler warnings | Swift warnings appeared in both Debug and Release logs: `Sources/Models/VinoAppState.swift:300:17` captured-var warning and `Sources/Auth/AuthService.swift:36:35` missing-`await` warning. | PASS with warning; not an icon/catalog/build-setting failure under current toolchain. |

## Built Info.plist Result

| Product | `CFBundleDisplayName` | `CFBundleName` | `CFBundleIdentifier` | `CFBundleShortVersionString` | `LSRequiresIPhoneOS` | Status |
|---|---|---|---|---|---|---|
| Debug simulator | `灵眼GX` | `灵眼GX` | `cc.vino.iphone` | `1.0.0` | `true` | PASS |
| Release iOS | `灵眼GX` | `灵眼GX` | `cc.vino.iphone` | `1.0.0` | `true` | PASS |

## Compiled Assets.car Result

| Product | `Assets.car` | `assetutil` | Icon entries | Status |
|---|---|---|---|---|
| Debug simulator | Exists | Exit 0 | 18 total entries; 13 icon-related entries for `AppIcon`, including all expected phone and marketing renditions. | PASS |
| Release iOS | Exists | Exit 0 | 18 total entries; 13 icon-related entries for `AppIcon`, including all expected phone and marketing renditions. | PASS |

## Failed Attempts Recorded

| Command | Exit code | Error | Classification | Final status |
|---|---:|---|---|---|
| Initial `PlistBuddy` inspection script after Release clean | 1 | Debug `Info.plist` missing because Release `clean` removed the Debug product. | Tooling/evidence sequencing blocker, not implementation failure | RESOLVED by rebuilding Debug without `clean`; final plist inspection PASS. |
| Initial `assetutil` inspection script after Release clean | 1 | Debug `Assets.car exists=false` because Release `clean` removed the Debug product. | Tooling/evidence sequencing blocker, not implementation failure | RESOLVED by rebuilding Debug without `clean`; final asset inspection PASS. |

## Remaining Blockers

| Area | Status | Reason |
|---|---|---|
| Simulator visual QA | BLOCKED | Not executed in Dev Self-Check; QA must verify Home Screen, App Library/Search, Settings list, App Switcher, launch sanity, and cache cleanup. |
| Physical iPhone QA | BLOCKED | Not executed in Dev Self-Check; QA must perform signed install or record the exact external signing/device blocker. |
| Release readiness | BLOCKED | QA Planner, QA Executor, Fixer/Retest if needed, and Release Judge artifacts are pending. |
