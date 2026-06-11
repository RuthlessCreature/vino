# QA Test Plan: vino_iPhone 1.0.0

## 1. Role And Scope

This document is a QA planning artifact only. It defines independent QA coverage for the `vino_iPhone` app icon correction in target version `1.0.0` and does not record execution results.

QA must not modify code, assets, Xcode project settings, builder artifacts, fix artifacts, release artifacts, or acceptance criteria. Negative and boundary coverage must be verified by inspection and execution against the delivered package, not by injecting faults into the repository.

## 2. Inputs Reviewed

| Input | Use In Plan |
|---|---|
| `docs/1.0.0/00_SPEC.md` | Acceptance criteria, roles, required simulator/device/cache/build coverage. |
| `docs/1.0.0/01_CHANGELOG.md` | Planned change areas and target version expectations. |
| `docs/1.0.0/02_FEATURE_LIST.md` | Verification capabilities and release blocking rules. |
| `docs/1.0.0/03_WORKFLOW.md` | Gate definitions and QA evidence requirements. |
| `docs/1.0.0/builder/DEV_NOTES.md` | Builder-declared changed files, selected legacy iPhone icon slot mode, source assumptions. |
| `docs/1.0.0/builder/SELF_CHECK.md` | Dev self-check evidence and remaining QA blockers. |
| `docs/1.0.0/builder/BUILD_RESULT.md` | Build result evidence and remaining simulator/device QA blockers. |
| `git status --short` / `git diff --name-status` | Changed-file summary only. |

## 3. Changed-File Summary For QA Scoping

| Area | Changed Files Observed | QA Implication |
|---|---|---|
| App icon catalog | `vino_iPhone/AppHost/Assets.xcassets/AppIcon.appiconset/Contents.json` | Verify legacy iPhone slot matrix, referenced files, no missing/stale/conflicting entries. |
| App icon PNGs | `AppIcon-20@2x.png`, `AppIcon-20@3x.png`, `AppIcon-29@2x.png`, `AppIcon-29@3x.png`, `AppIcon-40@2x.png`, `AppIcon-40@3x.png`, `AppIcon-60@2x.png`, `AppIcon-60@3x.png` | Verify exact dimensions, square shape, readability, no alpha, and visual consistency with approved 1024 source. |
| Project settings | `vino_iPhone/vino_iPhone.xcodeproj/project.pbxproj` | Verify only required icon/version/build-setting changes and no target identity/device-family regression. |
| Documentation | `docs/1.0.0/` | QA artifacts are planning/execution evidence only; release artifacts remain pending. |

No staged changes were reported in the changed-file summary.

## 4. Test Strategy

| Layer | Purpose | Required Coverage |
|---|---|---|
| Static catalog | Prove source icon catalog is internally valid before build. | JSON validity, `info.version = 1`, referenced-file existence, selected icon mode, missing reference boundary, stale/conflicting entry boundary. |
| PNG metadata | Prove source image files are valid iOS icon inputs. | Expected dimensions for every slot, square shape, readable PNGs, no alpha, wrong dimensions/alpha boundary. |
| Build settings | Prove the correct target and both configurations use the icon/version/device settings. | Debug and Release `AppIcon`, `MARKETING_VERSION = 1.0.0`, `TARGETED_DEVICE_FAMILY = 1`, supported platforms, Mac/Catalyst/XR disabled, wrong target boundary. |
| Clean builds | Prove packaging works without stale build state. | DerivedData cleanup, clean Debug simulator build, Release generic iOS build, no AppIcon/asset/Info.plist warnings. |
| Built product | Prove compiled artifacts match source expectations. | Built `Info.plist`, compiled `Assets.car`, Debug/Release parity, display name, bundle id, permissions, iPhone-only, version. |
| Simulator visual | Prove installed icon appears correctly on iPhone simulator surfaces. | Uninstall/reinstall, Home Screen, App Library/Search, Settings list, App Switcher, launch sanity, stale icon cache boundary. |
| Physical iPhone visual | Prove installed icon appears correctly on real iPhone. | Signed install or equivalent, uninstall/reinstall or first install, same visual surfaces, model/iOS/install method evidence. |
| Release gate review | Prove no required coverage is missing. | Simulator-only coverage boundary, physical-device blocker handling, skipped/inconclusive test issue handling. |

## 5. Environment Requirements

| Environment | Requirement |
|---|---|
| macOS/Xcode host | Record macOS version, Xcode version, selected toolchain, and repository path. |
| iPhone simulator | Use at least one iPhone simulator destination; record model, runtime, UDID, and install method. iPad or Mac destinations do not satisfy required simulator coverage. |
| Physical iPhone | Required. Record device model, iOS version, UDID or redacted identifier, signing/install method, and screenshots/photos. If unavailable, QA must create a QA issue; it cannot be treated as a pass or waived by QA. |
| DerivedData/cache | Clean or isolate DerivedData before required build checks; uninstall app before clean install checks. |

## 6. Entry Criteria

