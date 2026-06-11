# 02_FEATURE_LIST: vino_iPhone 1.0.0

## Feature Inventory

| Feature ID | Feature | Priority | Status | Owner | Acceptance References |
|---|---|---|---|---|---|
| APPICON-001 | Correct installed app icon artwork | P0 | Specified | Builder / QA | `AC-001`, `AC-015`, `AC-016` |
| APPICON-002 | Complete and valid `AppIcon.appiconset` | P0 | Specified | Builder / Dev Self-Check | `AC-002`, `AC-003`, `AC-004` |
| APPICON-003 | Debug and Release build integration | P0 | Specified | Builder / Dev Self-Check | `AC-005`, `AC-006`, `AC-007`, `AC-008` |
| APPICON-004 | App identity preservation | P0 | Specified | Builder / QA | `AC-009`, `AC-010` |
| APPICON-005 | iPhone-only target preservation | P0 | Specified | Builder / QA | `AC-011`, `AC-012` |
| APPICON-006 | Target version `1.0.0` consistency | P0 | Specified | Builder / Release Judge | `AC-013`, `AC-014` |
| APPICON-007 | No-dead-angle verification evidence | P0 | Specified | QA Planner / QA Executor | `AC-015`, `AC-016`, `AC-017`, `AC-018` |

## Verification Capabilities Required

| Capability ID | Capability | Required Evidence |
|---|---|---|
| VERIFY-001 | Static catalog inspection | JSON validity, referenced-file existence, no conflicting icon entries, final PNG metadata. |
| VERIFY-002 | Build settings inspection | Debug and Release `AppIcon`, `MARKETING_VERSION = 1.0.0`, iPhone-only settings. |
| VERIFY-003 | Clean simulator build | Full command, configuration, SDK/destination, log excerpt showing no icon warnings. |
| VERIFY-004 | Generic iOS or signed device build | Release/device packaging evidence using the same app icon and version settings. |
| VERIFY-005 | Built product inspection | Built `Info.plist` values and compiled asset catalog evidence. |
| VERIFY-006 | iPhone simulator visual checks | Home Screen, App Library/Search, Settings list, App Switcher, launch sanity screenshots. |
| VERIFY-007 | Physical iPhone visual checks | Device model, iOS version, install method, same visual surfaces, screenshots/photos. |
| VERIFY-008 | Cache and reinstall checks | DerivedData cleanup, simulator uninstall, device uninstall or upgrade path, retest evidence. |

## Release Blocking Rules

| Rule ID | Rule |
|---|---|
| BLOCK-001 | Any required icon check marked `SKIPPED`, `NOT RUN`, or inconclusive blocks release readiness. |
| BLOCK-002 | Any mismatch between source `Info.plist`, built plist, and expected display name `灵眼GX` blocks release readiness. |
| BLOCK-003 | Any mismatch between target version `1.0.0` and built `CFBundleShortVersionString` blocks release readiness. |
| BLOCK-004 | Simulator-only validation blocks release readiness because physical iPhone coverage is required. |
| BLOCK-005 | Device-only validation blocks release readiness because simulator coverage is required. |
| BLOCK-006 | Any broadening beyond iPhone-only target support blocks release readiness unless explicitly approved outside this iteration. |

## Out-Of-Scope Features

| Area | Reason |
|---|---|
| Runtime camera/inference/networking behavior | Icon correction must not alter app behavior. |
| Desktop/cloud components | `vino_iPhone` is the independent app in scope. |
| iPad/Mac icon support | Target remains iPhone-only. |
| App Store Connect metadata | Not needed to prove installed iPhone icon correctness. |
| Automated test implementation | Spec Owner defines requirements only. |
