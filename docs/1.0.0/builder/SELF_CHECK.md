# Dev Self-Check: vino_iPhone 1.0.0

## Scope

| Item | Result |
|---|---|
| Role | Dev Self-Check |
| Repository | `/Users/cengcheng/Documents/GitHub/vino` |
| Target version | `1.0.0` |
| App target | `vino_iPhone` |
| Self-check date | 2026-06-11 |
| App code / assets / project settings modified | No |
| `qa/`, `fix/`, `release/`, acceptance criteria modified | No |
| QA pass claimed | No |

## Inputs Read

| Artifact | Status |
|---|---|
| `docs/1.0.0/00_SPEC.md` | PASS |
| `docs/1.0.0/01_CHANGELOG.md` | PASS |
| `docs/1.0.0/02_FEATURE_LIST.md` | PASS |
| `docs/1.0.0/03_WORKFLOW.md` | PASS |
| `docs/1.0.0/builder/DEV_NOTES.md` | PASS |

## Required Check Results

| Check | Status | Evidence |
|---|---|---|
| Static JSON/file existence | PASS | `Contents.json` exists, parses as valid JSON, `info.version = 1`, has 9 image entries, and all 9 referenced files exist. |
| PNG metadata with `sips` | PASS | All 9 referenced PNG files report expected square dimensions and `hasAlpha: no`. |
| Debug/Release build settings | PASS | Both configurations use `AppIcon`, `MARKETING_VERSION = 1.0.0`, `TARGETED_DEVICE_FAMILY = 1`, `SUPPORTED_PLATFORMS = iphoneos iphonesimulator`, Mac/Catalyst/XR support disabled, and `INFOPLIST_FILE = AppHost/Info.plist`. |
| Clean Debug simulator build | PASS | Required clean build command exited 0 and produced `Debug-iphonesimulator/灵眼GX.app`; build log includes `actool --app-icon AppIcon --target-device iphone --platform iphonesimulator`. |
| Release generic iOS build | PASS | Generic iOS Release build with `CODE_SIGNING_ALLOWED=NO` exited 0 and produced `Release-iphoneos/灵眼GX.app`; no signing blocker encountered. |
| Built app `Info.plist` inspection | PASS | Debug and Release built plists resolve `CFBundleDisplayName = 灵眼GX`, `CFBundleName = 灵眼GX`, `CFBundleIdentifier = cc.vino.iphone`, `CFBundleShortVersionString = 1.0.0`, `LSRequiresIPhoneOS = true`. |
| Compiled `Assets.car` inspection | PASS | `xcrun assetutil --info` succeeds for Debug and Release `Assets.car`; each product has 18 asset entries, 13 icon-related entries, and all expected `AppIcon` icon renditions. |

## Static Catalog Evidence

| Entry | Idiom | Size | Scale | File | Status |
|---|---|---|---|---|---|
| 0 | `iphone` | `20x20` | `2x` | `AppIcon-20@2x.png` | PASS |
| 1 | `iphone` | `20x20` | `3x` | `AppIcon-20@3x.png` | PASS |
| 2 | `iphone` | `29x29` | `2x` | `AppIcon-29@2x.png` | PASS |
| 3 | `iphone` | `29x29` | `3x` | `AppIcon-29@3x.png` | PASS |
| 4 | `iphone` | `40x40` | `2x` | `AppIcon-40@2x.png` | PASS |
| 5 | `iphone` | `40x40` | `3x` | `AppIcon-40@3x.png` | PASS |
| 6 | `iphone` | `60x60` | `2x` | `AppIcon-60@2x.png` | PASS |
| 7 | `iphone` | `60x60` | `3x` | `AppIcon-60@3x.png` | PASS |
| 8 | `ios-marketing` | `1024x1024` | `1x` | `AppIcon-1024.png` | PASS |

## PNG Metadata Evidence

| File | `pixelWidth` | `pixelHeight` | `hasAlpha` | Status |
|---|---:|---:|---|---|
| `AppIcon-20@2x.png` | 40 | 40 | no | PASS |
| `AppIcon-20@3x.png` | 60 | 60 | no | PASS |
| `AppIcon-29@2x.png` | 58 | 58 | no | PASS |
| `AppIcon-29@3x.png` | 87 | 87 | no | PASS |
| `AppIcon-40@2x.png` | 80 | 80 | no | PASS |
| `AppIcon-40@3x.png` | 120 | 120 | no | PASS |
| `AppIcon-60@2x.png` | 120 | 120 | no | PASS |
| `AppIcon-60@3x.png` | 180 | 180 | no | PASS |
| `AppIcon-1024.png` | 1024 | 1024 | no | PASS |

## Build Settings Evidence

