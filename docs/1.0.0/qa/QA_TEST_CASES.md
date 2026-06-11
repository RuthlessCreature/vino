# QA Test Cases: vino_iPhone 1.0.0

These test cases are definitions only. QA Executor must record actual results, evidence paths, issues, and retest outcomes in separate execution artifacts.

## Test Case Index

| Test Case | Title | Primary Coverage |
|---|---|---|
| `TC-001` | Changed-file scope and approved icon source guard | `AC-001` |
| `TC-002` | Static `Contents.json` validity and referenced-file existence | `AC-002` |
| `TC-003` | PNG metadata, alpha, readability, and visual source sanity | `AC-001`, `AC-003` |
| `TC-004` | Icon catalog mode and slot matrix completeness | `AC-003`, `AC-004` |
| `TC-005` | Debug/Release build settings for icon, version, and device support | `AC-005`, `AC-011`, `AC-013` |
| `TC-006` | Asset catalog resource integration and wrong-target guard | `AC-006` |
| `TC-007` | DerivedData cleanup and clean Debug simulator build | `AC-003`, `AC-004`, `AC-007`, `AC-017` |
| `TC-008` | Release generic iOS build packaging check | `AC-008` |
| `TC-009` | Source and built `Info.plist` identity/version/permission regression | `AC-009`, `AC-010`, `AC-013` |
| `TC-010` | Compiled `Assets.car` icon evidence | `AC-006` |
| `TC-011` | iPhone simulator clean install visual surfaces and launch sanity | `AC-001`, `AC-012`, `AC-015` |
| `TC-012` | Simulator stale icon cache boundary | `AC-001`, `AC-015`, `AC-017` |
| `TC-013` | Physical iPhone install visual surfaces and launch sanity | `AC-001`, `AC-012`, `AC-016` |
| `TC-014` | Physical device availability and signing/install blocker handling | `AC-012`, `AC-016`, `AC-018` |
| `TC-015` | Device uninstall/reinstall or controlled upgrade cache boundary | `AC-001`, `AC-015`, `AC-016`, `AC-017` |
| `TC-016` | Missing icon reference negative case | `AC-002` |
| `TC-017` | Documentation and delivered version consistency | `AC-014` |
| `TC-018` | Simulator-only coverage release gate | `AC-012`, `AC-018` |
| `TC-019` | Debug/Release mismatch negative case | `AC-005`, `AC-008`, `AC-013` |
| `TC-020` | Wrong app target negative case | `AC-006` |
| `TC-021` | Identity, permissions, iPhone-only, and version regression sweep | `AC-009`, `AC-010`, `AC-011`, `AC-013` |
| `TC-022` | Stale DerivedData boundary | `AC-007`, `AC-017` |
| `TC-023` | QA completion and issue gate review | `AC-014`, `AC-018` |

## TC-001: Changed-File Scope And Approved Icon Source Guard

| Field | Definition |
|---|---|
| Objective | Verify the delivered change scope targets only `vino_iPhone` icon assets and required version/build settings, and that the visual icon source is identified. |
| Acceptance Criteria | `AC-001` |
| Preconditions | Repository is at the delivered candidate state; QA has the changed-file summary and builder notes. |
| Steps | Review changed-file summary, `builder/DEV_NOTES.md`, and any QA-approved source reference. Confirm icon files are under `vino_iPhone/AppHost/Assets.xcassets/AppIcon.appiconset`, project change is under `vino_iPhone/vino_iPhone.xcodeproj`, and no other app icon target is used as evidence. |
| Expected Evidence | Changed-file summary excerpt, builder source note, and QA visual reference or approval note for the intended `vino_iPhone` icon. |
| Issue Trigger | File changes or evidence point to another target/app, approved icon source is absent or disputed, or visual reference cannot distinguish the intended icon from a placeholder/wrong product icon. |

## TC-002: Static `Contents.json` Validity And Referenced-File Existence

| Field | Definition |
|---|---|
| Objective | Verify `AppIcon.appiconset/Contents.json` is valid JSON with `info.version = 1` and every referenced file exists in the same app icon set. |
| Acceptance Criteria | `AC-002` |
| Preconditions | No repository modifications by QA; static inspection tools available. |
| Steps | Parse `vino_iPhone/AppHost/Assets.xcassets/AppIcon.appiconset/Contents.json`. Check `info.version`. Enumerate `images[].filename`. Verify each non-empty filename exists in the app icon set directory. Verify no referenced file path escapes the app icon set. |
| Expected Evidence | JSON parse log, image-entry list, referenced-file existence table, and no path-escape findings. |
| Issue Trigger | Invalid JSON, missing `info.version = 1`, missing file, empty filename for a required delivered slot, duplicate/conflicting filename use, or reference outside the app icon set. |

