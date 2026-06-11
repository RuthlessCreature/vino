# 03_WORKFLOW: vino_iPhone 1.0.0

## Workflow Purpose

This workflow governs the `vino_iPhone` app icon correction iteration for target version `1.0.0`. It defines role boundaries, handoff gates, required evidence, and no-dead-angle verification expectations. Spec Owner creates only the four Spec Owner artifacts in `docs/1.0.0/`.

## Role Boundaries

| Role | May Do | Must Not Do |
|---|---|---|
| Spec Owner | Define requirements, acceptance criteria, risks, and workflow. | Modify app code, project files, assets, tests, `qa/`, `builder/`, `fix/`, or `release/`. |
| Builder | Make the smallest required icon/version/build-setting changes for `vino_iPhone`. | Touch unrelated app behavior, QA artifacts, release decisions, or other repository apps. |
| Dev Self-Check | Build and inspect Builder output; record evidence. | Claim QA pass or alter acceptance criteria. |
| QA Planner | Create test plan and test cases from this spec. | Reduce required simulator/device coverage. |
| QA Executor | Execute tests and report evidence/issues. | Modify implementation or mark skipped required tests as pass. |
| Fixer | Fix QA-reported issues only. | Change spec or QA standards to manufacture pass. |
| QA Retest | Re-run failed and key regression checks independently. | Skip required retest evidence. |
| Release Judge | Decide readiness from artifacts and evidence. | Fix implementation or rewrite results. |

## Stage Gates

| Gate | Required Inputs | Required Outputs | Pass Condition |
|---|---|---|---|
| `SPEC_READY` | User request, repository evidence | `00_SPEC.md`, `01_CHANGELOG.md`, `02_FEATURE_LIST.md`, `03_WORKFLOW.md` | Spec ends with `SPEC_READY`; all required acceptance areas are covered. |
| `BUILD_READY` | Spec artifacts | Builder implementation and `builder/DEV_NOTES.md` | Minimal scoped changes; icon source and version changes documented. |
| `DEV_SELF_CHECK_READY` | Builder output | `builder/SELF_CHECK.md`, `builder/BUILD_RESULT.md` | Static checks, builds, built plist, and compiled asset evidence recorded. |
| `QA_PLAN_READY` | Spec and self-check | `qa/QA_TEST_PLAN.md`, `qa/QA_TEST_CASES.md` | Every acceptance criterion maps to at least one test case. |
| `QA_RUN_READY` | QA plan and build artifacts | `qa/QA_TEST_RUN.md`, `qa/ISSUE_LIST.md`, `qa/REGRESSION_SUGGESTIONS.md` | Required tests executed; no `SKIPPED`/`NOT RUN` counted as pass. |
| `FIX_READY` | QA issues | `fix/FIX_REPORT.md`, `fix/ISSUE_RESOLUTION.md` | Every issue fixed or explicitly classified with rationale. |
| `QA_RETEST_READY` | Fix report | `qa/RETEST_REPORT.md` | Failed checks and key regressions rerun independently. |
| `RELEASE_DECISION_READY` | Complete evidence chain | `release/RELEASE_CHECKLIST.md`, `release/RELEASE_DECISION.md` | No open blocker; no unapproved open major; required icon coverage complete. |

## Builder Workflow

| Step | Action | Evidence Required |
|---|---|---|
| 1 | Confirm approved final icon source for `vino_iPhone`. | Source path or approval note in `builder/DEV_NOTES.md`. |
| 2 | Correct `AppHost/Assets.xcassets/AppIcon.appiconset` using single-size or complete legacy iPhone slot mode. | Diff summary and catalog mode selected. |
| 3 | Preserve `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` for Debug and Release. | Build settings excerpt. |
| 4 | Preserve display name `灵眼GX`, bundle id `cc.vino.iphone`, and iPhone-only settings. | Static plist/build settings excerpt. |
| 5 | Align `MARKETING_VERSION` to `1.0.0` for Debug and Release. | Build settings excerpt and rationale. |
| 6 | Avoid unrelated source changes. | Explicit scope statement in `builder/DEV_NOTES.md`. |

## Dev Self-Check Workflow

