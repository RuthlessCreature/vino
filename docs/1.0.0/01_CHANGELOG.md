# 01_CHANGELOG: vino_iPhone 1.0.0

## Metadata

| Item | Value |
|---|---|
| Target version | `1.0.0` |
| Base version | `NEW_PROJECT` |
| Iteration goal | 修复 `vino_iPhone` icon 显示不正确的问题，并且做无死角的测试 |
| Scope | `vino_iPhone` iPhone app only |
| Artifact role | Spec Owner changelog; not implementation evidence |

## Planned Changes

| Type | Change | Acceptance Reference |
|---|---|---|
| Fixed | Correct the installed `vino_iPhone` app icon so iOS never shows a placeholder, stale icon, wrong product icon, blank image, or incorrectly processed image. | `AC-001`, `AC-015`, `AC-016` |
| Fixed | Ensure `AppIcon.appiconset` is complete and internally consistent for either current single-size iOS mode or a complete legacy iPhone slot matrix. | `AC-002`, `AC-003`, `AC-004` |
| Fixed | Ensure the `AppIcon` asset catalog is compiled into Debug and Release app products. | `AC-005`, `AC-006`, `AC-007`, `AC-008` |
| Preserved | Keep app identity unchanged: display name `灵眼GX`, bundle id `cc.vino.iphone`, manual `Info.plist`, permissions, and iPhone-only target. | `AC-009`, `AC-010`, `AC-011`, `AC-012` |
| Changed | Align target marketing version with iteration version `1.0.0` for Debug, Release, and built app metadata. | `AC-013`, `AC-014` |
| Tested | Require no-dead-angle verification across static checks, clean builds, simulator install, physical iPhone install, cache controls, and evidence review. | `AC-015`, `AC-016`, `AC-017`, `AC-018` |

## Current Baseline Observations

| Area | Observed State | Required Outcome |
|---|---|---|
| App icon catalog | `Contents.json` currently references one iOS universal `1024x1024` PNG. | Keep this mode only if the final artwork is correct and asset compiler evidence is clean; otherwise complete a valid alternate catalog. |
| PNG metadata | `AppIcon-1024.png` reports `1024x1024` with no alpha. | Final image must continue to satisfy size/alpha requirements and visual correctness. |
| Build integration | Debug and Release currently point to `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`; `Assets.xcassets` is in resources. | Preserve and prove integration for both configurations. |
| App identity | `Info.plist` contains `CFBundleDisplayName = 灵眼GX` and `CFBundleName = 灵眼GX`. | Preserve these values in source and built products. |
| Device family | Target currently uses `TARGETED_DEVICE_FAMILY = 1`. | Preserve iPhone-only targeting. |
| Version | Target currently reports `MARKETING_VERSION = 0.1.0`. | Update target delivery metadata to `1.0.0`. |

## Non-Changes

- No Spec Owner changes to application code, project settings, assets, QA implementation, Builder artifacts, Fixer artifacts, or Release artifacts.
- No intended changes to camera, inference, auth, networking, model storage, upload, permissions, or runtime UI.
- No expansion to iPad, Mac Catalyst, Mac Designed for iPhone/iPad, or XR Designed for iPhone/iPad.

## Changelog Gate

This changelog is ready for Builder handoff only when paired with `00_SPEC.md`, `02_FEATURE_LIST.md`, and `03_WORKFLOW.md` under `docs/1.0.0/`.