## TC-003: PNG Metadata, Alpha, Readability, And Visual Source Sanity

| Field | Definition |
|---|---|
| Objective | Verify every referenced PNG is readable, square, exact expected dimensions for its slot, has no alpha channel, and visually matches the approved source artwork. |
| Acceptance Criteria | `AC-001`, `AC-003` |
| Preconditions | `TC-002` has produced the list of referenced PNGs; approved visual source is available or its absence is filed as an issue. |
| Steps | Run image metadata checks such as `sips -g pixelWidth -g pixelHeight -g hasAlpha <file>` for every referenced PNG. For legacy slots, verify pixel size equals point size multiplied by scale: `20@2x=40`, `20@3x=60`, `29@2x=58`, `29@3x=87`, `40@2x=80`, `40@3x=120`, `60@2x=120`, `60@3x=180`, marketing `1024@1x=1024`. If a single-size catalog is delivered instead, verify the one universal icon is exactly `1024x1024`. Compare rendered previews against the approved source for obvious wrong artwork, blank output, transparency, pre-rounded/padded rendering, or placeholder image. |
| Expected Evidence | PNG metadata table, preview/contact sheet or screenshots, and source-comparison notes. |
| Issue Trigger | Corrupt/unreadable PNG, wrong dimensions, non-square image, alpha present, wrong visual artwork, blank/transparent image, placeholder image, excessive padding, or pre-rounded corners that violate expected iOS icon rendering. |

## TC-004: Icon Catalog Mode And Slot Matrix Completeness

| Field | Definition |
|---|---|
| Objective | Verify the delivered catalog is internally complete for its selected mode and does not mix a partial legacy matrix with a single-size source in a warning-prone way. |
| Acceptance Criteria | `AC-003`, `AC-004` |
| Preconditions | `Contents.json` is parseable. |
| Steps | Determine whether the delivered catalog uses single-size iOS universal mode or legacy multi-slot mode. For the builder-declared legacy mode, verify required iPhone slots are present for notification `20x20@2x/@3x`, settings `29x29@2x/@3x`, spotlight `40x40@2x/@3x`, app `60x60@2x/@3x`, and `ios-marketing 1024x1024@1x`. Verify no iPad-only slots are required while `TARGETED_DEVICE_FAMILY = 1`. Verify there are no duplicate conflicting idiom/size/scale entries. |
| Expected Evidence | Slot matrix table with idiom, size, scale, filename, and mode decision. |
| Issue Trigger | Missing required iPhone slot, mixed partial mode, duplicate conflicting entries, iPad-only dependency introduced, or asset compiler warnings attributable to the catalog mode. |

## TC-005: Debug/Release Build Settings For Icon, Version, And Device Support

| Field | Definition |
|---|---|
| Objective | Verify Debug and Release build settings preserve the app icon name, version `1.0.0`, iPhone-only support, and disabled Mac/Catalyst/XR support. |
| Acceptance Criteria | `AC-005`, `AC-011`, `AC-013` |
| Preconditions | Xcode command line tools available; project path is `vino_iPhone/vino_iPhone.xcodeproj`; scheme is `vino_iPhone`. |
| Steps | Run or inspect `xcodebuild -project vino_iPhone.xcodeproj -scheme vino_iPhone -configuration Debug -showBuildSettings` and the Release equivalent. Capture `ASSETCATALOG_COMPILER_APPICON_NAME`, `MARKETING_VERSION`, `TARGETED_DEVICE_FAMILY`, `SUPPORTED_PLATFORMS`, `SUPPORTS_MACCATALYST`, `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD`, `SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD`, `INFOPLIST_FILE`, and bundle identifier settings. |
| Expected Evidence | Debug/Release build-setting excerpt table. |
| Issue Trigger | `ASSETCATALOG_COMPILER_APPICON_NAME` not `AppIcon` in either configuration, only one configuration updated, `MARKETING_VERSION` not `1.0.0`, iPad/Mac/Catalyst/XR support broadened, wrong `Info.plist`, or bundle id source changed unexpectedly. |

## TC-006: Asset Catalog Resource Integration And Wrong-Target Guard

