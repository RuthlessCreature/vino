# QA Test Run: vino_iPhone 1.0.0

## 1. Execution Summary

| Item | Result |
|---|---|
| Role | QA Executor |
| Target version | `1.0.0` |
| App target | `vino_iPhone` |
| Bundle id | `cc.vino.iphone` |
| Execution date | 2026-06-11 |
| macOS / Xcode | macOS `14.6`, Xcode `16.2` |
| QA evidence root | `docs/1.0.0/qa/evidence/` |
| Total planned test cases | 23 |
| PASS | 16 |
| FAIL | 0 |
| BLOCKED | 7 |
| Open Blocker issues | 2 |
| QA release readiness | BLOCKED |

## 2. Evidence Package

| Evidence Area | Path | Result |
|---|---|---|
| Environment | `docs/1.0.0/qa/evidence/logs/environment.txt` | PASS |
| Changed-file scope | `docs/1.0.0/qa/evidence/logs/git_status_short.txt`, `docs/1.0.0/qa/evidence/logs/git_diff_name_status.txt` | PASS |
| Static catalog | `docs/1.0.0/qa/evidence/logs/static_catalog_check.txt` | PASS |
| PNG metadata | `docs/1.0.0/qa/evidence/logs/png_metadata_check.txt` | PASS |
| Build settings | `docs/1.0.0/qa/evidence/logs/build_settings_check.txt` | PASS |
| Debug simulator build | `docs/1.0.0/qa/evidence/logs/debug_simulator_build.log` | PASS |
| Release generic iOS build | `docs/1.0.0/qa/evidence/logs/release_generic_ios_build.log` | PASS |
| Built plist | `docs/1.0.0/qa/evidence/logs/plist_check.txt` | PASS |
| Compiled assets | `docs/1.0.0/qa/evidence/logs/assetutil_unthinned_check.txt` | PASS |
| Simulator install/launch | `docs/1.0.0/qa/evidence/logs/simulator_install_launch.txt` | BLOCKED |
| Device availability | `docs/1.0.0/qa/evidence/logs/xctrace_devices.txt`, `docs/1.0.0/qa/evidence/logs/devicectl_devices.txt` | BLOCKED |
| Generated build caches | Removed after log capture | Repository evidence keeps logs/screenshots and omits Xcode DerivedData binaries. |

## 3. Test Case Results

| TC | Title | Result | Evidence / Notes | Issues |
|---|---|---|---|---|
| TC-001 | Changed-file scope and approved icon source guard | PASS | Changed files are limited to `vino_iPhone` AppIcon assets, project version setting, and iteration docs; Builder identified existing `AppIcon-1024.png` as source. | None |
| TC-002 | Static `Contents.json` validity and referenced-file existence | PASS | JSON parsed, `info.version = 1`, 9 entries, all referenced files exist, no path escape, no unreferenced PNGs. | None |
| TC-003 | PNG metadata, alpha, readability, and visual source sanity | PASS | All 9 PNGs are square, expected pixel dimensions, readable, and `hasAlpha: no`; installed visual proof remains covered by TC-011/TC-013. | None |
| TC-004 | Icon catalog mode and slot matrix completeness | PASS | Legacy iPhone slot matrix plus `ios-marketing` is complete with no duplicate conflicting slot. | None |
| TC-005 | Debug/Release build settings for icon, version, and device support | PASS | Debug and Release use `AppIcon`, `MARKETING_VERSION = 1.0.0`, `TARGETED_DEVICE_FAMILY = 1`, and Mac/Catalyst/XR flags remain disabled. | None |
| TC-006 | Asset catalog resource integration and wrong-target guard | PASS | Build evidence targets `vino_iPhone`, bundle id `cc.vino.iphone`, and compiles `AppHost/Assets.xcassets` with `--app-icon AppIcon`. | None |
| TC-007 | DerivedData cleanup and clean Debug simulator build | PASS | QA used isolated DerivedData under `qa/evidence/derived-data`; Debug simulator clean build succeeded. | None |
| TC-008 | Release generic iOS build packaging check | PASS | Release generic iOS build with signing disabled succeeded and compiled `AppIcon` for `iphoneos`. | None |
| TC-009 | Source and built `Info.plist` identity/version/permission regression | PASS | Source, Debug, and Release plist values preserve `灵眼GX`, `cc.vino.iphone`, required permissions, and version `1.0.0`. | None |
| TC-010 | Compiled `Assets.car` icon evidence | PASS | Unthinned Debug simulator asset catalog contains all expected 2x/3x/marketing icon entries; Release `Assets.car` also contains expected entries. | None |
| TC-011 | iPhone simulator clean install visual surfaces and launch sanity | BLOCKED | Dedicated `QA-vino-iPhone-1.0.0` simulator was created, app installed, launched, and screenshots captured, but App Library/Search and App Switcher surfaces were not conclusively proven from command-only evidence. | ISSUE-001 |
| TC-012 | Simulator stale icon cache boundary | BLOCKED | Simulator uninstall/reinstall and relaunch were executed, but final icon-cache judgment depends on the incomplete simulator visual-surface review from TC-011. | ISSUE-001 |
| TC-013 | Physical iPhone install visual surfaces and launch sanity | BLOCKED | Physical iPhones listed by tooling are unavailable; no signed physical-device install or photos/screenshots were produced. | ISSUE-002 |
| TC-014 | Physical device availability and signing/install blocker handling | BLOCKED | `devicectl` reports all iPhone devices unavailable; physical-device coverage cannot be counted as pass. | ISSUE-002 |
| TC-015 | Device uninstall/reinstall or controlled upgrade cache boundary | BLOCKED | Simulator reinstall path was attempted; required physical iPhone uninstall/reinstall or upgrade path was not executable. | ISSUE-001, ISSUE-002 |
| TC-016 | Missing icon reference negative case | PASS | Every `images[].filename` exists in the app icon set, no case/path mismatch observed, no unreferenced PNGs remain. | None |
| TC-017 | Documentation and delivered version consistency | PASS | Stale `0.1.0` mentions are baseline/history or negative examples only; delivered build metadata and target evidence use `1.0.0`. | None |
| TC-018 | Simulator-only coverage release gate | BLOCKED | Simulator coverage cannot satisfy required physical iPhone coverage; release remains blocked by ISSUE-002. | ISSUE-002 |
| TC-019 | Debug/Release mismatch negative case | PASS | Debug and Release build settings, plist version, and asset packaging are consistent for the required fields. | None |
| TC-020 | Wrong app target negative case | PASS | Commands and products reference `vino_iPhone.xcodeproj`, scheme `vino_iPhone`, app `灵眼GX.app`, and bundle id `cc.vino.iphone`. | None |
| TC-021 | Identity, permissions, iPhone-only, and version regression sweep | PASS | Display name, bundle id, permissions, Bonjour/local-network keys, portrait orientation, iPhone-only targeting, and `1.0.0` version are preserved. | None |
| TC-022 | Stale DerivedData boundary | PASS | QA used isolated DerivedData paths during execution; generated build caches were removed after logs/screenshots were captured to avoid committing Xcode build outputs. | None |
| TC-023 | QA completion and issue gate review | BLOCKED | Two required coverage blockers remain open: simulator visual surface proof and physical iPhone install/visual proof. | ISSUE-001, ISSUE-002 |

