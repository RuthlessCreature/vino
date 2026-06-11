# 00_SPEC: vino_iPhone App Icon Correction 1.0.0

## 1. Iteration Goal

修复 `vino_iPhone` icon 显示不正确的问题，并且做无死角的测试。

## 2. Iteration Context

| Item | Value |
|---|---|
| Repository | `/Users/cengcheng/Documents/GitHub/vino` |
| App scope | `vino_iPhone` independent iPhone app |
| Target version | `1.0.0` |
| Base version | `NEW_PROJECT` |
| Spec role | Spec Owner only |
| Current app target | `vino_iPhone` |
| Current bundle id | `cc.vino.iphone` |
| Current display name | `灵眼GX` |
| Current app icon set | `AppHost/Assets.xcassets/AppIcon.appiconset` |

## 3. Evidence Checked

| File | Relevant evidence |
|---|---|
| `vino_iPhone/README.md` | Project is opened through `vino_iPhone/vino_iPhone.xcodeproj`; shared scheme is `vino_iPhone`; existing simulator build command is documented. |
| `vino_iPhone/vino_iPhone.xcodeproj/project.pbxproj` | `Assets.xcassets` is in resources; Debug and Release use `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`; target is iPhone-only with `TARGETED_DEVICE_FAMILY = 1`; `MARKETING_VERSION` is currently `0.1.0`. |
| `vino_iPhone/AppHost/Info.plist` | `CFBundleDisplayName` and `CFBundleName` are both `灵眼GX`; version fields are build-setting backed; `LSRequiresIPhoneOS` is true. |
| `vino_iPhone/AppHost/Assets.xcassets/AppIcon.appiconset/Contents.json` | Current catalog contains one iOS universal `1024x1024` app icon entry referencing `AppIcon-1024.png`. |
| `vino_iPhone/AppHost/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` | Current PNG metadata reports `1024x1024` and no alpha. |

## 4. Scope

- Correct the `vino_iPhone` application icon as displayed by iOS and by compiled app bundles.
- Keep the app target independent from other repository components.
- Verify the icon asset catalog is complete, valid, and compiled into Debug and Release builds.
- Preserve `Info.plist` identity fields, especially `CFBundleDisplayName = 灵眼GX` and `CFBundleName = 灵眼GX`.
- Preserve iPhone-only targeting and explicitly verify no iPad, Mac Catalyst, Mac Designed for iPhone/iPad, or XR Designed for iPhone/iPad behavior is introduced.
- Align the `vino_iPhone` target version to `1.0.0` consistently for Debug, Release, built `Info.plist`, and release documentation.
- Define complete downstream verification expectations for static checks, build checks, simulator checks, and physical iPhone checks.

## 5. Out of Scope

- No Spec Owner modification to application code, Xcode project files, asset files, `qa/`, `builder/`, `fix/`, or `release/`.
- No test implementation in this phase.
- No redesign of app UI, camera, inference, networking, model, auth, or upload behavior.
- No desktop, cloud, protocol, or non-iPhone app changes.
- No App Store Connect metadata, screenshots, marketing copy, or provisioning-profile management unless needed only to install on a physical iPhone for QA.
- No iPad-specific icon requirement while the target remains iPhone-only.

## 6. User Roles / Permissions

| Role | Permission | Forbidden Actions |
|---|---|---|
| Spec Owner | Write `docs/1.0.0/00_SPEC.md`, `01_CHANGELOG.md`, `02_FEATURE_LIST.md`, and `03_WORKFLOW.md`; define requirements and acceptance criteria. | Modify app code, Xcode project files, assets, test implementation, `qa/`, `builder/`, `fix/`, or `release/`. |
| Builder | Implement the icon fix with the smallest necessary changes to `vino_iPhone` icon assets and build settings; update target version to `1.0.0` if required by this spec. | Modify QA standards, mark tests as passed, change unrelated app behavior, rename the app, change bundle id, or broaden device families. |
| Dev Self-Check | Build and inspect the product after Builder changes; produce self-check evidence only. | Modify production code or QA criteria after declaring self-check. |
| QA Planner | Convert this spec into full no-dead-angle test plan and cases. | Change acceptance criteria to fit the implementation. |
| QA Executor | Execute static, simulator, and device verification; record evidence and issues. | Modify code, assets, project settings, or test standards. |
| Fixer | Fix only issues reported by QA and explain each resolution. | Change this spec, weaken QA cases, or modify unrelated behavior. |
| QA Retest | Re-run failed and key regression checks independently. | Accept `SKIPPED` or `NOT RUN` as pass. |
| Release Judge | Decide release readiness based on complete evidence. | Fix code, rewrite test results, or accept open blocker/major issues without explicit business approval. |