| Field | Definition |
|---|---|
| Objective | Verify `Assets.xcassets` remains in the `vino_iPhone` Resources build phase and evidence is from the correct target, not another repository app. |
| Acceptance Criteria | `AC-006` |
| Preconditions | Project can be inspected with Xcode/project tooling or build logs. |
| Steps | Inspect the project resource phase or build log to confirm `AppHost/Assets.xcassets` is compiled for target `vino_iPhone`. Verify commands use `vino_iPhone.xcodeproj`, scheme `vino_iPhone`, and resulting bundle id `cc.vino.iphone`. Reject artifacts from other targets or asset catalogs. |
| Expected Evidence | Resource phase excerpt or `CompileAssetCatalog` log showing `AppHost/Assets.xcassets` and `--app-icon AppIcon` for `vino_iPhone`. |
| Issue Trigger | Asset catalog omitted from resources, different scheme/target used, wrong asset catalog path, wrong bundle id, or evidence from another app. |

## TC-007: DerivedData Cleanup And Clean Debug Simulator Build

| Field | Definition |
|---|---|
| Objective | Prove a clean Debug simulator build succeeds without stale DerivedData and without AppIcon, asset catalog, or Info.plist warnings/errors. |
| Acceptance Criteria | `AC-003`, `AC-004`, `AC-007`, `AC-017` |
| Preconditions | Xcode installed; iPhone simulator SDK available; DerivedData cleanup/isolation method selected. |
| Steps | Record the DerivedData cleanup or isolated `-derivedDataPath` method. Run `xcodebuild -project vino_iPhone.xcodeproj -scheme vino_iPhone -sdk iphonesimulator -configuration Debug clean build CODE_SIGNING_ALLOWED=NO` from `vino_iPhone/`. Review full log for `CompileAssetCatalog`, `actool`, `AppIcon`, `Info.plist`, warning, and error lines. |
| Expected Evidence | Cleanup command/evidence, build command, destination/SDK, product path, and log excerpts showing asset catalog compilation. |
| Issue Trigger | Build failure, asset/icon/Info.plist warning or error, no `CompileAssetCatalog`, no `--app-icon AppIcon`, stale DerivedData used without cleanup evidence, or product path not produced. |

## TC-008: Release Generic iOS Build Packaging Check

| Field | Definition |
|---|---|
| Objective | Prove Release/device packaging uses the same icon settings and can produce a generic iOS product. |
| Acceptance Criteria | `AC-008` |
| Preconditions | Xcode installed; generic iOS destination available; code signing can be disabled for generic build or a signed device build method is available. |
| Steps | Run `xcodebuild -project vino_iPhone.xcodeproj -scheme vino_iPhone -sdk iphoneos -configuration Release -destination 'generic/platform=iOS' clean build CODE_SIGNING_ALLOWED=NO` or a signed equivalent. Review log for `CompileAssetCatalog`, `--app-icon AppIcon`, target device `iphone`, and build warnings/errors. |
| Expected Evidence | Release build command, destination, product path, and log excerpts proving `AppIcon` compilation for `iphoneos`. |
| Issue Trigger | Release build failure, signing blocker not classified, icon setting absent, `actool` warning, Debug-only fix, or product not suitable for device packaging evidence. |

## TC-009: Source And Built `Info.plist` Identity/Version/Permission Regression

| Field | Definition |
|---|---|
| Objective | Verify source and built app metadata preserve display name, bundle id, required permissions/settings, and version `1.0.0`. |
| Acceptance Criteria | `AC-009`, `AC-010`, `AC-013` |
| Preconditions | Debug simulator and Release iOS products are available from current candidate builds. |
| Steps | Inspect source `vino_iPhone/AppHost/Info.plist` for `CFBundleDisplayName = 灵眼GX`, `CFBundleName = 灵眼GX`, `CFBundleShortVersionString = $(MARKETING_VERSION)`, `LSRequiresIPhoneOS = true`, launch screen, orientation, privacy permission strings, Bonjour/local-network settings, and manual plist usage. Inspect Debug and Release built `Info.plist` with `/usr/libexec/PlistBuddy` or equivalent for `CFBundleDisplayName`, `CFBundleName`, `CFBundleIdentifier`, `CFBundleShortVersionString`, `CFBundleVersion`, `LSRequiresIPhoneOS`, and existing permission/network keys. |
| Expected Evidence | Source plist key table and built Debug/Release plist key table. |
| Issue Trigger | Display name changed from `灵眼GX`, bundle id not `cc.vino.iphone`, version not `1.0.0`, required permission/network key removed, generated plist overrides manual plist, `LSRequiresIPhoneOS` missing/false, or unrelated metadata changes. |