| Entry Item | Required Before Execution |
|---|---|
| Spec artifacts | `00_SPEC.md` ends with `SPEC_READY`; related changelog, feature list, and workflow exist. |
| Builder artifacts | `builder/DEV_NOTES.md` identifies the icon source, selected catalog mode, changed files, and version-setting change. |
| Dev self-check artifacts | `builder/SELF_CHECK.md` and `builder/BUILD_RESULT.md` exist and do not claim QA execution. |
| Install capability | Simulator is available; physical iPhone and signing path are available or the blocker can be recorded as a QA issue. |

## 7. Required Evidence From QA Execution

| Evidence | Required Content |
|---|---|
| Static logs | JSON parse result, referenced files, PNG metadata, selected catalog mode, stale/conflicting entry review. |
| Build-setting logs | Debug and Release excerpts for icon name, version, device family, supported platforms, Mac/Catalyst/XR flags, bundle id source. |
| Build logs | Clean Debug simulator build and Release generic iOS/device build command, destination, exit code, and warning review. |
| Built product logs | Built `Info.plist` values and `Assets.car` `assetutil` evidence for Debug and Release. |
| Simulator evidence | Screenshots for Home Screen, App Library/Search, Settings list, App Switcher, plus launch sanity evidence after uninstall/reinstall. |
| Physical iPhone evidence | Photos/screenshots for the same surfaces, install log, device model, iOS version, and cache/uninstall method. |
| Issue evidence | Any missing, skipped, inconclusive, or blocked required check must become a QA issue with severity and reproduction/blocker details. |

## 8. Acceptance Criteria Mapping

| AC ID | Test Case Coverage |
|---|---|
| `AC-001` | `TC-001`, `TC-003`, `TC-011`, `TC-012`, `TC-013`, `TC-015` |
| `AC-002` | `TC-002`, `TC-016` |
| `AC-003` | `TC-003`, `TC-004`, `TC-007` |
| `AC-004` | `TC-004`, `TC-007` |
| `AC-005` | `TC-005`, `TC-019` |
| `AC-006` | `TC-006`, `TC-010`, `TC-020` |
| `AC-007` | `TC-007`, `TC-022` |
| `AC-008` | `TC-008`, `TC-019` |
| `AC-009` | `TC-009`, `TC-021` |
| `AC-010` | `TC-009`, `TC-021` |
| `AC-011` | `TC-005`, `TC-021` |
| `AC-012` | `TC-011`, `TC-013`, `TC-014`, `TC-018` |
| `AC-013` | `TC-005`, `TC-009`, `TC-019`, `TC-021` |
| `AC-014` | `TC-017`, `TC-023` |
| `AC-015` | `TC-011`, `TC-012`, `TC-015` |
| `AC-016` | `TC-013`, `TC-014`, `TC-015` |
| `AC-017` | `TC-007`, `TC-012`, `TC-015`, `TC-022` |
| `AC-018` | `TC-014`, `TC-018`, `TC-023` |

## 9. Negative And Boundary Coverage

| Risk / Boundary | Planned Detection |
|---|---|
| Missing icon reference | `TC-002` verifies every `Contents.json` filename exists in the same app icon set and no empty filename is used for required slots. |
| Wrong dimensions or alpha | `TC-003` verifies every referenced PNG has exact expected pixel dimensions, is square, readable, and has no alpha. |
| Single-size vs legacy mode ambiguity | `TC-004` verifies the selected mode is internally complete and not a mixed partial catalog. |
| Debug/Release mismatch | `TC-005`, `TC-008`, `TC-009`, and `TC-019` compare both configurations and built products. |
| Stale icon cache | `TC-012` and `TC-015` require uninstall/reinstall and cache-control evidence before visual judgment. |
| Wrong app target | `TC-001`, `TC-006`, and `TC-020` verify `vino_iPhone` scheme/target/path/bundle id and reject evidence from other apps. |
| Simulator-only coverage | `TC-018` blocks release readiness if physical iPhone evidence is absent. |
| Physical-device blocker | `TC-014` requires a QA issue for unavailable device/signing/install, not a pass. |
| Stale DerivedData | `TC-007` and `TC-022` require clean or isolated DerivedData before build evidence. |

## 10. Issue Severity Guidance

| Severity | Use When |
|---|---|
| Blocker | Wrong/blank/stale app icon on any required surface, physical iPhone unavailable, build cannot prove required packaging, missing required QA evidence, or required check is skipped/inconclusive. |
| Major | Identity/version/device-family regression, Debug/Release mismatch, asset warnings, missing non-visual but required metadata evidence. |
| Minor | Evidence formatting issue that does not obscure the result and can be corrected without rerunning required coverage. |

## 11. Execution Rules

| Rule | Requirement |
|---|---|
| No result claims in plan | QA results must be recorded later in execution artifacts, not in this plan or cases. |
| No skipped pass | A required check that is skipped, unavailable, inconclusive, or blocked must be listed as a QA issue. |
| Physical iPhone required | QA cannot substitute simulator, iPad, Mac, screenshots from builder, or self-check evidence for physical iPhone coverage. |
| Evidence before release | Release Judge must receive command logs, screenshots/photos, issue list, and retest evidence if issues are found. |

QA_PLAN_READY
