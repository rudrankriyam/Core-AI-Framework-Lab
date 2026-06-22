# CI verification matrix

The versioned contract in `verification-matrix.v1.json` separates checks that
can run on GitHub-hosted infrastructure from evidence that requires Apple's
Xcode 27 SDK or a real iOS device. Validate it with:

```bash
python3 Scripts/ci_matrix.py validate
python3 -m unittest discover -s Scripts/tests -p 'test_*.py'
```

| Lane | Trigger | Runner labels | What it proves |
| --- | --- | --- | --- |
| Hosted software | Pull requests, `main`, manual | `ubuntu-latest` | The matrix contract and Python device-harness behavior work without Xcode, signing, credentials, downloaded weights, or a device. It does not prove Swift compilation or Core AI execution. |
| Xcode 27 macOS | Trusted `main` pushes and manual runs from `main` | `self-hosted`, `macOS`, `ARM64`, `coreai-xcode27`, `coreai-macos-contracts` | The checked-in project builds and its default macOS contract tests pass with the macOS 27 SDK. Opt-in real-model tests remain disabled. |
| Physical iOS 27 | Approval-gated manual runs from `main` | `self-hosted`, `macOS`, `ARM64`, `coreai-xcode27`, `coreai-ios-device` | The deterministic workbench fixture produces exactly one passing, unskipped test attributed to the attached physical iOS 27+ device. |

Hardware workflows never run for pull requests. This prevents unreviewed code
from executing on persistent self-hosted machines. A manual hardware run is
also rejected unless its selected ref is `refs/heads/main`. Every external
action is pinned to a reviewed full commit SHA; repository administrators should
also restrict Actions to selected actions and require full-SHA pinning.

## Xcode 27 macOS runner

Register an Apple-silicon self-hosted runner with the five labels above. Do not
put `coreai-macos-contracts` on the physical-device runner: that separation
prevents automatic macOS jobs from running beside installed signing keys. The
macOS runner needs:

- Xcode 27 at `/Applications/Xcode-beta.app` with its first-launch setup done;
- outbound access for `actions/setup-python` to select the declared Python 3.12
  runtime used by the checked-in validation tools;
- Git LFS and network access to the repository's pinned Swift packages and
  tracked LFS resources; and
- enough free space for the repository assets, Derived Data, and an xcresult.

The workflow forces `CODE_SIGNING_ALLOWED=NO`, clears every opt-in model-test
environment variable, and checks the Xcode and macOS SDK major versions. Raw
build logs and xcresults remain private to the runner and are deleted before the
job uploads its environment manifest and identifier-free test summary for 14
days. Repository LFS assets are present so the macOS resource bundle is
structurally representative, but the lane does not claim real-model inference
or particular compute-unit placement.

## Physical iOS 27 runner

Use a dedicated Apple-silicon runner with all five labels in the matrix and an
attached, paired, unlocked iPhone or iPad running iOS 27 or newer. Developer
Mode and developer services must already work, and Git LFS must be installed.
Configure a protected GitHub environment named `coreai-ios-hardware`, require a
reviewer, and add one secret:

- `COREAI_APPLE_TEAM_ID`: the 10-character team identifier for the installed
  Apple Development identity and development profile.

The runner must already contain the matching private key and exactly one
eligible unexpired development profile covering both `com.rudrank.CoreAILab`
and `com.rudrank.CoreAILabTests` for exactly one eligible attached device. The
workflow does not accept public device/profile selector inputs and never
installs, downloads, or creates signing material.

The runner also needs outbound access for `actions/setup-python`; the workflow
selects Python 3.12 before validating the matrix or invoking the device harness.

The workflow calls `Scripts/run_device_tests.py`, which intentionally never
passes `-allowProvisioningUpdates` or `-allowProvisioningDeviceRegistration`.
It selectively downloads only `CoreAILabTests/Fixtures/**` from LFS, refuses to
continue if a fixture remains an LFS pointer, and never downloads the macOS
model bundle. It then runs only the checked-in deterministic fixture, serializes
access to the device, and validates the private xcresult: success requires
exactly one passed, unskipped test attributed to the selected physical device.
Raw logs and xcresults are suppressed from public job output and deleted before
upload. The retained 14-day artifact contains only a toolchain manifest and an
identifier-free count/platform summary.

This repository is public. Never print or upload device names, UDIDs, profile
names/UUIDs, signing identities, raw xcresults, or raw hardware logs. Access to
the protected `coreai-ios-hardware` environment still must be restricted because
it controls execution beside the installed private key.

## Rollout status

These workflows are configuration, not current hardware evidence. Before
calling either lane operational, provision separate self-hosted runners, create
and reviewer-protect the `coreai-ios-hardware` environment, add its team-ID
secret, enable a selected-actions/full-SHA repository policy, and record a
passing run from `main` for each hardware lane.