## 7. Functional Requirements

### FR-001: Correct App Icon Artwork

- Description: The installed app icon must display the intended `vino_iPhone` product icon on iOS surfaces, not a placeholder, stale cached icon, wrong project icon, blank image, transparent image, or incorrectly padded/rounded source image.
- Input: Approved icon artwork or approved repository source asset.
- Output: Correct app icon visible on iPhone Home Screen, App Library/Search, Settings app list, and App Switcher after installation.
- Preconditions: Builder has an approved source image or documents the selected approved source.
- Postconditions: Icon appearance is consistent across simulator and physical iPhone evidence.
- Error Cases: Wrong artwork, missing artwork, transparent icon, old cached icon, black/blank icon, asset compiler fallback, or mismatched Debug/Release icon.
- Permission Requirement: Builder may change only icon assets and necessary build/version settings.

### FR-002: Complete And Valid Asset Catalog

- Description: `AppIcon.appiconset` must be complete for the chosen Xcode iOS app icon mode and must pass asset compilation without icon warnings.
- Input: `Contents.json` and all referenced image files under `AppIcon.appiconset`.
- Output: A valid `AppIcon` compiled into the built app asset catalog.
- Preconditions: `ASSETCATALOG_COMPILER_APPICON_NAME` points to `AppIcon` for Debug and Release.
- Postconditions: Every JSON filename exists, every referenced PNG is valid, and no stale or unreferenced icon file causes ambiguity.
- Error Cases: Missing file, wrong size, alpha channel, corrupt PNG, mixed single-size and legacy slots without full coverage, duplicate conflicting idiom/size entries, or asset compiler warning.
- Permission Requirement: Builder may replace or expand icon assets only inside the app icon set unless project wiring must be corrected.

### FR-003: Xcode Build Integration

- Description: The app target must compile the `AppIcon` asset catalog into Debug and Release products.
- Input: `vino_iPhone.xcodeproj`, scheme `vino_iPhone`, target build settings, resources build phase.
- Output: Built app bundle contains the compiled icon asset and uses it as `CFBundleIcons` data.
- Preconditions: `Assets.xcassets` remains in the Resources build phase.
- Postconditions: Clean simulator and device builds have no icon-related warnings or errors.
- Error Cases: Asset catalog not in resources, app icon build setting removed, only one configuration fixed, generated Info.plist conflicts, or stale DerivedData masks failure.
- Permission Requirement: Builder may edit project settings only when directly required to satisfy this spec.

### FR-004: Preserve App Identity And Info.plist Fields

- Description: Fixing the icon must not rename the app or alter unrelated `Info.plist` capabilities and permissions.
- Input: `AppHost/Info.plist` and target build settings.
- Output: Built app still displays as `灵眼GX` and retains existing required permissions and Bonjour/local-network settings.
- Preconditions: Existing `Info.plist` remains the source of truth with `GENERATE_INFOPLIST_FILE = NO`.
- Postconditions: `CFBundleDisplayName`, `CFBundleName`, `CFBundleIdentifier`, permissions, `UILaunchScreen`, and portrait orientation remain consistent unless explicitly approved outside this iteration.
- Error Cases: Display name changed to `vino_iPhone`, bundle id changed, permission string removed, generated plist overwrites manual plist, or category changes unexpectedly.
- Permission Requirement: Builder may adjust version-related build settings but must not change app identity.

### FR-005: Preserve iPhone-Only Targeting

- Description: The icon fix must preserve iPhone-only packaging and test coverage.
- Input: Target build settings and built app metadata.
- Output: `TARGETED_DEVICE_FAMILY = 1`, iPhone simulator/device support remains, and iPad/Mac variants are not introduced.
- Preconditions: Current target is an iPhone app with `SUPPORTED_PLATFORMS = iphoneos iphonesimulator`.
- Postconditions: QA verifies on iPhone simulator and physical iPhone; iPad-specific icon slots are not required while target remains iPhone-only.
- Error Cases: Target broadened to iPad, Mac Catalyst enabled, Mac Designed for iPhone/iPad enabled, or QA tests only iPad/non-iPhone surfaces.
- Permission Requirement: No role may broaden supported device families in this iteration.

### FR-006: Target Version 1.0.0 Consistency

