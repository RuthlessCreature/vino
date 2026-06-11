# Release Checklist: vino_iPhone 1.0.0

## 1. Required Evidence

| Evidence | Exists | Status | Notes |
|---|---|---|---|
| `00_SPEC.md` | Yes | PASS | Ends with `SPEC_READY`; covers icon assets, build integration, version, simulator/device evidence, and release blockers. |
| `01_CHANGELOG.md` | Yes | PASS | Documents icon fix and version alignment scope. |
| `02_FEATURE_LIST.md` | Yes | PASS | Lists P0 app icon, build, version, and evidence requirements. |
| `03_WORKFLOW.md` | Yes | PASS | Defines role boundaries and gates. |
| `builder/DEV_NOTES.md` | Yes | PASS | Documents AppIcon slot expansion and `MARKETING_VERSION = 1.0.0`. |
| `builder/SELF_CHECK.md` | Yes | PASS | Static, build-setting, build, plist, and compiled asset checks pass. |
| `builder/BUILD_RESULT.md` | Yes | PASS | Debug simulator and Release generic iOS builds pass. |
| `qa/QA_TEST_PLAN.md` | Yes | PASS | Maps `AC-001` through `AC-018` to test cases. |
| `qa/QA_TEST_CASES.md` | Yes | PASS | Defines 23 test cases including negative and boundary coverage. |
| `qa/QA_TEST_RUN.md` | Yes | BLOCKED | 16 PASS, 0 FAIL, 7 BLOCKED; two open Blocker issues. |
| `qa/ISSUE_LIST.md` | Yes | BLOCKED | `ISSUE-001` and `ISSUE-002` remain OPEN Blocker. |
| `qa/REGRESSION_SUGGESTIONS.md` | Yes | PASS | Suggests automated AppIcon/static/build regressions and manual device checks. |
| `fix/FIX_REPORT.md` | Yes | PASS_WITH_OPEN_BLOCKERS | No implementation fix required; blockers are evidence/device availability gaps. |
| `fix/ISSUE_RESOLUTION.md` | Yes | BLOCKED | Both issues require product decision or additional QA/device evidence. |
| `qa/RETEST_REPORT.md` | Yes | BLOCKED | Retest confirms implementation regression checks pass, but blockers remain. |
| `05_DEPLOYMENT_SOP.md` | No | GAP | No dedicated deployment SOP was created for this icon-only iteration; release remains blocked regardless due open Blockers. |

## 2. Blocking Checks

| Check | Result | Notes |
|---|---|---|
| Open Blocker = 0 | FAIL | Two open Blockers remain: simulator visual evidence incomplete and physical iPhone coverage unavailable. |
| Unaccepted Major = 0 | PASS | No open Major issue recorded. |
| Core tests fully verified | FAIL | Simulator visual surface matrix and physical iPhone surface matrix are incomplete. |
| Release build/package evidence | PASS | Release generic iOS build, built plist, and compiled asset evidence pass. |
| App version is `1.0.0` | PASS | Debug and Release `MARKETING_VERSION` and built plists resolve to `1.0.0`. |
| App identity preserved | PASS | Display name `灵眼GX`, bundle id `cc.vino.iphone`, permissions, and iPhone-only target are preserved. |
| Rollback plan exists | GAP | No formal rollback SOP exists. Reverting AppIcon JSON/PNGs and `MARKETING_VERSION` would be the practical code rollback. |
| Deployment SOP exists | GAP | No separate SOP artifact exists. |

## 3. Acceptance Criteria Status

| Area | Result | Notes |
|---|---|---|
| Static AppIcon catalog and PNG metadata | PASS | `Contents.json`, 9 referenced files, dimensions, and no-alpha checks pass. |
| Debug/Release build integration | PASS | Build settings, clean builds, built plists, and compiled assets pass. |
| Version `1.0.0` consistency | PASS | Build settings and built products align with target version. |
| Simulator visual icon coverage | BLOCKED | Required surfaces are not conclusively proven. |
| Physical iPhone icon coverage | BLOCKED | No usable physical iPhone install target was available. |

## 4. Release Checklist Result

Release checklist result: BLOCKED.