| Step | Required Check | Suggested Command Or Method |
|---|---|---|
| 1 | Validate icon PNG metadata. | `sips -g pixelWidth -g pixelHeight -g hasAlpha vino_iPhone/AppHost/Assets.xcassets/AppIcon.appiconset/<icon>.png` |
| 2 | Validate app icon build settings for Debug and Release. | `xcodebuild -project vino_iPhone.xcodeproj -scheme vino_iPhone -configuration Debug -showBuildSettings` and Release equivalent. |
| 3 | Clean Debug simulator build. | `xcodebuild -project vino_iPhone.xcodeproj -scheme vino_iPhone -sdk iphonesimulator -configuration Debug clean build CODE_SIGNING_ALLOWED=NO` |
| 4 | Release/generic iOS packaging check. | `xcodebuild -project vino_iPhone.xcodeproj -scheme vino_iPhone -configuration Release -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO` or signed equivalent. |
| 5 | Inspect built app plist. | `/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' <built-app>/Info.plist` and version/bundle id checks. |
| 6 | Inspect compiled asset catalog. | `xcrun assetutil --info <built-app>/Assets.car` or equivalent asset evidence. |

## QA Planning Requirements

| Area | Required Coverage |
|---|---|
| Static catalog | JSON validity, referenced-file existence, PNG metadata, no conflicting/stale entries. |
| Build integration | Debug and Release settings, resources phase, clean build logs, built app metadata. |
| Simulator | Clean install, Home Screen, App Library/Search, Settings list, App Switcher, launch sanity. |
| Physical iPhone | Signed install or equivalent, same visual surfaces as simulator, model/iOS version recorded. |
| Cache controls | DerivedData cleanup, simulator uninstall, device uninstall or controlled upgrade path. |
| Regression | Display name, bundle id, permissions, iPhone-only target, target version `1.0.0`. |

## QA Execution Workflow

| Step | Action | Pass / Fail Rule |
|---|---|---|
| 1 | Start from clean checkout or record working tree state. | Fail if implementation includes unrelated app behavior changes that prevent scoped verification. |
| 2 | Run static catalog checks. | Fail on missing file, invalid PNG, alpha issue, invalid JSON, conflicting slots, or warning-prone catalog. |
| 3 | Run clean simulator build and inspect built product. | Fail on build error, icon warning, missing `AppIcon`, wrong display name, wrong bundle id, or wrong version. |
| 4 | Install on iPhone simulator after uninstall/cache cleanup. | Fail if any required iOS surface shows wrong, blank, placeholder, or stale icon. |
| 5 | Install on physical iPhone. | Fail if device install cannot be completed, unless release explicitly accepts the external blocker. |
| 6 | Record screenshots/photos and command logs. | Fail if required evidence is absent or unverifiable. |
| 7 | Write issue list with severity and reproduction. | Fail release gate if blocker remains open or major remains unapproved. |

## Required Evidence Matrix

| Evidence | Owner | Required For Release |
|---|---|---|
| Approved icon source or approval note | Builder | Yes |
| App icon catalog JSON and PNG metadata | Builder / Dev Self-Check / QA | Yes |
| Debug and Release build setting excerpts | Dev Self-Check / QA | Yes |
| Clean simulator build log | Dev Self-Check / QA | Yes |
| Release/generic iOS or signed device build log | Dev Self-Check / QA | Yes |
| Built `Info.plist` display name, bundle id, and version evidence | Dev Self-Check / QA | Yes |
| Compiled `Assets.car` evidence | Dev Self-Check / QA | Yes |
| iPhone simulator screenshots | QA Executor | Yes |
| Physical iPhone screenshots/photos | QA Executor | Yes |
| Cache cleanup evidence | QA Executor | Yes |
| Complete `qa/ISSUE_LIST.md` | QA Executor | Yes |
| Retest report for any issue | QA Retest | Yes if issues exist; key regression retest still required otherwise. |

## Decision Rules

| Condition | Decision |
|---|---|
| All acceptance criteria pass with complete evidence | Release Judge may approve. |
| Any required test is `SKIPPED`, `NOT RUN`, or inconclusive | Do not approve release. |
| Physical iPhone test is unavailable | Do not approve release unless business explicitly accepts the gap with documented risk. |
| App icon correct on simulator but wrong on device | Do not approve release. |
| App icon correct but display name/version/device family regresses | Do not approve release. |
| Open blocker exists | Do not approve release. |
| Open major exists without explicit business acceptance | Do not approve release. |

## Handoff Notes

- The next role is Builder only after `00_SPEC.md` ends with `SPEC_READY` and the other three Spec Owner artifacts exist.
- Builder should prefer the smallest correct change and must document why the selected icon catalog mode is complete.
- QA must treat icon correctness as a visual and packaging requirement, not only a source-file requirement.
- Release readiness requires both simulator and physical iPhone evidence for target version `1.0.0`.