- Description: The app target version must align with the iteration target version `1.0.0`.
- Input: Debug and Release target build settings, built `Info.plist`, and iteration docs.
- Output: `MARKETING_VERSION = 1.0.0` for Debug and Release; built `CFBundleShortVersionString` resolves to `1.0.0`.
- Preconditions: `CFBundleShortVersionString` remains `$(MARKETING_VERSION)`.
- Postconditions: Release evidence cannot reference `0.1.0` as the delivered target version.
- Error Cases: Only Debug updated, only Release updated, docs say `1.0.0` while app bundle says `0.1.0`, or `CFBundleVersion` is changed without evidence.
- Permission Requirement: Builder may update version build settings required to reach `1.0.0`.

### FR-007: No-Dead-Angle Icon Verification

- Description: QA must verify the icon with static checks, clean builds, clean installs, upgrade/reinstall checks, simulator evidence, and physical iPhone evidence.
- Input: Fixed source tree, built app bundles, simulator, physical iPhone, screenshots/logs.
- Output: Complete pass/fail evidence across all required surfaces.
- Preconditions: Builder and Dev Self-Check artifacts exist before QA execution.
- Postconditions: `SKIPPED` and `NOT RUN` are not accepted as pass for required icon checks.
- Error Cases: Simulator-only validation, device-only validation, no screenshots, no asset compiler log, no built plist inspection, or cache not cleared before judging.
- Permission Requirement: QA may only observe, execute, and report.

## 8. API / UI Requirements

| ID | Surface | Requirement | Expected Behavior |
|---|---|---|---|
| UI-001 | iPhone Home Screen | App icon must display correct final artwork after clean install. | No default placeholder, old icon, blank icon, or wrong project icon. |
| UI-002 | App Library / Spotlight Search | App icon and app name must match the installed app identity. | Icon matches Home Screen; name remains `灵眼GX`. |
| UI-003 | Settings app list | App entry must show the correct icon and display name. | Icon matches Home Screen; name remains `灵眼GX`. |
| UI-004 | App Switcher | Running app card must show the correct app icon where iOS displays it. | No placeholder or stale icon. |
| UI-005 | Built app metadata | Built `Info.plist` must resolve expected identity and version. | `CFBundleDisplayName = 灵眼GX`; `CFBundleShortVersionString = 1.0.0`. |
| UI-006 | Xcode/asset compiler | Build output must include `AppIcon` without warnings. | Debug and Release asset compilation succeeds cleanly. |

## 9. State Transitions

| From | Action | To | Role | Guard |
|---|---|---|---|---|
| Spec missing | Write Spec Owner artifacts | `SPEC_READY` | Spec Owner | `00_SPEC.md` ends with `SPEC_READY` and sibling docs exist. |
| Icon incorrect or ambiguous | Replace or correct icon asset source | Asset candidate ready | Builder | Approved source recorded; no unrelated changes. |
| Asset candidate ready | Validate `Contents.json` and PNG metadata | Catalog statically valid | Builder / Dev Self-Check | All referenced files exist; image dimensions/alpha valid; no stale conflicting entries. |
| Catalog statically valid | Clean Debug simulator build | Simulator build ready | Dev Self-Check | No asset or Info.plist warnings/errors. |
| Simulator build ready | Inspect built app metadata/assets | Build integration verified | Dev Self-Check | Built plist and `Assets.car` prove `AppIcon` and version `1.0.0`. |
| Build integration verified | Execute clean simulator install checks | Simulator icon verified | QA Executor | Home Screen, Search/App Library, Settings, and App Switcher evidence captured. |
| Simulator icon verified | Execute physical iPhone checks | Device icon verified | QA Executor | Physical iPhone install evidence captured; no required test skipped. |
| Any verification failed | Report issue and fix minimally | Ready for retest | QA Executor / Fixer | Issue has severity, reproduction, fix report, and retest evidence. |
| All required checks pass | Release Judge reviews evidence | Release decision | Release Judge | No open blocker; no unapproved open major; no `SKIPPED`/`NOT RUN` required checks. |

## 10. Acceptance Criteria