## TC-010: Compiled `Assets.car` Icon Evidence

| Field | Definition |
|---|---|
| Objective | Verify the built app bundles contain compiled icon assets in `Assets.car` for Debug and Release. |
| Acceptance Criteria | `AC-006` |
| Preconditions | Debug simulator and Release iOS products exist from the current candidate builds. |
| Steps | Confirm each built `.app` contains `Assets.car`. Run `xcrun assetutil --info <built-app>/Assets.car` for Debug and Release. Search output for `AppIcon` entries and expected iPhone/marketing renditions. Compare Debug/Release output for parity. |
| Expected Evidence | `Assets.car` existence check and `assetutil` excerpts for Debug and Release. |
| Issue Trigger | Missing `Assets.car`, `assetutil` failure, missing `AppIcon` entries, expected renditions absent, Debug/Release compiled asset mismatch, or evidence from wrong product. |

## TC-011: iPhone Simulator Clean Install Visual Surfaces And Launch Sanity

| Field | Definition |
|---|---|
| Objective | Verify the app icon displays correctly on required iPhone simulator surfaces after a clean install and the app launches. |
| Acceptance Criteria | `AC-001`, `AC-012`, `AC-015` |
| Preconditions | Debug simulator app product exists; an iPhone simulator runtime is available; app is uninstalled before install. |
| Steps | Record simulator model, runtime, UDID, and install method. Uninstall existing `cc.vino.iphone` from the simulator. Install the current Debug simulator `.app`. Capture screenshots for Home Screen, App Library or Spotlight Search, Settings app list, and App Switcher. Launch the app and capture launch sanity evidence. Compare icon to approved source and display name `灵眼GX`. |
| Expected Evidence | Simulator command log and screenshots for all required surfaces plus launch evidence. |
| Issue Trigger | Placeholder/generic Xcode icon, stale old icon, wrong product icon, blank/black/transparent icon, display name mismatch, app cannot launch, app not uninstallable/installable, missing screenshot, or non-iPhone simulator used. |

## TC-012: Simulator Stale Icon Cache Boundary

| Field | Definition |
|---|---|
| Objective | Verify simulator visual judgment is not affected by stale icon cache. |
| Acceptance Criteria | `AC-001`, `AC-015`, `AC-017` |
| Preconditions | `TC-011` simulator destination selected. |
| Steps | Before final simulator screenshots, uninstall `cc.vino.iphone`; if stale icon remains suspected, reboot simulator or erase the selected simulator only after recording the reason. Reinstall the current build and repeat Home Screen/Search/Settings/App Switcher checks. Record exact cache-control method. |
| Expected Evidence | Uninstall/reinstall log and any simulator reboot/erase evidence with repeated screenshots. |
| Issue Trigger | Old icon remains after reinstall, cache-control method not recorded, visual evidence captured before cleanup, or screenshots conflict between surfaces. |

## TC-013: Physical iPhone Install Visual Surfaces And Launch Sanity

| Field | Definition |
|---|---|
| Objective | Verify the app icon displays correctly on a physical iPhone after install and the app launches. |
| Acceptance Criteria | `AC-001`, `AC-012`, `AC-016` |
| Preconditions | Physical iPhone available; signing/provisioning or install path available; device can install `cc.vino.iphone`. |
| Steps | Record device model, iOS version, identifier/redacted identifier, signing method, build configuration, and install method. Uninstall existing app or confirm first install. Install the signed current candidate. Capture photos/screenshots for Home Screen, App Library or Spotlight Search, Settings app list, and App Switcher. Launch the app and capture launch sanity evidence. Compare icon to approved source and display name `灵眼GX`. |
| Expected Evidence | Device install log, device metadata, and photos/screenshots for all required surfaces plus launch evidence. |
| Issue Trigger | Device install unavailable, placeholder/generic Xcode icon, stale old icon, wrong product icon, blank/black/transparent icon, display name mismatch, launch failure, missing device metadata, or missing physical-device visual evidence. |

## TC-014: Physical Device Availability And Signing/Install Blocker Handling

