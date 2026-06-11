# QA Issue List: vino_iPhone 1.0.0

## Summary

| Metric | Count |
|---|---:|
| Open Blocker | 2 |
| Open Major | 0 |
| Open Minor | 0 |
| Fixed | 0 |
| External coverage blocker | 2 |
| Implementation defect confirmed | 0 |

## ISSUE-001: Simulator visual icon surfaces are not fully proven

- Status: OPEN
- Severity: Blocker
- Type: QA evidence coverage gap
- Affected AC: `AC-001`, `AC-012`, `AC-015`, `AC-017`, `AC-018`
- Affected TC: `TC-011`, `TC-012`, `TC-015`, `TC-023`
- Evidence: `docs/1.0.0/qa/evidence/logs/simulator_install_launch.txt`; screenshots under `docs/1.0.0/qa/evidence/screenshots/`
- Finding: QA successfully created an iPhone simulator, installed the app, launched it, granted camera permission, uninstalled/reinstalled, and captured screenshots. However, command-only execution did not conclusively prove all required iOS visual surfaces, especially App Library/Search and App Switcher.
- Reproduction / Completion Steps: Open simulator `QA-vino-iPhone-1.0.0`, confirm `灵眼GX` icon visually on Home Screen, App Library/Search, Settings app entry, and App Switcher after clean uninstall/reinstall, then attach screenshots or photos that clearly show each surface.
- Expected: Every required simulator icon surface shows the correct app icon and display name after cache-controlled install.
- Actual: Evidence is incomplete/inconclusive for the full required simulator surface matrix.
- Release Impact: Release cannot be approved while a required visual icon check remains incomplete.
- Ownership: QA/manual validation or automation harness; no implementation defect is confirmed by current evidence.

## ISSUE-002: Physical iPhone install and visual icon coverage unavailable

- Status: OPEN
- Severity: Blocker
- Type: External environment coverage gap
- Affected AC: `AC-001`, `AC-012`, `AC-016`, `AC-017`, `AC-018`
- Affected TC: `TC-013`, `TC-014`, `TC-015`, `TC-018`, `TC-023`
- Evidence: `docs/1.0.0/qa/evidence/logs/xctrace_devices.txt`; `docs/1.0.0/qa/evidence/logs/devicectl_devices.txt`
- Finding: Device discovery commands list iPhone devices as offline or unavailable. QA could not install the candidate on a physical iPhone and could not capture required Home Screen, Search/App Library, Settings, App Switcher, launch, or uninstall/reinstall evidence.
- Reproduction / Completion Steps: Connect/trust an eligible physical iPhone, ensure development signing/provisioning is available, install target `cc.vino.iphone`, perform uninstall/reinstall or controlled upgrade, capture the required icon surfaces, and record device model/iOS version/install method.
- Expected: At least one physical iPhone shows the correct `灵眼GX` icon on all required surfaces after cache-controlled install.
- Actual: No usable physical iPhone install target was available during QA execution.
- Release Impact: Release cannot be approved because physical iPhone evidence is mandatory and cannot be substituted by simulator evidence.
- Ownership: External test environment/signing/device availability; no implementation defect is confirmed by current evidence.

## Closed / Non-Issues

| Item | Classification | Rationale |
|---|---|---|
| Thinned Debug simulator `Assets.car` omitted 2x renditions | Non-issue | The first assetutil check inspected a thinned product for a 3x simulator. Unthinned Debug evidence later contains all 2x/3x/marketing renditions and Release evidence is complete. |
| `0.1.0` references in docs | Non-issue | References are baseline/history mentions or negative examples. Delivered build settings and built plists resolve to `1.0.0`. |