| AC ID | Related FR | Criteria | Verification Method |
|---|---|---|---|
| AC-001 | FR-001 | The final icon artwork is the approved `vino_iPhone` icon and is not a placeholder, generic Xcode icon, wrong product icon, blank image, or stale cached image. | Visual comparison against approved source plus QA screenshots from simulator and physical iPhone. |
| AC-002 | FR-002 | `AppHost/Assets.xcassets/AppIcon.appiconset/Contents.json` is valid JSON, has `info.version = 1`, and references only files that exist in the same app icon set. | Static JSON/file existence check. |
| AC-003 | FR-002 | If single-size iOS icon mode is retained, the catalog has exactly one iOS universal `1024x1024` image entry, its PNG is exactly `1024x1024`, square, non-transparent, readable by macOS image tools, and accepted by `actool` without warnings. | `sips`, JSON inspection, and clean `xcodebuild`/asset compiler log. |
| AC-004 | FR-002 | If legacy multi-slot mode is used instead, every required iPhone notification, settings, spotlight, app, and iOS marketing slot is populated for required scales, with no iPad-only slots required. | JSON slot matrix inspection and asset compiler log. |
| AC-005 | FR-003 | Debug and Release both keep `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`. | Inspect `project.pbxproj` or `xcodebuild -showBuildSettings` for both configurations. |
| AC-006 | FR-003 | `Assets.xcassets` remains in the `vino_iPhone` Resources build phase and compiles into the app bundle. | Inspect project resources and built product `Assets.car` with asset tooling. |
| AC-007 | FR-003 | Clean Debug simulator build succeeds with no AppIcon, asset catalog, or Info.plist warnings/errors. | Run documented `xcodebuild` simulator clean build with `CODE_SIGNING_ALLOWED=NO`; archive logs. |
| AC-008 | FR-003 | Release or generic iOS build succeeds sufficiently to prove device packaging uses the same icon settings. | Run Release `iphoneos`/generic iOS build or signed device build; archive logs. |
| AC-009 | FR-004 | Source `Info.plist` still contains `CFBundleDisplayName = 灵眼GX`, `CFBundleName = 灵眼GX`, `CFBundleShortVersionString = $(MARKETING_VERSION)`, and `LSRequiresIPhoneOS = true`. | Static plist inspection. |
| AC-010 | FR-004 | Built app `Info.plist` resolves display name to `灵眼GX` and bundle id to `cc.vino.iphone`. | Inspect built app plist with plist tooling. |
| AC-011 | FR-005 | Debug and Release keep `TARGETED_DEVICE_FAMILY = 1`, `SUPPORTED_PLATFORMS = iphoneos iphonesimulator`, and Mac/Catalyst/XR support disabled. | Inspect `xcodebuild -showBuildSettings` for both configurations. |
| AC-012 | FR-005 | QA executes on at least one iPhone simulator and one physical iPhone; iPad or Mac-only evidence cannot satisfy required coverage. | QA run evidence with device model, OS version, install method, and screenshots. |
| AC-013 | FR-006 | Debug and Release set `MARKETING_VERSION = 1.0.0`; built `CFBundleShortVersionString` resolves to `1.0.0`. | Build settings and built plist inspection. |
| AC-014 | FR-006 | Iteration evidence, changelog, and release decision all refer to target version `1.0.0`; no delivered artifact claims `0.1.0`. | Documentation and build metadata review. |
| AC-015 | FR-007 | Simulator validation includes clean install after uninstall, Home Screen, App Library/Search, Settings app list, App Switcher, and app launch sanity check. | QA screenshots and command log. |
| AC-016 | FR-007 | Physical iPhone validation includes uninstall/reinstall or first install, Home Screen, Search/App Library, Settings app list, App Switcher, and app launch sanity check. | QA screenshots/photos and signed build/install log. |
| AC-017 | FR-007 | Cache risk is explicitly tested: DerivedData is cleaned before build, simulator app is uninstalled before install, and device app is uninstalled or upgraded according to the test case. | QA command log and precondition evidence. |
| AC-018 | FR-007 | Any `SKIPPED`, `NOT RUN`, or inconclusive required icon check blocks release readiness until rerun or explicitly accepted by business with severity rationale. | Release Judge review of QA artifacts. |

## 11. Edge Cases

| Case | Expected Behavior | Priority |
|---|---|---|
| iOS icon cache shows old icon after asset replacement | QA must clear install/cache conditions before judging and record the exact cleanup method. | High |
| Simulator passes but physical iPhone shows old or wrong icon | Release is blocked until device-specific cause is fixed or explicitly accepted as non-release scope. | High |
| Debug fixed but Release still uses old icon | Release is blocked; both configurations must pass. | High |
| Single-size catalog mixed with partial legacy slots | Release is blocked unless the catalog is made internally complete and asset compiler clean. | High |
| PNG has alpha channel or pre-rounded corners | Release is blocked unless Apple icon requirements and approved visual appearance are satisfied. | High |
| Display name changes while fixing icon | Release is blocked; app name must remain `灵眼GX`. | High |
| Target version remains `0.1.0` | Release is blocked for target `1.0.0`. | High |
| Physical iPhone unavailable | Required device coverage is `NOT RUN`; release cannot pass unless business explicitly accepts the gap. | High |
| iPad icon slots absent | Acceptable only while target remains iPhone-only and asset compiler has no warnings. | Medium |
| Asset compiler scales single 1024 source differently from expectation | QA visual evidence and approved artwork comparison decide pass/fail. | Medium |