| Field | Definition |
|---|---|
| Objective | Ensure physical iPhone coverage is treated as required and unavailable coverage becomes a QA issue. |
| Acceptance Criteria | `AC-012`, `AC-016`, `AC-018` |
| Preconditions | QA has attempted to identify physical iPhone and install path. |
| Steps | Confirm physical iPhone availability and signing/install capability before execution. If unavailable, record exact blocker: no device, no cable/trust, provisioning/signing failure, install command failure, organization policy, or other cause. Create a QA issue with severity and release impact. Do not substitute simulator, iPad, Mac, builder screenshot, or self-check evidence. |
| Expected Evidence | Device readiness record or blocker issue details. |
| Issue Trigger | Physical iPhone unavailable, signing/install path unavailable, blocker not documented, or release evidence attempts to count simulator-only coverage as sufficient. |

## TC-015: Device Uninstall/Reinstall Or Controlled Upgrade Cache Boundary

| Field | Definition |
|---|---|
| Objective | Verify install/cache behavior on simulator and physical iPhone does not hide a stale icon. |
| Acceptance Criteria | `AC-001`, `AC-015`, `AC-016`, `AC-017` |
| Preconditions | Simulator and physical iPhone install methods are available. |
| Steps | On simulator, uninstall `cc.vino.iphone`, install current app, capture visual surfaces, uninstall again, reinstall, and confirm icon remains correct. On physical iPhone, uninstall/reinstall or perform a documented controlled upgrade path if uninstall is not acceptable; capture before/after evidence. Record exact commands/manual steps. |
| Expected Evidence | Simulator and device uninstall/reinstall or upgrade logs plus repeated visual evidence. |
| Issue Trigger | Stale icon after reinstall/upgrade, missing cleanup evidence, only first install checked when existing app was present, or manual steps not reproducible. |

## TC-016: Missing Icon Reference Negative Case

| Field | Definition |
|---|---|
| Objective | Explicitly cover the missing-file fault model without modifying the repository. |
| Acceptance Criteria | `AC-002` |
| Preconditions | `TC-002` referenced-file list exists. |
| Steps | Treat every `images[].filename` in `Contents.json` as a required source file for the delivered catalog. Verify none are missing, mistyped by case, duplicated with conflicting slots, or located outside the app icon set. Record what the issue would be if any filename failed this check. |
| Expected Evidence | Missing-reference checklist tied to each filename. |
| Issue Trigger | Any missing, case-mismatched, external, or conflicting reference. |

## TC-017: Documentation And Delivered Version Consistency

| Field | Definition |
|---|---|
| Objective | Verify iteration evidence and delivered metadata consistently refer to target version `1.0.0` and do not claim delivery as `0.1.0`. |
| Acceptance Criteria | `AC-014` |
| Preconditions | QA has spec, changelog, feature list, workflow, builder notes, self-check, build result, and built plist evidence. |
| Steps | Review version references in required docs and built metadata evidence. Confirm target version is `1.0.0`, `MARKETING_VERSION` evidence is `1.0.0`, and built `CFBundleShortVersionString` evidence is `1.0.0`. Search reviewed artifacts for stale delivered-version claims such as `0.1.0`; classify baseline mentions separately from delivered target claims. |
| Expected Evidence | Documentation/version review table and any stale-version findings. |
| Issue Trigger | Delivered artifact claims target version `0.1.0`, built app version is `0.1.0`, only one configuration updated, or documentation/build metadata conflict. |

## TC-018: Simulator-Only Coverage Release Gate

| Field | Definition |
|---|---|
| Objective | Ensure simulator-only validation cannot satisfy required coverage. |
| Acceptance Criteria | `AC-012`, `AC-018` |
| Preconditions | QA execution artifact is being prepared or reviewed. |
| Steps | Compare completed evidence against required simulator and physical iPhone coverage. If simulator evidence exists but physical iPhone evidence is missing, classify the release gate as blocked and create/verify a QA issue. Confirm no iPad/Mac-only evidence is used to fill either required iPhone slot. |
| Expected Evidence | Coverage matrix showing simulator and physical iPhone evidence requirements separately. |
| Issue Trigger | Physical iPhone evidence absent, evidence from iPad/Mac substituted, or missing coverage not listed as a QA issue. |

## TC-019: Debug/Release Mismatch Negative Case

