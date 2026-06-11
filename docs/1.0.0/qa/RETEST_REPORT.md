# Retest Report: vino_iPhone 1.0.0

## 1. Retest Summary

| Total Fixed Claims | Verified Fixed | Reopened | Blocked |
|---:|---:|---:|---:|
| 0 | 0 | 0 | 2 |

## 2. Issue Retest Results

| Issue ID | Fixer Status | Retest Result | Evidence | Notes |
|---|---|---|---|---|
| `ISSUE-001` | `NEEDS_PRODUCT_DECISION` | BLOCKED | `docs/1.0.0/qa/QA_TEST_RUN.md`; `docs/1.0.0/qa/evidence/logs/simulator_install_launch.txt` | No code fix was claimed. Simulator install/launch evidence still exists, but full visual-surface proof remains incomplete. |
| `ISSUE-002` | `NEEDS_PRODUCT_DECISION` | BLOCKED | Fresh `xcrun devicectl list devices` retest still reports iPhones as `unavailable`. | No code fix was claimed. Physical iPhone install and screenshot/photo coverage remains unavailable. |

## 3. Regression Results

| Area | Result | Notes |
|---|---|---|
| AppIcon catalog JSON | PASS | Retest parsed `Contents.json`: 9 entries, all expected iPhone and marketing slots present. |
| PNG metadata | PASS | Retest checked all 9 PNGs with `sips`; dimensions match expected sizes and `hasAlpha: no`. |
| Debug build settings | PASS | Retest confirms `AppIcon`, `MARKETING_VERSION = 1.0.0`, `TARGETED_DEVICE_FAMILY = 1`, iPhone platforms, and disabled Mac/Catalyst/XR flags. |
| Release build settings | PASS | Retest confirms the same required settings in Release. |
| Physical device availability | BLOCKED | `devicectl` still lists available iPhone candidates as `unavailable`; physical install cannot be completed in this environment. |
| Initial retest filtering command | BLOCKED_RESOLVED | `rg` is not installed in this shell, so retest reran build-setting extraction with `grep -E`; final build-setting evidence passed. |

## 4. Reopened Issues

No previously fixed issue was reopened because Fixer did not claim any issue as fixed.

## 5. Retest Decision

RETEST_FAILED

Rationale: implementation regression checks still pass, but the two open Blocker issues remain unresolved. Release Judge must not approve RC while simulator visual proof and physical iPhone coverage are incomplete.