| Setting | Debug | Release | Status |
|---|---|---|---|
| `ASSETCATALOG_COMPILER_APPICON_NAME` | `AppIcon` | `AppIcon` | PASS |
| `MARKETING_VERSION` | `1.0.0` | `1.0.0` | PASS |
| `TARGETED_DEVICE_FAMILY` | `1` | `1` | PASS |
| `SUPPORTED_PLATFORMS` | `iphoneos iphonesimulator` | `iphoneos iphonesimulator` | PASS |
| `INFOPLIST_FILE` | `AppHost/Info.plist` | `AppHost/Info.plist` | PASS |
| `SUPPORTS_MACCATALYST` | `NO` | `NO` | PASS |
| `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD` | `NO` | `NO` | PASS |
| `SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD` | `NO` | `NO` | PASS |
| `DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER` | `NO` | `NO` | PASS |

## Built Product Evidence

| Product | Path | Status |
|---|---|---|
| Debug simulator app | `/Users/cengcheng/Library/Developer/Xcode/DerivedData/vino_iPhone-ckagsusjkllkwigqqnrlwkenruxt/Build/Products/Debug-iphonesimulator/灵眼GX.app` | PASS |
| Release iOS app | `/Users/cengcheng/Library/Developer/Xcode/DerivedData/vino_iPhone-ckagsusjkllkwigqqnrlwkenruxt/Build/Products/Release-iphoneos/灵眼GX.app` | PASS |

| Product | `CFBundleDisplayName` | `CFBundleName` | `CFBundleIdentifier` | `CFBundleShortVersionString` | `LSRequiresIPhoneOS` | Status |
|---|---|---|---|---|---|---|
| Debug simulator | `灵眼GX` | `灵眼GX` | `cc.vino.iphone` | `1.0.0` | `true` | PASS |
| Release iOS | `灵眼GX` | `灵眼GX` | `cc.vino.iphone` | `1.0.0` | `true` | PASS |

## Compiled Asset Evidence

| Product | `Assets.car` | `assetutil` result | Icon evidence | Status |
|---|---|---|---|---|
| Debug simulator | Exists | Exit 0 | 18 entries total; 13 icon-related; `AppIcon` includes marketing 1024, phone 40/58/60/80/87/120/180 renditions and multi-sized entries. | PASS |
| Release iOS | Exists | Exit 0 | 18 entries total; 13 icon-related; `AppIcon` includes marketing 1024, phone 40/58/60/80/87/120/180 renditions and multi-sized entries. | PASS |

## Command Failures And Blockers

| Attempt | Status | Exit code | Relevant error | Classification | Resolution |
|---|---|---:|---|---|---|
| Initial built plist inspection after Release clean | BLOCKED | 1 | Debug `Info.plist` path no longer existed because the Release clean build removed the prior Debug product. | Tooling/evidence sequencing, not implementation failure | Ran Debug simulator build without `clean` to restore the product, then plist inspection passed for Debug and Release. |
| Initial `Assets.car` inspection after Release clean | BLOCKED | 1 | Debug `Assets.car exists=false` because the Release clean build removed the prior Debug product. | Tooling/evidence sequencing, not implementation failure | Ran Debug simulator build without `clean` to restore the product, then `assetutil` inspection passed for Debug and Release. |

## Warnings And Risks

| Item | Status | Notes |
|---|---|---|
| Icon/catalog warnings | PASS | Build logs show `actool` compilation for `AppIcon`; no icon-specific warning or error was found in the captured checks. |
| Swift 6 language-mode warnings | PASS with warning | Builds succeed, but logs contain existing Swift warnings in `Sources/Models/VinoAppState.swift:300:17` and `Sources/Auth/AuthService.swift:36:35`. These are not icon implementation failures, but should be tracked outside this icon-only self-check scope. |
| Simulator visual icon checks | BLOCKED for QA | Dev Self-Check did not install or visually inspect Home Screen, Search/App Library, Settings, or App Switcher. QA must execute these. |
| Physical iPhone visual checks | BLOCKED for QA | Dev Self-Check did not perform signed physical-device install or screenshots/photos. QA/release cannot treat device coverage as passed. |

## Dev Self-Check Decision

| Gate | Status | Rationale |
|---|---|---|
| Static implementation evidence | PASS | Catalog JSON, referenced files, PNG metadata, build settings, builds, built plists, and compiled assets match the Spec Owner requirements for Dev Self-Check. |
| QA readiness | PASS | Evidence is complete enough for QA Planner to create no-dead-angle simulator and physical iPhone test coverage. |
| Release readiness | BLOCKED | QA execution, simulator visual evidence, physical iPhone evidence, issue list, retest, and release decision are still pending and cannot be marked pass by Dev Self-Check. |

DEV_SELF_CHECK_READY