| Field | Definition |
|---|---|
| Objective | Explicitly detect mismatches between Debug and Release icon/version/build integration. |
| Acceptance Criteria | `AC-005`, `AC-008`, `AC-013` |
| Preconditions | Debug and Release build settings and built product evidence are available. |
| Steps | Compare Debug and Release for `ASSETCATALOG_COMPILER_APPICON_NAME`, `MARKETING_VERSION`, `TARGETED_DEVICE_FAMILY`, supported platforms, built `Info.plist`, and `Assets.car` icon evidence. Verify Release generic iOS packaging is not inferred from Debug simulator evidence. |
| Expected Evidence | Debug/Release comparison table. |
| Issue Trigger | Any relevant value differs unexpectedly, Debug passes but Release lacks `AppIcon`, Release version differs, Release not built, or Release evidence is inferred rather than observed. |

## TC-020: Wrong App Target Negative Case

| Field | Definition |
|---|---|
| Objective | Explicitly detect evidence produced from the wrong app target, scheme, bundle id, or asset catalog. |
| Acceptance Criteria | `AC-006` |
| Preconditions | Build/install commands and built product evidence are available. |
| Steps | Verify every command uses `vino_iPhone.xcodeproj` and scheme `vino_iPhone`. Verify built product bundle id is `cc.vino.iphone`, display name is `灵眼GX`, and compiled assets come from `AppHost/Assets.xcassets/AppIcon.appiconset`. Verify no other repository app icon is used for screenshots or build evidence. |
| Expected Evidence | Command/product target trace table. |
| Issue Trigger | Wrong scheme/project/target, wrong bundle id, screenshot from another app, asset path outside `AppHost/Assets.xcassets/AppIcon.appiconset`, or ambiguous evidence. |

## TC-021: Identity, Permissions, iPhone-Only, And Version Regression Sweep

| Field | Definition |
|---|---|
| Objective | Verify the icon fix did not regress app identity, permissions, iPhone-only targeting, or version. |
| Acceptance Criteria | `AC-009`, `AC-010`, `AC-011`, `AC-013` |
| Preconditions | Build settings, source plist, and built plist evidence exist. |
| Steps | Compare source and built metadata for `CFBundleDisplayName = 灵眼GX`, `CFBundleName = 灵眼GX`, `CFBundleIdentifier = cc.vino.iphone`, `CFBundleShortVersionString = 1.0.0`, `LSRequiresIPhoneOS = true`, existing privacy permission strings, Bonjour/local-network settings, launch screen, supported orientations, and iPhone-only build settings. Confirm no Mac Catalyst, Mac Designed for iPhone/iPad, XR Designed for iPhone/iPad, or iPad family broadening is introduced. |
| Expected Evidence | Regression checklist covering identity, permissions, iPhone-only settings, and version. |
| Issue Trigger | Any identity/version/permission/device-family value changes outside approved version update, or evidence cannot prove preservation. |

## TC-022: Stale DerivedData Boundary

| Field | Definition |
|---|---|
| Objective | Explicitly detect stale DerivedData risk before relying on build artifacts. |
| Acceptance Criteria | `AC-007`, `AC-017` |
| Preconditions | QA is about to run clean build or inspect built products. |
| Steps | Record current DerivedData strategy. Prefer an isolated `-derivedDataPath` for QA or remove only the candidate's derived build output if safe. Run required clean builds after cleanup. Verify built product timestamps and paths correspond to the current candidate build. |
| Expected Evidence | DerivedData cleanup/isolation log, build command, product path, and timestamp/path correlation. |
| Issue Trigger | Build artifacts predate the candidate, product path reused without cleanup, clean build not run, or stale artifacts used for plist/assets/screenshots. |

## TC-023: QA Completion And Issue Gate Review

| Field | Definition |
|---|---|
| Objective | Verify all required acceptance criteria have execution evidence and missing/inconclusive checks are treated as release-blocking QA issues. |
| Acceptance Criteria | `AC-014`, `AC-018` |
| Preconditions | QA execution artifacts, issue list, and evidence paths are available after execution. |
| Steps | Build an AC-to-test evidence matrix for `AC-001` through `AC-018`. Confirm each required check has concrete evidence. Confirm physical iPhone coverage is present or a QA issue exists. Confirm any skipped, unavailable, inconclusive, or blocked required check is not counted as acceptable by QA. Confirm version documentation still targets `1.0.0`. |
| Expected Evidence | Final QA coverage matrix and issue gate checklist for Release Judge. |
| Issue Trigger | Any AC lacks evidence, required physical iPhone coverage missing without issue, skipped/inconclusive check counted as acceptable, stale version claim remains, or issue severity/rationale missing. |
