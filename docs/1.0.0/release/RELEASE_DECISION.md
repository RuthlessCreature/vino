# Release Decision: vino_iPhone 1.0.0

## 1. Decision

BLOCKED

## 2. Evidence Summary

| Evidence | Status | Notes |
|---|---|---|
| Spec readiness | PASS | `00_SPEC.md` ends with `SPEC_READY`; acceptance criteria are testable. |
| Builder implementation | PASS | AppIcon legacy iPhone slots added, `MARKETING_VERSION` updated to `1.0.0`, no unrelated runtime code changes. |
| Dev self-check | PASS | Static JSON, PNG metadata, Debug/Release build settings, Debug simulator build, Release generic iOS build, plist, and compiled asset checks pass. |
| QA plan | PASS | 23 test cases cover all acceptance criteria and negative/boundary cases. |
| QA execution | BLOCKED | 16 PASS, 0 FAIL, 7 BLOCKED; required simulator visual proof and physical iPhone proof are incomplete. |
| Fixer | PASS_WITH_OPEN_BLOCKERS | No repository code fix required; issues are evidence/environment blockers. |
| QA retest | BLOCKED | Key static/build-setting regressions pass, but both open Blockers remain unresolved. |

## 3. Open Issues

| Issue ID | Severity | Status | Release Impact |
|---|---|---|---|
| `ISSUE-001` | Blocker | OPEN | Simulator Home Screen, App Library/Search, Settings, App Switcher, launch, and cache-controlled visual evidence is incomplete; release cannot pass. |
| `ISSUE-002` | Blocker | OPEN | Physical iPhone install and visual icon evidence is unavailable; release cannot pass. |

## 4. Untested / Incomplete Areas

| Area | Status | Impact |
|---|---|---|
| iPhone simulator App Library/Search visual proof | BLOCKED | Required icon surface not conclusively proven. |
| iPhone simulator App Switcher visual proof | BLOCKED | Required icon surface not conclusively proven. |
| Physical iPhone Home Screen / Search / Settings / App Switcher | BLOCKED | Mandatory device coverage absent. |
| Physical iPhone uninstall/reinstall or controlled upgrade cache check | BLOCKED | Mandatory cache-boundary evidence absent. |
| Deployment / rollback SOP | GAP | Not the primary blocker, but should be added before release discipline is complete. |

## 5. Accepted Risks

No risks are accepted for RC in this decision. Open Blocker issues cannot be accepted by Release Judge without explicit product/business approval outside this artifact.

## 6. Release Conditions

Release can be reconsidered only after all conditions are met:

| Condition | Required Evidence |
|---|---|
| Close `ISSUE-001` | Conclusive simulator screenshots/photos for Home Screen, App Library/Search, Settings app entry, App Switcher, launch, and reinstall/cache path. |
| Close `ISSUE-002` | Physical iPhone device model/iOS/install method plus photos/screenshots for required surfaces and uninstall/reinstall or controlled upgrade cache behavior. |
| Rerun QA Retest | `qa/RETEST_REPORT.md` updated to show open Blockers resolved and key regressions still passing. |
| Add deployment/rollback SOP | Minimal SOP for installing/verifying/rolling back this iPhone icon release. |

## 7. Final Recommendation

Do not enter RC. The icon implementation and packaging checks are strong, but the release gate requires complete simulator visual proof and physical iPhone proof. With two open Blocker issues, approving RC would violate the iteration quality gate.