## 12. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Approved final icon artwork is not identified | Builder may fix packaging but still ship the wrong visual asset. | Require Builder to record the approved source or obtain approval before replacing artwork. |
| Xcode single-size icon behavior differs by toolchain | Catalog may compile locally but fail elsewhere. | Record Xcode version and accept only asset-compiler-clean evidence; expand to legacy slots if needed. |
| Device signing/provisioning blocks physical iPhone install | Required device coverage may be missing. | Treat as a blocker for release readiness, not as a passed test. |
| iOS caching hides actual icon result | QA may falsely pass or fail. | Require clean install/cache controls and evidence. |
| Version update touches unrelated release settings | Scope creep or accidental behavior change. | Limit Builder changes to `MARKETING_VERSION` and directly required icon settings. |
| Other repository apps have icons with similar names | Wrong target or asset set could be modified. | Require all changes and tests to reference `vino_iPhone` target and `AppHost/Assets.xcassets/AppIcon.appiconset`. |

## 13. Deliverables

| Deliverable | Owner | Required Content |
|---|---|---|
| `docs/1.0.0/00_SPEC.md` | Spec Owner | Requirements, acceptance criteria, roles, state transitions, edge cases, risks, assumptions, `SPEC_READY`. |
| `docs/1.0.0/01_CHANGELOG.md` | Spec Owner | Planned change summary for version `1.0.0`. |
| `docs/1.0.0/02_FEATURE_LIST.md` | Spec Owner | Feature and verification capability list. |
| `docs/1.0.0/03_WORKFLOW.md` | Spec Owner | Downstream workflow, permissions, gates, and evidence requirements. |
| `docs/1.0.0/builder/DEV_NOTES.md` | Builder | Future artifact, not created by Spec Owner. Must summarize implementation changes and icon source. |
| `docs/1.0.0/builder/SELF_CHECK.md` and `BUILD_RESULT.md` | Dev Self-Check | Future artifacts, not created by Spec Owner. Must include build and metadata evidence. |
| `docs/1.0.0/qa/*` | QA Planner / QA Executor | Future artifacts, not created by Spec Owner. Must include no-dead-angle test plan, cases, run, issues, and regression suggestions. |
| `docs/1.0.0/fix/*` | Fixer | Future artifacts, not created by Spec Owner. Must include issue resolution if QA finds defects. |
| `docs/1.0.0/release/*` | Release Judge | Future artifacts, not created by Spec Owner. Must include release checklist and decision. |

## 14. Missing Questions

| Question | Why It Matters | Default If Unanswered |
|---|---|---|
| What is the approved final `vino_iPhone` icon artwork source? | Visual correctness cannot be proven without a reference. | Builder must locate an approved repository/user-provided source or request approval before changing artwork. |
| Which physical iPhone model and iOS version are available for QA? | Device coverage is required and may expose packaging/cache differences. | Any physical iPhone capable of installing the app on the supported iOS range is acceptable, but lack of device coverage blocks release pass. |
| Should the catalog remain in current single-size universal mode or be expanded to legacy iPhone slots? | Both can be valid depending on Xcode/toolchain policy. | Keep single-size mode if asset compiler is clean; expand only if needed to satisfy toolchain or visual correctness. |
| Is `CURRENT_PROJECT_VERSION = 1` acceptable for `1.0.0`? | Build number policy is not specified. | Preserve `CURRENT_PROJECT_VERSION = 1` unless release policy says otherwise. |
| Where should QA screenshots/photos be stored? | Evidence location affects release traceability. | Store paths inside future QA artifacts without creating evidence directories in Spec Owner phase. |
| Is signed physical-device installation available through the existing development team? | Physical device verification may require signing setup. | Treat signing blockage as a release blocker or externally accepted risk, not a passed test. |

## 15. Conservative Assumptions

- `vino_iPhone` is independent for this iteration; other repository components must not be modified.
- The existing app display name `灵眼GX` and bundle id `cc.vino.iphone` are intentional and must be preserved.
- The existing iPhone-only target is intentional and must remain `TARGETED_DEVICE_FAMILY = 1`.
- The current Xcode single-size app icon catalog can be valid if `actool` accepts it without warnings and the final icon displays correctly.
- `MARKETING_VERSION` must become `1.0.0` for both Debug and Release because this iteration target is `1.0.0`.
- `CURRENT_PROJECT_VERSION = 1` remains acceptable unless a release owner provides a different build-number policy.
- Required physical iPhone coverage cannot be substituted by simulator-only checks.
- Spec Owner artifacts define required behavior only and do not claim implementation or QA pass status.

SPEC_READY
