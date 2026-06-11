# Regression Suggestions: vino_iPhone 1.0.0

## 1. Recommended Automated Checks

| Area | Suggested Automation | Trigger |
|---|---|---|
| App icon catalog | Script parse `AppIcon.appiconset/Contents.json`, verify `info.version`, slot matrix, referenced files, no path escape, no unreferenced PNGs. | Every PR touching `Assets.xcassets` or Xcode project files. |
| PNG metadata | Run `sips -g pixelWidth -g pixelHeight -g hasAlpha` for every referenced icon and compare against expected point-size times scale. | Every PR touching icon PNGs. |
| Build settings | Run `xcodebuild -showBuildSettings -json` for Debug and Release and assert `AppIcon`, `MARKETING_VERSION`, iPhone-only settings, and disabled Mac/Catalyst/XR flags. | Every release candidate. |
| Clean build | Build Debug simulator and Release generic iOS with isolated DerivedData. | Every release candidate. |
| Built plist | Inspect Debug and Release `Info.plist` for display name, bundle id, version, permissions, Bonjour/local-network keys, and `LSRequiresIPhoneOS`. | Every release candidate. |
| Compiled assets | Run `xcrun assetutil --info` on unthinned simulator product and Release product, assert expected `AppIcon` renditions. | Every release candidate. |

## 2. Recommended Manual / Device Checks

| Area | Suggestion | Reason |
|---|---|---|
| Simulator visual surfaces | Keep a repeatable simulator script but require human screenshot review for Home Screen, App Library/Search, Settings, App Switcher, and launch. | Command success alone does not prove icon appearance on every visual surface. |
| Physical iPhone gate | Maintain at least one trusted test iPhone with signing path documented before release QA starts. | Physical-device coverage is mandatory and blocked this run. |
| Cache boundary | Always uninstall/reinstall on simulator and device, or document a controlled upgrade path when uninstall is not acceptable. | iOS icon cache can hide stale or wrong icons. |
| Evidence naming | Store screenshots with surface, device, runtime, and pass sequence in the filename. | Reduces ambiguity for Release Judge. |

## 3. Suggested Future Test Cases

| Case | Priority | Notes |
|---|---|---|
| `REG-ICON-001` | P0 | Validate AppIcon matrix automatically in CI. |
| `REG-ICON-002` | P0 | Build unthinned simulator product and Release generic iOS product, then compare `Assets.car` icon names. |
| `REG-ICON-003` | P0 | Execute a manual device checklist on physical iPhone before every RC. |
| `REG-ICON-004` | P1 | Verify a 2x iPhone simulator and a 3x iPhone simulator to catch scale-specific packaging gaps. |
| `REG-ICON-005` | P1 | Add a screenshot review SOP for App Library/Search and App Switcher where `simctl` navigation is limited. |

## 4. Retest Focus

| Open Issue | Retest Requirement |
|---|---|
| `ISSUE-001` | Complete simulator visual surface review and attach conclusive screenshots for Home Screen, App Library/Search, Settings, App Switcher, launch, and reinstall/cache path. |
| `ISSUE-002` | Connect/sign/install on a physical iPhone and attach conclusive device screenshots/photos for all required visual surfaces plus device metadata. |
