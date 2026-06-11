# Issue Resolution: vino_iPhone 1.0.0

## ISSUE-001

- Status: NEEDS_PRODUCT_DECISION
- Root Cause: QA could execute simulator install, launch, uninstall/reinstall, and screenshot capture, but could not conclusively prove every required visual surface from command-only evidence.
- Fix: No code fix applied. The AppIcon catalog, PNG metadata, Debug/Release build settings, clean builds, built plists, and unthinned compiled assets already passed independent QA checks.
- Files Changed: None in Fixer phase.
- Evidence: `docs/1.0.0/qa/QA_TEST_RUN.md`; `docs/1.0.0/qa/evidence/logs/simulator_install_launch.txt`; screenshots under `docs/1.0.0/qa/evidence/screenshots/`.
- Regression Test: QA Retest must complete simulator visual surface review for Home Screen, App Library/Search, Settings, App Switcher, launch, and uninstall/reinstall cache behavior.
- Notes: This remains an open release blocker unless QA provides conclusive visual evidence or product explicitly accepts the evidence gap.

## ISSUE-002

- Status: NEEDS_PRODUCT_DECISION
- Root Cause: Physical iPhone devices were reported offline or unavailable by `xctrace` and `devicectl`, so QA could not install or visually verify the app on a real iPhone.
- Fix: No code fix applied. The blocker is external physical-device/signing/test-environment availability.
- Files Changed: None in Fixer phase.
- Evidence: `docs/1.0.0/qa/evidence/logs/xctrace_devices.txt`; `docs/1.0.0/qa/evidence/logs/devicectl_devices.txt`.
- Regression Test: QA Retest must run physical iPhone install, launch, icon-surface screenshots/photos, and uninstall/reinstall or controlled-upgrade cache checks when a device is available.
- Notes: This remains an open release blocker unless physical iPhone coverage is completed or product explicitly accepts release without mandatory device evidence.