## 4. Build And Packaging Results

| Check | Result | Evidence |
|---|---|---|
| Static icon catalog | PASS | `Contents.json` has 8 iPhone slots plus `ios-marketing`, all files present, no unreferenced PNGs. |
| PNG dimensions and alpha | PASS | `20@2x=40`, `20@3x=60`, `29@2x=58`, `29@3x=87`, `40@2x=80`, `40@3x=120`, `60@2x=120`, `60@3x=180`, marketing `1024`, all no alpha. |
| Debug build settings | PASS | `AppIcon`, `MARKETING_VERSION = 1.0.0`, `TARGETED_DEVICE_FAMILY = 1`. |
| Release build settings | PASS | Same as Debug for required icon/version/device fields. |
| Debug simulator clean build | PASS | Isolated DerivedData build succeeded. |
| Release generic iOS build | PASS | Generic iOS Release build succeeded with `CODE_SIGNING_ALLOWED=NO`. |
| Built plist | PASS | Debug and Release resolve `CFBundleDisplayName = 灵眼GX`, bundle id `cc.vino.iphone`, version `1.0.0`. |
| Compiled assets | PASS | Unthinned Debug and Release `Assets.car` evidence contains expected AppIcon renditions. |

## 5. Simulator Execution Notes

| Item | Result |
|---|---|
| Simulator policy | No booted iPhone existed; QA created disposable simulator `QA-vino-iPhone-1.0.0` without erasing user simulators. |
| Simulator UDID | `B2A8DF6D-0A29-4509-BE25-2E7C43EFDFD1` |
| Simulator runtime | iOS `18.3.1` |
| Install | `xcrun simctl install` exited 0. |
| Launch | `xcrun simctl launch cc.vino.iphone` exited 0 after camera permission was granted. |
| Screenshots captured | `simulator_home_pregranted.png`, `simulator_launch_pregranted.png`, `simulator_settings_clean.png`, `simulator_app_prefs_url_clean.png`, plus earlier exploratory screenshots. |
| Visual gate | BLOCKED because command-only evidence did not conclusively prove App Library/Search and App Switcher icon surfaces. |

## 6. Device Execution Notes

| Item | Result |
|---|---|
| `xcrun xctrace list devices` | Multiple iPhones appear under offline devices; no usable physical iPhone install target was verified. |
| `xcrun devicectl list devices` | Listed iPhone devices are `unavailable`. |
| Physical install | BLOCKED. |
| Physical screenshots/photos | BLOCKED. |
| Release impact | BLOCKED by required physical iPhone coverage gap. |

## 7. QA Decision

| Gate | Result | Rationale |
|---|---|---|
| Static/build/package QA | PASS | Source catalog, images, build settings, clean builds, plist, and compiled asset checks passed independently. |
| Simulator visual QA | BLOCKED | Install/launch and screenshots exist, but required visual surfaces are not fully proven. |
| Physical iPhone QA | BLOCKED | No available physical iPhone install target or device visual evidence. |
| QA_RUN_READY | READY_WITH_OPEN_BLOCKERS | Execution artifacts and issue list are complete enough for Fixer/Release Judge, but release cannot pass. |

QA_RUN_READY
