# Builder DEV_NOTES: vino_iPhone 1.0.0

## 1. Implemented Scope

- `FR-001`: Corrected app icon packaging by keeping the existing repository `GX` source image and generating iPhone-specific icon renditions.
- `FR-002`: Expanded `AppIcon.appiconset` from a single universal 1024 entry to a complete iPhone legacy slot matrix plus iOS marketing icon.
- `FR-003`: Preserved `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` and `Assets.xcassets` resource integration.
- `FR-004`: Preserved `Info.plist` identity fields and did not change app display name, bundle id, permissions, or launch settings.
- `FR-005`: Preserved iPhone-only target settings.
- `FR-006`: Updated Debug and Release `MARKETING_VERSION` to `1.0.0`.

## 2. Changed Files

| File | Change | Reason | Related SPEC ID |
|---|---|---|---|
| `vino_iPhone/AppHost/Assets.xcassets/AppIcon.appiconset/Contents.json` | Replaced single universal app icon entry with iPhone notification, settings, spotlight, app, and iOS marketing slots. | Ensure every iPhone icon surface has an explicit asset slot. | `FR-001`, `FR-002` |
| `vino_iPhone/AppHost/Assets.xcassets/AppIcon.appiconset/AppIcon-20@2x.png` | Added 40x40 rendition from existing `AppIcon-1024.png`. | iPhone notification `20x20@2x`. | `FR-001`, `FR-002` |
| `vino_iPhone/AppHost/Assets.xcassets/AppIcon.appiconset/AppIcon-20@3x.png` | Added 60x60 rendition from existing `AppIcon-1024.png`. | iPhone notification `20x20@3x`. | `FR-001`, `FR-002` |
| `vino_iPhone/AppHost/Assets.xcassets/AppIcon.appiconset/AppIcon-29@2x.png` | Added 58x58 rendition from existing `AppIcon-1024.png`. | iPhone settings `29x29@2x`. | `FR-001`, `FR-002` |
| `vino_iPhone/AppHost/Assets.xcassets/AppIcon.appiconset/AppIcon-29@3x.png` | Added 87x87 rendition from existing `AppIcon-1024.png`. | iPhone settings `29x29@3x`. | `FR-001`, `FR-002` |
| `vino_iPhone/AppHost/Assets.xcassets/AppIcon.appiconset/AppIcon-40@2x.png` | Added 80x80 rendition from existing `AppIcon-1024.png`. | iPhone spotlight `40x40@2x`. | `FR-001`, `FR-002` |
| `vino_iPhone/AppHost/Assets.xcassets/AppIcon.appiconset/AppIcon-40@3x.png` | Added 120x120 rendition from existing `AppIcon-1024.png`. | iPhone spotlight `40x40@3x`. | `FR-001`, `FR-002` |
| `vino_iPhone/AppHost/Assets.xcassets/AppIcon.appiconset/AppIcon-60@2x.png` | Added 120x120 rendition from existing `AppIcon-1024.png`. | iPhone app icon `60x60@2x`. | `FR-001`, `FR-002` |
| `vino_iPhone/AppHost/Assets.xcassets/AppIcon.appiconset/AppIcon-60@3x.png` | Added 180x180 rendition from existing `AppIcon-1024.png`. | iPhone app icon `60x60@3x`. | `FR-001`, `FR-002` |
| `vino_iPhone/vino_iPhone.xcodeproj/project.pbxproj` | Updated Debug and Release `MARKETING_VERSION` from `0.1.0` to `1.0.0`. | Align built app metadata with target version. | `FR-006` |

## 3. API Changes

None.

## 4. UI Changes

No runtime UI code changed. Installed iPhone app icon resources were corrected.

## 5. Data Model / Migration Changes

None.

## 6. Developer Tests Added

No automated tests were added. This iteration changes Xcode icon assets and target metadata; Dev Self-Check must validate with asset, build-setting, build, and built-product inspections.

## 7. Assumptions

- The existing `AppIcon-1024.png` is the approved `vino_iPhone` GX icon source because no alternate approved artwork exists in the repository.
- The icon display issue is caused by incomplete iPhone app icon slots, so explicit iPhone slots are safer than relying on a single universal source.
- `CURRENT_PROJECT_VERSION = 1` remains acceptable for target version `1.0.0` per SPEC conservative assumption.

## 8. Known Limitations

- Builder did not execute QA and does not claim simulator or physical iPhone visual pass.
- Final visual correctness still requires Dev Self-Check and QA evidence on built products and installed app surfaces.

## 9. Handoff to Dev Self-Check

Recommended checks:

```bash
sips -g pixelWidth -g pixelHeight -g hasAlpha vino_iPhone/AppHost/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
xcodebuild -project vino_iPhone.xcodeproj -scheme vino_iPhone -configuration Debug -showBuildSettings
xcodebuild -project vino_iPhone.xcodeproj -scheme vino_iPhone -configuration Release -showBuildSettings
xcodebuild -project vino_iPhone.xcodeproj -scheme vino_iPhone -sdk iphonesimulator -configuration Debug clean build CODE_SIGNING_ALLOWED=NO
xcodebuild -project vino_iPhone.xcodeproj -scheme vino_iPhone -configuration Release -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO
```
